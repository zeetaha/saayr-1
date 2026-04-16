import Foundation
import HealthKit

/// Tracks sensor-recorded steps (excludes iOS Health manual entries) and syncs
/// them to the backend both in the foreground and when the app is woken in the
/// background by HealthKit's observer delivery.
final class HealthKitManager {

    static let shared = HealthKitManager()
    private init() {}

    private let healthStore = HKHealthStore()
    private let stepType   = HKQuantityType(.stepCount)
    private var observerQuery: HKObserverQuery?

    // MARK: - Availability & status

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var authorizationStatus: HKAuthorizationStatus {
        healthStore.authorizationStatus(for: stepType)
    }

    // MARK: - Authorization

    /// Call once after the user authenticates. Re-calling is safe; iOS will
    /// only show the permission sheet the first time.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isAvailable else { completion(false); return }
        healthStore.requestAuthorization(toShare: nil, read: [stepType]) { success, error in
            if let error { print("❌ HealthKit auth error: \(error.localizedDescription)") }
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - Background delivery

    /// Call after authorization is granted. Registers an observer so iOS wakes
    /// the app whenever new step samples are written — even if fully terminated.
    func setupBackgroundDelivery() {
        guard isAvailable else { return }

        healthStore.enableBackgroundDelivery(for: stepType, frequency: .immediate) { [weak self] success, error in
            if let error {
                print("❌ HealthKit BG delivery: \(error.localizedDescription)")
                return
            }
            guard success else { return }
            print("✅ HealthKit background delivery enabled")
            self?.registerObserverQuery()
        }
    }

    /// Call when the user logs out so the observer is released.
    func stopBackgroundDelivery() {
        if let q = observerQuery { healthStore.stop(q) }
        observerQuery = nil
        healthStore.disableAllBackgroundDelivery { _, _ in }
    }

    private func registerObserverQuery() {
        if let existing = observerQuery { healthStore.stop(existing) }

        // Predicate = nil so iOS fires for ANY new step sample
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                print("❌ Observer error: \(error!.localizedDescription)")
                completionHandler() // must always call to avoid iOS throttling
                return
            }
            // completionHandler MUST be called after async work; pass it through
            self?.fetchAndSendTodaySensorSteps(completion: completionHandler)
        }

        observerQuery = query
        healthStore.execute(query)
    }

    // MARK: - Fetch sensor-only steps and send to API

    /// Fetches today's cumulative steps from hardware sensors only (manual
    /// entries added via the iOS Health app are excluded via metadata predicate)
    /// then POSTs to the backend.  Safe to call at any time from any thread.
    func fetchAndSendTodaySensorSteps(completion: (() -> Void)? = nil) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let now        = Date()

        let datePredicate = HKQuery.predicateForSamples(
            withStart: startOfDay, end: now, options: .strictStartDate
        )

        // HKMetadataKeyWasUserEntered == true on every manually-typed entry.
        // This predicate keeps only samples where the flag is absent or false
        // (i.e. recorded by the accelerometer / Apple Watch sensor).
        let notManualPredicate = NSPredicate(
            format: "metadata.%K != YES", HKMetadataKeyWasUserEntered
        )

        let combined = NSCompoundPredicate(
            andPredicateWithSubpredicates: [datePredicate, notManualPredicate]
        )

        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: combined,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            if let error {
                print("❌ Step fetch error: \(error.localizedDescription)")
                completion?()
                return
            }

            let steps = result?.sumQuantity().map {
                Int($0.doubleValue(for: .count()))
            } ?? 0

            print("📊 Sensor-recorded steps today: \(steps)")
            self?.sendStepsToAPI(steps: steps, date: startOfDay, completion: completion)
        }

        healthStore.execute(query)
    }

    // MARK: - API

    /// Uses URLSession directly (not Alamofire) so it works reliably inside
    /// the short background window granted by HealthKit's observer delivery.
    private func sendStepsToAPI(steps: Int, date: Date, completion: (() -> Void)? = nil) {
        guard
            let token = UserModel.shared.user?.accessToken,
            !token.isEmpty
        else {
            print("⚠️ No auth token — skipping step sync")
            completion?()
            return
        }

        guard let url = URL(string: WebService.recordSteps) else {
            completion?()
            return
        }

        // Build ISO-8601 date string (YYYY-MM-DD) for which day the steps belong to
        let isoFull = ISO8601DateFormatter()
        let dateStr = isoFull.string(from: date).prefix(10) // "2026-04-15"

        let body: [String: Any] = [
            "steps": steps,
            "date": String(dateStr),
            "recorded_at": isoFull.string(from: Date())
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion?()
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody   = httpBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        request.setValue(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            forHTTPHeaderField: "App-Version"
        )
        request.setValue(UserModel.shared.languageCode, forHTTPHeaderField: "Language-Code")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                print("❌ Step sync failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                print("✅ Step sync → HTTP \(http.statusCode) | \(steps) steps on \(dateStr)")
            }
            completion?() // always signal HealthKit we're done
        }.resume()
    }
}
