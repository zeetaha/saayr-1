//
//  StepsSyncPush.swift
//  SAAYR
//
//  The backend can't read HealthKit, so when it wants steps it sends a silent
//  push and the app answers with one `POST steps/sync`. Nothing else calls
//  that endpoint — the everyday syncs go to `record-steps`.
//
//  Payload (APNs `content-available: 1`, no alert):
//    { "type": "steps_sync", "from": "2026-09-01", "to": "2026-09-24" }
//  `from` / `to` (or `from_date` / `to_date`) are device-local calendar days,
//  both optional (default today).
//  A range longer than `HealthKitManager.maxRequestedDays` is trimmed to the
//  most recent days.
//
//  Delivery is best effort: iOS throttles silent pushes, never delivers them
//  to a force-quit app, and HealthKit is unreadable while the phone is locked.
//

import UIKit
import os

enum StepsSyncPush {

    static func handle(_ userInfo: [AnyHashable: Any],
                       completion: @escaping (UIBackgroundFetchResult) -> Void) {
        let log     = HealthKitManager.log
        let started = Date()
        let state: String = switch UIApplication.shared.applicationState {
            case .active:     "foreground"
            case .inactive:   "inactive"
            case .background: "background"
            @unknown default: "unknown"
        }
        log.log("📩 steps_sync push received (app \(state, privacy: .public)) from=\(string(userInfo, "from") ?? "-", privacy: .public) to=\(string(userInfo, "to") ?? "-", privacy: .public)")

        guard let token = UserModel.shared.currentAccessToken, !token.isEmpty else {
            log.error("⏭ Skipped — nobody is logged in")
            completion(.noData)
            return
        }

        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        let to    = day(string(userInfo, "to")) ?? today
        var from  = day(string(userInfo, "from")) ?? to

        // Keep the newest days when the range is too long for one wake.
        if let earliest = cal.date(byAdding: .day, value: -(HealthKitManager.maxRequestedDays - 1), to: to),
           from < earliest {
            from = earliest
        }

        let fmt = HealthKitManager.dayFormatter
        log.log("🔎 Reading \(fmt.string(from: from), privacy: .public) … \(fmt.string(from: to), privacy: .public)")

        let extra: [String: Any] = [
            "app_state":      state,
            "requested_from": string(userInfo, "from") ?? NSNull(),
            "requested_to":   string(userInfo, "to") ?? NSNull()
        ]
        HealthKitManager.shared.syncSteps(from: from, to: to, extra: extra) { ok in
            // iOS allows ~30 s per wake; going over gets the app throttled.
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            if ok {
                log.log("🏁 steps_sync done in \(seconds, privacy: .public)s — .newData")
            } else {
                log.error("🏁 steps_sync FAILED in \(seconds, privacy: .public)s — .failed")
            }
            completion(ok ? .newData : .failed)
        }
    }

    /// Accepts `from` / `to` and the backend's `from_date` / `to_date`.
    private static func string(_ userInfo: [AnyHashable: Any], _ key: String) -> String? {
        (userInfo[key] ?? userInfo["\(key)_date"]) as? String
    }

    private static func day(_ string: String?) -> Date? {
        string.flatMap(HealthKitManager.dayFormatter.date(from:))
    }
}
