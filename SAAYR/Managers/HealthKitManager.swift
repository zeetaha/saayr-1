import Foundation
import HealthKit
import CoreMotion
import Combine
/// Two complementary step-tracking systems:
///
/// 1. **CMPedometer** — real-time, motion-coprocessor accuracy.
///    Used while the app is open. Fires on every step.
///
/// 2. **HKObserverQuery** — background delivery.
///    iOS wakes the app when new HealthKit samples arrive (including from
///    Apple Watch) and we send a daily total to the backend.
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()
    private init() {}

    // MARK: - Published

    /// Live cumulative step count for today (updated in real time via CMPedometer).
    @Published var liveStepCount: Int = 0

    // MARK: - Private

    private let healthStore   = HKHealthStore()
    private let stepType      = HKQuantityType(.stepCount)
    private let pedometer     = CMPedometer()
    private var observerQuery: HKObserverQuery?

    private var lastSyncedSteps: Int = 0
    private var lastSyncDate:    Date = .distantPast

    // MARK: - HealthKit availability & auth

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var authorizationStatus: HKAuthorizationStatus {
        healthStore.authorizationStatus(for: stepType)
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isAvailable else { completion(false); return }
        healthStore.requestAuthorization(toShare: nil, read: [stepType]) { success, error in
            if let error { print("❌ HealthKit auth: \(error.localizedDescription)") }
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - Real-time live tracking (CMPedometer)

    /// Start live step updates from the motion coprocessor.
    /// Call this from `onAppear` / `scenePhase == .active`.
    func startLiveTracking() {
        guard CMPedometer.isStepCountingAvailable() else {
            print("⚠️ CMPedometer not available on this device")
            return
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())

        pedometer.startUpdates(from: startOfDay) { [weak self] data, error in
            guard let self, let data, error == nil else { return }

            let steps = data.numberOfSteps.intValue

            DispatchQueue.main.async {
                self.liveStepCount = steps
            }

            // Debounce API sync: only send if ≥60 s have passed AND steps changed
            let now = Date()
            let stepDelta = abs(steps - self.lastSyncedSteps)
            let secondsSinceSync = now.timeIntervalSince(self.lastSyncDate)

            if secondsSinceSync >= 60 && stepDelta > 0 {
                self.lastSyncedSteps = steps
                self.lastSyncDate    = now
                self.sendStepsToAPI(steps: steps, date: startOfDay, source: "pedometer")
            }
        }

        print("🏃 CMPedometer live tracking started")
    }

    /// Stop live tracking. Call from `onDisappear` / `scenePhase != .active`.
    func stopLiveTracking() {
        pedometer.stopUpdates()
        print("⏹ CMPedometer live tracking stopped")
    }

    // MARK: - HealthKit background delivery

    /// Enables background delivery so iOS wakes the app when new step data
    /// arrives (e.g. Apple Watch syncing after a workout).
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

    func stopBackgroundDelivery() {
        if let q = observerQuery { healthStore.stop(q) }
        observerQuery = nil
        healthStore.disableAllBackgroundDelivery { _, _ in }
    }

    private func registerObserverQuery() {
        if let existing = observerQuery { healthStore.stop(existing) }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                print("❌ HK observer error: \(error!.localizedDescription)")
                completionHandler()
                return
            }
            self?.fetchAndSendTodaySensorSteps(completion: completionHandler)
        }

        observerQuery = query
        healthStore.execute(query)
    }

    // MARK: - HealthKit batch fetch (background / on-demand)

    /// Fetches today's sensor-only steps from HealthKit and sends to the API.
    /// Manual entries (added via iOS Health app) are filtered out.
    func fetchAndSendTodaySensorSteps(completion: (() -> Void)? = nil) {
        let startOfDay = Calendar.current.startOfDay(for: Date())

        let datePredicate = HKQuery.predicateForSamples(
            withStart: startOfDay, end: Date(), options: .strictStartDate
        )
        // Exclude manually typed entries — HKMetadataKeyWasUserEntered == true on those
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
                print("❌ HK step fetch: \(error.localizedDescription)")
                completion?()
                return
            }
            let steps = result?.sumQuantity().map {
                Int($0.doubleValue(for: .count()))
            } ?? 0

            print("📊 Sensor steps today (HK): \(steps)")
            self?.sendStepsToAPI(steps: steps, date: startOfDay, completion: completion)
        }

        healthStore.execute(query)
    }

    // MARK: - API

    /// Uses URLSession directly so this works inside HealthKit's short
    /// background execution window (Alamofire sessions may be suspended).
    private func sendStepsToAPI(steps: Int, date: Date, source: String = "healthkit", completion: (() -> Void)? = nil) {
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

        let iso       = ISO8601DateFormatter()
        let now       = Date()
        let dateStr   = String(iso.string(from: date).prefix(10)) // "2026-04-18"
        let cal     = Calendar.current
        let hour    = cal.component(.hour,   from: now) // 0–23
        let minute  = cal.component(.minute, from: now) // 0–59

        let body: [String: Any] = [
            "steps":       steps,
            "date":        dateStr,
            "hour":        hour,
            "minute":      minute,
            "recorded_at": iso.string(from: now),
            "source":      source   // "pedometer" = live (CMPedometer) | "healthkit" = background batch
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
            completion?()
        }.resume()
    }
}
