//
//  BossViews.swift
//  SAAYR
//
//  Shared furniture for the boss feature: the palette, the countdown, the HP
//  bar and the two cards that lead into it — the home banner and the card
//  inside Challenges.
//

import SwiftUI
import Combine
import Kingfisher

// MARK: - Palette

/// The boss runs hot and dark against the rest of the app, which is light and
/// green. That contrast is the point: a boss is a limited event, and it should
/// look like an intrusion on the ordinary screens.
enum BossStyle {
    static let surface     = Color(hex: "#141821")
    static let surfaceEdge = Color(hex: "#232A38")
    static let ember       = Color(hex: "#F97316")
    static let emberDeep   = Color(hex: "#C2410C")
    static let live        = Color(hex: "#EF4444")
    static let gold        = Color(hex: "#F5C542")
    static let textPrimary = Color(hex: "#F8FAFC")
    static let textDim     = Color(hex: "#94A3B8")

    static var emberGradient: LinearGradient {
        LinearGradient(colors: [ember, emberDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Countdown

/// `HH:MM:SS` ticking down to `deadline`, with a leading day count once more
/// than a day remains.
///
/// Deliberately not `CountdownText`: that one switches to prose ("20h
/// remaining") above an hour, which is right for a weekly reset but wrong
/// here — a raid countdown is meant to feel like a clock running out.
struct BossCountdownText: View {
    let deadline: Date
    var monospaced: Bool = true

    @State private var remaining: Int = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(Self.format(remaining))
            .monospacedDigit()
            .onAppear { remaining = Self.secondsLeft(to: deadline) }
            .onReceive(tick) { _ in remaining = Self.secondsLeft(to: deadline) }
    }

    private static func secondsLeft(to date: Date) -> Int {
        max(0, Int(date.timeIntervalSinceNow.rounded()))
    }

    static func format(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let secs = seconds % 60

        if days > 0 {
            return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, secs)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

/// "starts in 02:14:09" until the moment arrives, then "Waiting…".
///
/// A countdown sitting at 00:00:00 reads as broken, and the state it's waiting
/// on is the server's: the banner still says `scheduled` until the backend
/// flips it, which can be a beat after the clock runs out. `Waiting…` says
/// that honestly, and it holds until a refresh brings back a different state
/// — at which point the card renders its live detail instead of this.
struct BossStartsInLabel: View {

    let startsAt: Date?
    let isEnglish: Bool

    @State private var hasStarted = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let startsAt, !hasStarted {
                HStack(spacing: 4) {
                    Text(isEnglish ? "starts in" : "يبدأ خلال")
                        .font(.system(size: 11))
                        .foregroundColor(BossStyle.textDim)

                    BossCountdownText(deadline: startsAt)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BossStyle.ember)
                }
            } else {
                // Also the no-start-time case: a scheduled boss the server
                // hasn't given a time for is waiting on exactly the same
                // thing, and "starts in —" says less.
                Text(isEnglish ? "Waiting…" : "…في الانتظار")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(BossStyle.textDim)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    private func refresh() {
        hasStarted = (startsAt?.timeIntervalSinceNow ?? 0) <= 0
    }
}

// MARK: - HP bar

/// The boss's remaining health. Drains right-to-left as the community lands
/// hits, so the fill is the share still standing.
struct BossHPBar: View {
    /// 0…100.
    let percent: Int
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))

                Capsule()
                    .fill(BossStyle.emberGradient)
                    .frame(width: geo.size.width * fraction)
                    // Animated on the value so an SSE tick slides the bar
                    // rather than snapping it.
                    .animation(.easeOut(duration: 0.6), value: percent)
            }
        }
        .frame(height: height)
    }

    private var fraction: CGFloat {
        CGFloat(min(100, max(0, percent))) / 100
    }
}

// MARK: - Stat tile

/// One of the three numbers a player cares about: their damage, their share,
/// their rank. Rank is the one worth winning, so it gets the gold treatment.
struct BossStatTile: View {
    let value: String
    let label: String
    var highlighted: Bool = false

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(highlighted ? BossStyle.gold : BossStyle.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(BossStyle.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(highlighted ? BossStyle.gold.opacity(0.14) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(highlighted ? BossStyle.gold.opacity(0.55) : .clear, lineWidth: 1)
        )
    }
}

// MARK: - Boss avatar

/// The boss's portrait, falling back to a mask when it has no image.
struct BossAvatar: View {
    let imageURL: String?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(BossStyle.emberGradient)

            if let resolved = WebService.resolvedImageUrl(imageURL),
               let url = URL(string: resolved) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Text("👹").font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
    }
}

