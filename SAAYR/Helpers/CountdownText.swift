import SwiftUI
import Combine

// MARK: - Countdown formatting
//
// Shared by the leaderboard reset and the daily/weekly challenge timers:
// more than an hour left -> "20h remaining" / "5 days remaining"
// under an hour          -> live ticking "MM:SS"

enum CountdownFormat {
    static let urgentThreshold: TimeInterval = 3600

    static func text(until deadline: Date, now: Date = Date(), isEnglish: Bool = true) -> String {
        let seconds = Int(deadline.timeIntervalSince(now).rounded())
        guard seconds > 0 else {
            return isEnglish ? "Resetting…" : "جارٍ التحديث…"
        }

        if seconds < Int(urgentThreshold) {
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }

        let days = seconds / 86400
        if days >= 1 {
            if isEnglish {
                return days == 1 ? "1 day remaining" : "\(days) days remaining"
            }
            return days == 1 ? "متبقي يوم واحد" : "متبقي \(days) أيام"
        }

        let hours = seconds / 3600
        return isEnglish ? "\(hours)h remaining" : "متبقي \(hours) ساعة"
    }

    /// True once the display should tick every second (under an hour left).
    static func isUrgent(deadline: Date, now: Date = Date()) -> Bool {
        let remaining = deadline.timeIntervalSince(now)
        return remaining > 0 && remaining < urgentThreshold
    }

    /// Parses a deadline out of what the API sends: an ISO timestamp when available,
    /// otherwise a pre-formatted string such as "Reset in 8h", "20h remaining", "5 days remaining".
    static func deadline(fromISO iso: String?, orDurationText text: String?, now: Date = Date()) -> Date? {
        if let date = UserManager.parseISODate(iso) { return date }
        guard let text = text, let seconds = durationSeconds(from: text) else { return nil }
        return now.addingTimeInterval(seconds)
    }

    /// Pulls a duration out of strings like "Reset in 8h", "2d 3h", "45m", "5 days remaining".
    static func durationSeconds(from text: String) -> TimeInterval? {
        let lowered = text.lowercased()
        var total: TimeInterval = 0
        var matched = false

        let units: [(pattern: String, multiplier: TimeInterval)] = [
            ("(\\d+)\\s*(?:d|day|days)\\b", 86400),
            ("(\\d+)\\s*(?:h|hr|hrs|hour|hours)\\b", 3600),
            ("(\\d+)\\s*(?:m|min|mins|minute|minutes)\\b", 60),
            ("(\\d+)\\s*(?:s|sec|secs|second|seconds)\\b", 1)
        ]

        for unit in units {
            guard let regex = try? NSRegularExpression(pattern: unit.pattern) else { continue }
            let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
            guard let match = regex.firstMatch(in: lowered, range: range),
                  let valueRange = Range(match.range(at: 1), in: lowered),
                  let value = Double(lowered[valueRange]) else { continue }
            total += value * unit.multiplier
            matched = true
        }

        return matched ? total : nil
    }
}

// MARK: - CountdownText

/// Renders a countdown to `deadline`, ticking every second once under an hour remains
/// and once a minute before that. Styling is left to the caller.
struct CountdownText: View {
    let deadline: Date
    var isEnglish: Bool = true
    /// Colors are applied here (rather than by the caller) so the switch to the urgent
    /// color happens on this view's own tick, not on the parent's next redraw.
    var color: Color = .gray
    var urgentColor: Color? = nil

    @State private var now = Date()

    var body: some View {
        Text(CountdownFormat.text(until: deadline, now: now, isEnglish: isEnglish))
            .monospacedDigit()
            .foregroundColor(
                CountdownFormat.isUrgent(deadline: deadline, now: now) ? (urgentColor ?? color) : color
            )
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                // Away from the reset a minute-level refresh is enough; near it, tick every second.
                if CountdownFormat.isUrgent(deadline: deadline, now: date)
                    || date.timeIntervalSince(now) >= 30 {
                    now = date
                }
            }
            .onAppear { now = Date() }
    }
}
