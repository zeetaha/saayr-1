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
            self?.sendStepsToAPI(steps: steps, date: startOfDay) { _ in completion?() }
        }

        healthStore.execute(query)
    }

    // MARK: - Backend-requested sync (silent push)

    /// Longest range one silent push may ask for. iOS gives a background
    /// wake about 30 seconds, and every day in the range is its own request.
    static let maxRequestedDays = 31

    /// Reads sensor-only steps for each calendar day from `from` through `to`
    /// (inclusive, device-local days) and posts one record per day. Days with
    /// no steps are sent as 0 so the backend can tell "asked and answered"
    /// apart from "never synced".
    ///
    /// `completion(true)` only when every day was read and accepted — HealthKit
    /// can't be read while the phone is locked, so a push that lands then
    /// reports failure and the backend should ask again later.
    func syncSteps(from: Date, to: Date, source: String, completion: @escaping (Bool) -> Void) {
        guard isAvailable else { completion(false); return }

        let cal   = Calendar.current
        let start = cal.startOfDay(for: from)
        let today = cal.startOfDay(for: Date())
        let last  = min(cal.startOfDay(for: to), today)
        guard start <= last,
              let end = cal.date(byAdding: .day, value: 1, to: last)
        else { completion(false); return }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        let notManualPredicate = NSPredicate(
            format: "metadata.%K != YES", HKMetadataKeyWasUserEntered
        )
        let combined = NSCompoundPredicate(
            andPredicateWithSubpredicates: [datePredicate, notManualPredicate]
        )

        let query = HKStatisticsCollectionQuery(
            quantityType: stepType,
            quantitySamplePredicate: combined,
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        query.initialResultsHandler = { [weak self] _, results, error in
            guard let self, let results, error == nil else {
                print("❌ HK step range fetch: \(error?.localizedDescription ?? "no results")")
                completion(false)
                return
            }

            var days: [(date: Date, steps: Int)] = []
            results.enumerateStatistics(from: start, to: last) { stats, _ in
                let steps = stats.sumQuantity().map { Int($0.doubleValue(for: .count())) } ?? 0
                days.append((stats.startDate, steps))
            }
            print("📊 Requested step sync: \(days.count) day(s)")

            let group = DispatchGroup()
            var allSent = true
            let lock = NSLock()
            for day in days {
                group.enter()
                self.sendStepsToAPI(steps: day.steps, date: day.date, source: source) { ok in
                    lock.lock(); allSent = allSent && ok; lock.unlock()
                    group.leave()
                }
            }
            group.notify(queue: .main) { completion(allSent) }
        }

        healthStore.execute(query)
    }

    // MARK: - API

    /// Uses URLSession directly so this works inside HealthKit's short
    /// background execution window (Alamofire sessions may be suspended).
    private func sendStepsToAPI(steps: Int, date: Date, source: String = "healthkit", completion: ((Bool) -> Void)? = nil) {
        guard
            let token = UserModel.shared.currentAccessToken,
            !token.isEmpty
        else {
            print("⚠️ No auth token — skipping step sync")
            completion?(false)
            return
        }

        guard let url = URL(string: WebService.recordSteps) else {
            completion?(false)
            return
        }

        let iso       = ISO8601DateFormatter()
        let now       = Date()
        let dateStr   = Self.dayFormatter.string(from: date) // "2026-04-18", device-local day
        let cal     = Calendar.current
        let hour    = cal.component(.hour,   from: now) // 0–23
        let minute  = cal.component(.minute, from: now) // 0–59

        let body: [String: Any] = [
            "steps":       steps,
            "date":        dateStr,
            "hour":        hour,
            "minute":      minute,
            "recorded_at": iso.string(from: now),
            "source":      source   // "pedometer" = live (CMPedometer) | "healthkit" = background batch | "silent_push" = backend-requested
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion?(false)
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
            var ok = false
            if let error {
                print("❌ Step sync failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                print("✅ Step sync → HTTP \(http.statusCode) | \(steps) steps on \(dateStr)")
                ok = (200..<300).contains(http.statusCode)
            }
            completion?(ok)
        }.resume()
    }

    /// Calendar day in the device's own timezone. ISO8601DateFormatter works
    /// in UTC, which put a Riyadh midnight on the previous day's date.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar   = Calendar(identifier: .gregorian)
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