// MARK: - Map marker

/// How a boss target looks on the map. Reads as "go here to hit the boss"
/// rather than as an ordinary merchant, which is the whole reason the flag
/// exists — an on-site boss is otherwise asking players to go somewhere the
/// map never points at.
struct BossMarkerView: View {

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(BossStyle.ember.opacity(0.35))
                .frame(width: 58, height: 58)
                .scaleEffect(pulse ? 1.7 : 1)
                .opacity(pulse ? 0 : 0.7)
                .animation(
                    .easeOut(duration: 1.8).repeatForever(autoreverses: false),
                    value: pulse
                )

            RoundedRectangle(cornerRadius: 14)
                .fill(BossStyle.emberGradient)
                .frame(width: 46, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(BossStyle.gold.opacity(0.9), lineWidth: 2.5)
                )
                .shadow(color: BossStyle.emberDeep.opacity(0.6), radius: 6)

            Text("⚔️").font(.system(size: 22))
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Map card

/// Shown when a boss target is tapped on the map. It's still an ordinary
/// check-in — that's how the damage is dealt — so the check-in button stays;
/// what's added is why it matters and a way into the fight.
struct BossLocationCard: View {

    let location: NearbyLocationResponse
    /// The live boss, when there is one. Absent means the location is flagged
    /// for the event but nothing is running, so there's no battle to open.
    let bossName: String?
    let canOpenBattle: Bool
    let isEnglish: Bool
    let isCheckingIn: Bool
    let onCheckIn: () -> Void
    let onOpenBattle: () -> Void
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BossStyle.emberGradient)
                            .frame(width: 52, height: 52)
                        Text("⚔️").font(.system(size: 24))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(location.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(BossStyle.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(damageLine)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BossStyle.ember)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 30)
                }

                if let reason = blockedReason {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundColor(BossStyle.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button(action: onCheckIn) {
                        Group {
                            if isCheckingIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#1A1206")))
                            } else {
                                Text(isEnglish
                                     ? "Check In (+\(location.xp_reward) XP)"
                                     : "سجّل حضورك (+\(location.xp_reward) نقطة)")
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                        .foregroundColor(Color(hex: "#1A1206"))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(location.can_checkin ? BossStyle.gold : BossStyle.gold.opacity(0.35))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!location.can_checkin || isCheckingIn)

                    if canOpenBattle {
                        Button(action: onOpenBattle) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(BossStyle.ember)
                                .frame(width: 50, height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(BossStyle.ember.opacity(0.16))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isEnglish ? "Open the battle" : "افتح المعركة")
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24).fill(BossStyle.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(BossStyle.ember.opacity(0.5), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(BossStyle.textDim)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .padding(10)
                    .accessibilityLabel(isEnglish ? "Close" : "إغلاق")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var damageLine: String {
        guard let bossName else {
            return isEnglish ? "Boss event location" : "موقع معركة الزعيم"
        }
        return isEnglish
            ? "Checking in here damages \(bossName)"
            : "تسجيل الحضور هنا يضر \(bossName)"
    }

    /// The same `can_checkin` the ordinary card obeys — a boss target on
    /// cooldown or out of range can't be hit either, and saying so beats a
    /// dead button.
    private var blockedReason: String? {
        guard !location.can_checkin else { return nil }
        if let minutes = location.cooldown_remaining_minutes, minutes > 0 {
            let hours = minutes / 60
            let text = hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
            return isEnglish ? "Available again in \(text)" : "متاح مجددًا خلال \(text)"
        }
        return isEnglish
            ? "You need to be closer to check in here"
            : "عليك الاقتراب أكثر لتسجيل الحضور"
    }
}

// MARK: - Live pill

struct BossLivePill: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
            Text("LIVE")
                .font(.system(size: 9, weight: .black))
                .tracking(0.6)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(BossStyle.live))
    }
}

// MARK: - Home banner

/// The poster that sits above the pet on the home screen. Shows only when a
/// boss is scheduled or live; the caller drops it entirely otherwise.
struct BossHomeBannerCard: View {

    let banner: BossHomeBanner
    let isEnglish: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                BossAvatar(imageURL: banner.image_url, size: 46)

                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(BossStyle.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if banner.state == .live {
                        liveDetail
                    } else {
                        scheduledDetail
                    }
                }

                Spacer(minLength: 4)

                VStack(spacing: 10) {
                    // The bell reflects a global admin setting, not a per-user
                    // subscription — there is no per-user opt-in to toggle yet,
                    // so it's an indicator rather than a control.
                    if banner.notifications_enabled {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 12))
                            .foregroundColor(BossStyle.gold)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BossStyle.textDim)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(BossStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(banner.state == .live ? BossStyle.live : BossStyle.surfaceEdge,
                            lineWidth: banner.state == .live ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var headline: String {
        if banner.state == .live {
            return isEnglish ? "Boss LIVE — join now!" : "!المعركة مباشرة — انضم الآن"
        }
        guard let name = banner.boss_name else {
            return isEnglish ? "Boss event incoming" : "معركة قادمة"
        }
        return name
    }

    private var liveDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                BossLivePill()
                if let ends = banner.endsAtDate {
                    BossCountdownText(deadline: ends)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BossStyle.textDim)
                }
            }
            if let count = banner.attacker_count {
                Text("⚔️ \(count.formatted()) \(isEnglish ? "attacking" : "يهاجمون")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BossStyle.textDim)
            }
        }
    }

    private var scheduledDetail: some View {
        BossStartsInLabel(startsAt: banner.startsAtDate, isEnglish: isEnglish)
    }
}

