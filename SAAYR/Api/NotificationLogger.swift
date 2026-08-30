//
//  NotificationLogger.swift
//  SAAYR
//
//  Console logging for notifications, in the same shape as APILogger and
//  SSELogger so the three read side by side. DEBUG only — payloads routinely
//  carry ids and deep links that have no business in a release build's log.
//
//  Covers all three ways a notification reaches the app: arriving while it's
//  open, being tapped, and cold-launching it. The last one is the easiest to
//  miss, because the app wasn't running to see anything arrive.
//

#if DEBUG
import Foundation
import UIKit
import UserNotifications

/// ```
/// 🔔 FOREGROUND  Boss LIVE — join now!
///    body:     The boss has spawned. Join the fight.
///    identifier: boss-17-live   category: BOSS
///    payload:  {"boss_id":17,"type":"boss_live"}
/// 👆 TAP  action: default  ·  Boss LIVE — join now!
///    payload:  {"boss_id":17,"type":"boss_live"}
/// 🚀 COLD LAUNCH from notification
///    payload:  {"boss_id":17,"type":"boss_live"}
/// ```
enum NotificationLogger {

    /// Set to `false` to silence the log without unpicking the wiring.
    static var isEnabled = true

    /// Payloads are trimmed to this many characters. Generous, because the
    /// whole point of this log is that the payload is what you came to read.
    static var payloadCharacterLimit = 2_000

    /// Whether to print the full `UNNotificationRequest` trigger. Off by
    /// default: for a push it's always nil, and for a scheduled local one
    /// `dumpPending()` is the better view.
    static var logsTrigger = false

    // MARK: - Arrival

    /// The app was open when it arrived.
    static func presented(_ notification: UNNotification) {
        guard isEnabled else { return }
        print("🔔 FOREGROUND  \(title(of: notification.request))")
        printDetail(of: notification.request)
    }

    /// The player tapped it, or picked one of its actions.
    ///
    /// `actionIdentifier` is the field worth watching: it's
    /// `UNNotificationDefaultActionIdentifier` for a plain tap,
    /// `UNNotificationDismissActionIdentifier` for a swipe-away, and your own
    /// string for a custom action button.
    static func acted(on response: UNNotificationResponse) {
        guard isEnabled else { return }

        print("👆 TAP  action: \(actionName(response.actionIdentifier))  ·  \(title(of: response.notification.request))")
        if let textResponse = response as? UNTextInputNotificationResponse {
            print("   typed:    \(textResponse.userText)")
        }
        printDetail(of: response.notification.request)
    }

    /// The app wasn't running and a notification started it. Call from
    /// `didFinishLaunchingWithOptions`.
    ///
    /// `didReceive` fires for this too, once the delegate is set — this line
    /// is what tells you the difference between a tap that resumed the app and
    /// a tap that launched it, which is usually the routing bug.
    static func launched(with launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard isEnabled,
              let payload = launchOptions?[.remoteNotification] as? [AnyHashable: Any]
        else { return }

        print("🚀 COLD LAUNCH from notification")
        print("   payload:  \(rendered(payload))")
    }

    // MARK: - Scheduled and delivered

    /// Every local notification currently scheduled but not yet fired.
    /// Asynchronous, so the lines land a beat after the call.
    static func dumpPending() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            guard isEnabled else { return }
            print("⏳ PENDING  \(requests.count) scheduled")
            for request in requests {
                print("   · \(request.identifier)  \(title(of: request))")
                if let trigger = request.trigger {
                    print("     trigger: \(trigger)")
                }
                print("     payload: \(rendered(request.content.userInfo))")
            }
        }
    }

    /// Everything still sitting in Notification Centre.
    static func dumpDelivered() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            guard isEnabled else { return }
            print("📥 DELIVERED  \(notifications.count) in Notification Centre")
            for notification in notifications {
                print("   · \(notification.request.identifier)  \(title(of: notification.request))")
                print("     payload: \(rendered(notification.request.content.userInfo))")
            }
        }
    }

    /// Current authorization and registration state — the first thing to check
    /// when nothing is arriving at all.
    static func dumpSettings() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard isEnabled else { return }
            print("""
            ⚙️ NOTIFICATION SETTINGS
               authorization: \(settings.authorizationStatus.rawValue) \
            (0 notDetermined · 1 denied · 2 authorized · 3 provisional · 4 ephemeral)
               alert: \(settings.alertSetting.rawValue)  \
            sound: \(settings.soundSetting.rawValue)  badge: \(settings.badgeSetting.rawValue)
            """)
        }
    }

    // MARK: - Helpers

    private static func printDetail(of request: UNNotificationRequest) {
        let content = request.content

        if !content.body.isEmpty {
            print("   body:     \(content.body)")
        }

        var line = "   identifier: \(request.identifier)"
        if !content.categoryIdentifier.isEmpty {
            line += "   category: \(content.categoryIdentifier)"
        }
        if !content.threadIdentifier.isEmpty {
            line += "   thread: \(content.threadIdentifier)"
        }
        print(line)

        if logsTrigger, let trigger = request.trigger {
            print("   trigger:  \(trigger)")
        }

        print("   payload:  \(rendered(content.userInfo))")
    }

    private static func title(of request: UNNotificationRequest) -> String {
        let content = request.content
        let text = [content.title, content.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return text.isEmpty ? "(no title)" : text
    }

    /// Maps the two system action identifiers onto something readable and
    /// leaves custom ones as they are.
    private static func actionName(_ identifier: String) -> String {
        switch identifier {
        case UNNotificationDefaultActionIdentifier: return "default (opened)"
        case UNNotificationDismissActionIdentifier: return "dismiss (swiped away)"
        default: return identifier
        }
    }

    /// Pretty JSON when the payload is JSON-shaped — which an APNs one always
    /// is — and the raw dictionary when it isn't, so a non-serializable value
    /// still prints instead of silently logging nothing.
    private static func rendered(_ payload: [AnyHashable: Any]) -> String {
        guard !payload.isEmpty else { return "(empty)" }

        let text: String
        if JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
           ),
           let json = String(data: data, encoding: .utf8) {
            // Indented to sit under the "payload:" label rather than against
            // the left margin, where it reads as separate output.
            text = json.replacingOccurrences(of: "\n", with: "\n   ")
        } else {
            text = String(describing: payload)
        }

        guard text.count > payloadCharacterLimit else { return text }
        return text.prefix(payloadCharacterLimit) + "… (\(text.count) chars)"
    }
}
#endif
