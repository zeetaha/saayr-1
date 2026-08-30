//
//  BossPush.swift
//  SAAYR
//
//  What the app does with a boss push. Kept out of the AppDelegate so the
//  payload contract lives in one place rather than being read twice — once
//  when a notification arrives in the foreground and once when it's tapped.
//

import Foundation

extension Notification.Name {
    /// A boss push says the banner is now out of date. Posted rather than
    /// called directly because the screen that owns the banner isn't
    /// reachable from the app delegate.
    static let bossBannerNeedsRefresh = Notification.Name("bossBannerNeedsRefresh")
}

enum BossPush {

    /// The `type` values the server sends. All three mean the same thing to
    /// the client — the banner it is showing is now out of date — and differ
    /// only in which way the boss moved.
    enum Kind: String {
        case scheduled = "boss_scheduled"
        case live = "boss_live"
        case ended = "boss_ended"
    }

    /// Acts on a notification payload if it's one of ours.
    ///
    /// Returns whether it was handled, so a caller that wants to fall through
    /// to other handling can tell.
    @discardableResult
    static func handle(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let type = userInfo["type"] as? String else { return false }

        switch Kind(rawValue: type) {
        case .scheduled, .live, .ended:
            // Always a re-read, never a patch from the payload: the push
            // carries `boss_id` as a string and none of the state, timings or
            // image the banner renders. The endpoint is the only thing that
            // knows what the banner should say now.
            NotificationCenter.default.post(name: .bossBannerNeedsRefresh, object: nil)
            return true

        case nil:
            #if DEBUG
            print("🔔 boss push: no handler for type '\(type)'")
            #endif
            return false
        }
    }
}
