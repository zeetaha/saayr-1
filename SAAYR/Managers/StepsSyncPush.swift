//
//  StepsSyncPush.swift
//  SAAYR
//
//  The backend can't read HealthKit, so when it wants steps it sends a silent
//  push and the app answers by posting them to `record-steps`.
//
//  Payload (APNs `content-available: 1`, no alert):
//    { "type": "steps_sync", "from": "2026-09-01", "to": "2026-09-24" }
//  `from` / `to` are device-local calendar days, both optional (default today).
//  A range longer than `HealthKitManager.maxRequestedDays` is trimmed to the
//  most recent days.
//
//  Delivery is best effort: iOS throttles silent pushes, never delivers them
//  to a force-quit app, and HealthKit is unreadable while the phone is locked.
//

import UIKit

enum StepsSyncPush {

    static func handle(_ userInfo: [AnyHashable: Any],
                       completion: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let token = UserModel.shared.currentAccessToken, !token.isEmpty else {
            completion(.noData)
            return
        }

        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        let to    = day(userInfo["to"]) ?? today
        var from  = day(userInfo["from"]) ?? to

        // Keep the newest days when the range is too long for one wake.
        if let earliest = cal.date(byAdding: .day, value: -(HealthKitManager.maxRequestedDays - 1), to: to),
           from < earliest {
            from = earliest
        }

        HealthKitManager.shared.syncSteps(from: from, to: to, source: "silent_push") { ok in
            completion(ok ? .newData : .failed)
        }
    }

    private static func day(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return HealthKitManager.dayFormatter.date(from: string)
    }
}