// MARK: - Challenges card

/// The boss's slot inside the Challenges screen. Carries the whole lifecycle:
/// sign up, fight, collect.
struct BossChallengeCard: View {

    let boss: BossChallengeSummary
    let isEnglish: Bool
    /// Opens the waitlist, the battle or the rewards, depending on state.
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(spacing: 12) {
                BossAvatar(imageURL: boss.image_url, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(boss.boss_name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(BossStyle.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(BossStyle.textDim)
                }

                Spacer(minLength: 0)
            }

            if boss.state == .live {
                BossHPBar(percent: 100)
                    .padding(.vertical, 2)
            }

            Button(action: onPrimaryAction) {
                Text(ctaTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ctaForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ctaBackground))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(BossStyle.surface))
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            HStack(spacing: 5) {
                Text("⚡️").font(.system(size: 12))
                Text(isEnglish ? "Boss Event" : "معركة الزعيم")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(BossStyle.textPrimary)
            }

            Spacer()

            switch boss.state {
            case .live:
                BossLivePill()
            case .ended:
                Text(isEnglish ? "ENDED" : "انتهت")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(BossStyle.textDim)
            default:
                if let starts = boss.startsAtDate {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 9))
                        BossCountdownText(deadline: starts)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(BossStyle.ember)
                }
            }
        }
    }

    private var subtitle: String {
        switch boss.state {
        case .live:
            let count = boss.attacker_count ?? 0
            return "⚔️ \(count.formatted()) \(isEnglish ? "attacking" : "يهاجمون")"

        case .ended:
            let result: String
            switch boss.outcome {
            case .victory:   result = isEnglish ? "Boss defeated" : "هُزم الزعيم"
            case .defeat:    result = isEnglish ? "Boss survived" : "نجا الزعيم"
            case .cancelled: result = isEnglish ? "Event cancelled" : "أُلغيت المعركة"
            default:         result = isEnglish ? "Event over" : "انتهت المعركة"
            }
            guard let rank = boss.user_rank else { return result }
            return "\(result) · \(isEnglish ? "your rank #\(rank)" : "ترتيبك #\(rank)")"

        default:
            var parts: [String] = []
            if let interested = boss.interested_count {
                parts.append("\(interested.formatted()) \(isEnglish ? "interested" : "مهتم")")
            }
            if let hp = boss.hp_total {
                parts.append("HP \(hp.formatted())")
            }
            return parts.joined(separator: " · ")
        }
    }

    private var ctaTitle: String {
        switch boss.state {
        case .live:
            return isEnglish ? "⚔️ Join the battle" : "⚔️ انضم للمعركة"
        case .ended:
            return isEnglish ? "🎁 View your rewards" : "🎁 اعرض مكافآتك"
        default:
            return boss.user_on_waitlist == true
                ? (isEnglish ? "✓ Reminder set" : "✓ تم ضبط التذكير")
                : (isEnglish ? "🔔 Remind me" : "🔔 ذكّرني")
        }
    }

    private var ctaBackground: Color {
        switch boss.state {
        case .live:  return BossStyle.gold
        case .ended: return BossStyle.gold.opacity(0.9)
        default:     return boss.user_on_waitlist == true
            ? Color.white.opacity(0.10)
            : BossStyle.gold
        }
    }

    private var ctaForeground: Color {
        if boss.state == .scheduled && boss.user_on_waitlist == true {
            return BossStyle.textPrimary
        }
        return Color(hex: "#1A1206")
    }
}
