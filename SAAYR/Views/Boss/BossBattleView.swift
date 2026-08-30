//
//  BossBattleView.swift
//  SAAYR
//
//  The fight itself. One REST call hydrates the screen, then a single stream
//  keeps HP, the attacker count, the feed and the leaderboard current.
//
//  There is no "attack" button and no attack endpoint: damage is a side effect
//  of things the player already does — checking in, walking, redeeming a
//  voucher. The weapons list below is a set of shortcuts into those flows.
//

import SwiftUI
import Combine
import CoreLocation

// MARK: - Model

@MainActor
final class BossBattleModel: ObservableObject {

    @Published private(set) var battle: BossBattleState?
    @Published private(set) var isLoading = true

    // Live values. Seeded from battle-state, then replaced by each stream tick.
    @Published var hpPercent: Int = 100
    @Published var currentHP: Int = 0
    @Published var attackerCount: Int = 0
    @Published var deadline: Date = Date()

    /// The player's own damage/contribution/rank. Seeded from battle-state,
    /// then replaced by each `you` frame — the server recomputes contribution
    /// as other people land hits, so it moves even when the player is idle.
    @Published var userStats: UserBattleStats = .empty

    @Published var feed: [BattleFeedEvent] = []
    @Published var leaderboard: [BattleLeaderboardEntry] = []

    @Published var isConnected = false
    @Published var endedOutcome: BossOutcome?

    /// The feed is a ticker, not a log — old lines have no value and an
    /// unbounded array on a long fight is just memory.
    private let feedLimit = 30

    private let bossID: Int
    private var stream: EventSource?
    /// Whether the loaded battle-state was computed with the player's
    /// coordinates. False means the weapons card has no nearest location in it.
    private var hasLocatedState = false

    init(bossID: Int) {
        self.bossID = bossID
    }

    // MARK: Load

    func load(coordinate: CLLocationCoordinate2D?) {
        BossAPI.shared.fetchBattleState(bossID: bossID, coordinate: coordinate) { [weak self] state in
            guard let self else { return }
            self.isLoading = false
            guard let state else { return }

            self.apply(state)
            if coordinate != nil { self.hasLocatedState = true }
            self.startStream()
        }
    }

    /// Re-reads battle-state now that a fix exists, but only if the first read
    /// went out without one. The stream owns everything after that.
    func hydrateLocationIfNeeded(coordinate: CLLocationCoordinate2D) {
        guard !hasLocatedState, !isLoading else { return }
        hasLocatedState = true

        BossAPI.shared.fetchBattleState(bossID: bossID, coordinate: coordinate) { [weak self] state in
            guard let self, let state else { return }
            self.apply(state)
        }
    }

    private func apply(_ state: BossBattleState) {
        battle = state
        hpPercent = state.hp_percent
        currentHP = state.current_hp
        attackerCount = state.attacker_count
        userStats = state.user_stats
        // Anchored from the server's remaining-seconds rather than its absolute
        // end time, so a skewed device clock can't shift it.
        deadline = state.deadline()
    }

    private func startStream() {
        guard stream == nil, let source = BossAPI.shared.liveFeedStream(bossID: bossID) else { return }

        source.onOpen = { [weak self] in self?.isConnected = true }
        source.onMessage = { [weak self] message in self?.handle(message) }
        source.onError = { [weak self] _, _ in self?.isConnected = false }

        stream = source
        source.connect()
    }

    func stop() {
        #if DEBUG
        // TEMPORARY: the debug switch holds the feed open across screens, so
        // leaving the battle screen mustn't tear it down. Remove with
        // BossLiveFeedDebug.
        if BossLiveFeedDebug.isEnabled {
            print("🧪 DEBUG: leaving battle screen with the live-feed still open")
            return
        }
        #endif

        stream?.close()
        stream = nil
        isConnected = false
    }

    private func handle(_ message: SSEMessage) {
        switch message.event {
        case "state":
            guard let event = message.decode(BattleStateEvent.self) else { return }
            if let hp = event.hp_percent { hpPercent = hp }
            if let current = event.current_hp { currentHP = current }
            if let attackers = event.attacker_count { attackerCount = attackers }
            // Re-anchored each tick: the server is the clock, and this keeps a
            // long session from drifting away from it.
            if let remaining = event.time_remaining_seconds {
                deadline = Date().addingTimeInterval(TimeInterval(remaining))
            }

        case "feed":
            guard let event = message.decode(BattleFeedEvent.self) else { return }
            feed.insert(event, at: 0)
            if feed.count > feedLimit { feed.removeLast(feed.count - feedLimit) }

        // The player's own row. Sent on its own event rather than inside
        // `state`, because contribution shifts whenever anyone lands a hit.
        case "you":
            guard let stats = message.decode(UserBattleStats.self) else { return }
            userStats = stats

        case "leaderboard":
            guard let entries = message.decode([BattleLeaderboardEntry].self) else { return }
            leaderboard = entries

        case "ended":
            let event = message.decode(BattleEndedEvent.self)
            if let hp = event?.final_hp { currentHP = hp }
            stop()
            endedOutcome = event?.outcome ?? .unknown

        // Transport-level keep-alives. Named so they can never fall through to
        // the unhandled branch and be mistaken for something the player
        // should see.
        case "ping", "heartbeat", "keepalive":
            break

        default:
            // Every frame is already printed by SSELogger; this says which
            // ones the screen has no handler for, so a new server event shows
            // up as a named gap rather than silence.
            #if DEBUG
            print("🧪 live-feed: unhandled event '\(message.event)' — \(message.data)")
            #endif
            // Release compiles the block above away, and an empty `default:`
            // isn't legal Swift.
            break
        }
    }

}

/// One line of the damage breakdown: a weapon, and what it has contributed so
/// far. Built in the view rather than decoded — the server sends per-hit
/// damage and a use count, not a per-weapon total.
private struct DamageSource: Identifiable {
    let id: String
    let icon: String
    let label: String
    let damage: Int
}

// MARK: - Screen

struct BossBattleView: View {

    let bossID: Int
    let isEnglish: Bool
    let onClose: () -> Void
    /// Fires when the stream reports the fight is over, so the host can show
    /// the rewards screen.
    let onEnded: (BossOutcome) -> Void

    @StateObject private var model: BossBattleModel
    @StateObject private var locationManager = FilteredLocationManager()

    init(
        bossID: Int,
        isEnglish: Bool,
        onClose: @escaping () -> Void,
        onEnded: @escaping (BossOutcome) -> Void
    ) {
        self.bossID = bossID
        self.isEnglish = isEnglish
        self.onClose = onClose
        self.onEnded = onEnded
        _model = StateObject(wrappedValue: BossBattleModel(bossID: bossID))
    }

    private var coordinate: CLLocationCoordinate2D? {
        locationManager.currentLocation?.coordinate
    }

    var body: some View {
        ZStack {
            Color(hex: "#0B0E14").ignoresSafeArea()

            if model.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: BossStyle.ember))
                    .scaleEffect(1.4)
            } else if let battle = model.battle {
                content(battle)
            } else {
                unavailable
            }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startUpdating()
            model.load(coordinate: coordinate)
        }
        // A first fix takes a few seconds, so the screen almost always loads
        // without one — and battle-state computed without lat/lng comes back
        // with no nearest location, which is what the check-in weapon is built
        // around. Re-hydrate once, when the fix finally lands. This is a
        // one-shot on acquisition, not the polling the contract rules out.
        .onReceive(locationManager.$currentLocation.compactMap { $0 }) { location in
            model.hydrateLocationIfNeeded(coordinate: location.coordinate)
        }
        .onDisappear {
            locationManager.stopUpdating()
            model.stop()
        }
        .onChange(of: model.endedOutcome) { outcome in
            if let outcome { onEnded(outcome) }
        }
    }

    // MARK: Content

    private func content(_ battle: BossBattleState) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                header(battle)

                if battle.zone_required {
                    zoneBadge
                }

                bossCard(battle)
                statTiles(model.userStats)
                damageBreakdown(model.userStats, weapons: battle.weapons)

                // Leaderboard above the feed: standings are what the player
                // is here to move, and burying them under a scrolling feed
                // makes the fight feel like it has no scoreboard. Both are
                // always shown, with a waiting state — a section that appears
                // out of nowhere on the first hit is easy to miss.
                leaderboardSection

                feedSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private func header(_ battle: BossBattleState) -> some View {
        HStack(spacing: 8) {
            BossLivePill()

            Text(battle.boss_name)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(BossStyle.textPrimary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                BossCountdownText(deadline: model.deadline, isEnglish: isEnglish)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(BossStyle.textDim)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(BossStyle.textDim)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .accessibilityLabel(isEnglish ? "Close" : "إغلاق")
        }
        .padding(.top, 12)
    }

    /// On-site bosses can only be fought from inside the zone. The client
    /// can't verify that itself — the server decides when it scores the
    /// check-in — so this states the requirement rather than claiming the
    /// player currently meets it.
    private var zoneBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 11))
            Text(isEnglish
                 ? "Fight from inside the zone"
                 : "قاتل من داخل المنطقة")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(Color(hex: "#34D399"))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#34D399").opacity(0.12)))
    }

    private func bossCard(_ battle: BossBattleState) -> some View {
        HStack(spacing: 12) {
            BossAvatar(imageURL: battle.image_url, size: 52)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(isEnglish ? "Boss HP" : "صحة الزعيم")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BossStyle.textDim)
                    Spacer()
                    // The percent alone hides how much of the bar a hit is
                    // worth; the raw numbers are what make ~50 damage read as
                    // meaningful against a 272 HP boss.
                    Text("\(model.currentHP.formatted()) / \(battle.max_hp.formatted())")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(BossStyle.textDim)
                    Text("\(model.hpPercent)%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(BossStyle.textPrimary)
                }

                BossHPBar(percent: model.hpPercent)

                HStack(spacing: 4) {
                    Text("⚔️")
                    Text("\(model.attackerCount.formatted()) \(isEnglish ? "fighting" : "يقاتلون")")
                    if !model.isConnected {
                        Text("·").foregroundColor(BossStyle.textDim)
                        Text(isEnglish ? "reconnecting…" : "…جارٍ إعادة الاتصال")
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(BossStyle.textDim)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(BossStyle.surface))
    }

    private func statTiles(_ stats: UserBattleStats) -> some View {
        HStack(spacing: 10) {
            BossStatTile(
                value: stats.damage_dealt.formatted(),
                label: isEnglish ? "Your damage" : "ضررك"
            )
            BossStatTile(
                value: String(format: "%.1f%%", stats.contribution_percent),
                label: isEnglish ? "Contribution" : "مساهمتك"
            )
            BossStatTile(
                value: stats.rank > 0 ? "#\(stats.rank)" : "—",
                label: isEnglish ? "Rank" : "ترتيبك",
                highlighted: stats.rank > 0
            )
        }
    }

    // MARK: Damage breakdown

    /// Splits the "Your damage" tile into where the damage came from, so the
    /// player can see which weapon is actually earning and which one they've
    /// been ignoring.
    ///
    /// Values come from `user_stats.damage_breakdown`, which the server scores
    /// the same way it scores the total — so when it's present the rows sum to
    /// the tile above, caps and bonuses included. It rides the `you` event, so
    /// they tick up mid-fight along with the tile. Without it the rows fall
    /// back to an estimate; see `breakdownRows`.
    private func damageBreakdown(_ stats: UserBattleStats, weapons: BossWeapons) -> some View {
        let rows = breakdownRows(stats, weapons: weapons)
        let total = rows.reduce(0) { $0 + $1.damage }

        return VStack(alignment: .leading, spacing: 8) {
            Text(isEnglish ? "WEAPONS & DAMAGES" : "الأسلحة والأضرار")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundColor(BossStyle.textDim)

            // One block with dividers rather than separate cards: these are
            // parts of a single number, and spacing them apart would read as
            // four unrelated stats.
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    breakdownRow(row, total: total)
                    if row.id != rows.last?.id {
                        Divider().overlay(BossStyle.surfaceEdge)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(BossStyle.surface))
        }
    }

    private func breakdownRow(_ row: DamageSource, total: Int) -> some View {
        HStack(spacing: 10) {
            Text(row.icon).font(.system(size: 15))

            Text(row.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BossStyle.textPrimary)

            Spacer(minLength: 8)

            // The share reads faster than the raw number when comparing two
            // weapons, but only means something once there's damage to split.
            if total > 0 {
                Text("\(Int((Double(row.damage) / Double(total) * 100).rounded()))%")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(BossStyle.textDim)
            }

            Text(row.damage.formatted())
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundColor(row.damage > 0 ? BossStyle.ember : BossStyle.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    /// One row per weapon the boss actually has. A weapon the player hasn't
    /// used yet still gets a row at zero — the gap is the point.
    ///
    /// `weapons` decides which rows exist, matching the cards below; the
    /// breakdown decides what they're worth. Falls back to `per-hit × uses`
    /// only when the server hasn't sent a breakdown at all, so the section
    /// still says something against an older backend.
    private func breakdownRows(_ stats: UserBattleStats, weapons: BossWeapons) -> [DamageSource] {
        let split = stats.damage_breakdown

        var rows: [DamageSource] = [
            DamageSource(
                id: "checkin",
                icon: "📍",
                label: isEnglish ? "Check-ins" : "تسجيلات الحضور",
                damage: split?.checkin
                    ?? (weapons.checkin.damage ?? 0) * weapons.checkin.used_count
            )
        ]

        let partnerDamage = split?.partner_checkin
            ?? (weapons.partner_checkin?.damage ?? 0) * (weapons.partner_checkin?.used_count ?? 0)
        // Same escape hatch as the voucher row below: damage the player has
        // already scored has to appear, or it drops out of the rows and
        // silently inflates every other row's share.
        if weapons.partner_checkin != nil || partnerDamage > 0 {
            rows.append(DamageSource(
                id: "partner",
                icon: "🤝",
                label: isEnglish ? "Partner check-ins" : "تسجيلات لدى الشركاء",
                damage: partnerDamage
            ))
        }

        rows.append(DamageSource(
            id: "steps",
            icon: "👟",
            label: isEnglish ? "Steps" : "الخطوات",
            damage: split?.steps ?? weapons.steps.damage_dealt
        ))

        // Same rule as the weapon card: a boss with no voucher damage
        // configured doesn't have the weapon at all, so it gets no row —
        // unless the player has already scored with one, which means the
        // weapon is live whatever the card config says.
        let voucherDamage = split?.voucher ?? (weapons.voucher.damage ?? 0) * weapons.voucher.used_count
        if weapons.voucher.damage != nil || voucherDamage > 0 {
            rows.append(DamageSource(
                id: "voucher",
                icon: "🎟️",
                label: isEnglish ? "Redemptions" : "الاستبدالات",
                damage: voucherDamage
            ))
        }

        return rows
    }

    // MARK: Leaderboard & feed

    /// Every fighter the stream sends, not a top-N slice — seeing the whole
    /// field is what makes a mid-table rank feel worth climbing. Lazy because
    /// a busy boss can carry hundreds of rows.
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // No count in the header: the row total would only be the number
            // of entries the stream chose to send, which reads as the size of
            // the field even when it's a slice of it.
            HStack(spacing: 6) {
                Text(isEnglish ? "LEADERBOARD" : "قائمة المتصدرين")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                Spacer()
            }
            .foregroundColor(BossStyle.textDim)

            if model.leaderboard.isEmpty {
                Text(isEnglish
                     ? "Standings appear with the first hit…"
                     : "…تظهر الترتيبات مع أول ضربة")
                    .font(.system(size: 12))
                    .foregroundColor(BossStyle.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(model.leaderboard) { entry in
                        leaderboardRow(entry)
                    }
                }
            }
        }
    }

    private func leaderboardRow(_ entry: BattleLeaderboardEntry) -> some View {
        // The podium is the carrot: three rows carry gold rather than one, so
        // second and third read as places worth defending, not as also-rans.
        let isPodium = entry.rank <= 3

        return HStack(spacing: 10) {
            Text(podiumSymbol(entry.rank) ?? "#\(entry.rank)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundColor(isPodium ? BossStyle.gold : BossStyle.textDim)
                .frame(width: 28, alignment: .leading)

            Text(entry.name)
                .font(.system(size: 13, weight: isPodium ? .bold : .semibold))
                .foregroundColor(BossStyle.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(entry.damage.formatted())
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundColor(BossStyle.ember)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isPodium ? BossStyle.gold.opacity(0.08) : BossStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPodium ? BossStyle.gold.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    /// Medals for the podium, plain rank for everyone else.
    private func podiumSymbol(_ rank: Int) -> String? {
        switch rank {
        case 1:  return "🥇"
        case 2:  return "🥈"
        case 3:  return "🥉"
        default: return nil
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(isEnglish ? "LIVE FEED" : "البث المباشر")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                // A quiet feed and a dead connection look identical otherwise,
                // so the dot says which one it is.
                Circle()
                    .fill(model.isConnected ? BossStyle.live : BossStyle.textDim)
                    .frame(width: 6, height: 6)
                    .opacity(model.isConnected ? 1 : 0.4)
                Spacer()
            }
            .foregroundColor(BossStyle.textDim)

            VStack(spacing: 5) {
                if model.feed.isEmpty {
                    Text(isEnglish
                         ? "Waiting for the first hit…"
                         : "…في انتظار أول ضربة")
                        .font(.system(size: 12))
                        .foregroundColor(BossStyle.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                } else {
                    ForEach(model.feed) { entry in
                        feedRow(entry)
                            // Each new hit slides in from the top, which is
                            // what makes it read as a feed rather than a table.
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.easeOut(duration: 0.25), value: model.feed.map(\.id))
        }
    }

    private func feedRow(_ entry: BattleFeedEvent) -> some View {
        HStack(spacing: 8) {
            Text(entry.symbol)
                .font(.system(size: 13))

            Text(entry.summary(isEnglish: isEnglish))
                .font(.system(size: 12))
                .foregroundColor(BossStyle.textPrimary.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 4)

            if let time = entry.timeText(isEnglish: isEnglish) {
                Text(time)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(BossStyle.textDim)
            }

            if let damage = entry.damage {
                Text("-\(damage)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(BossStyle.ember)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Text("👹").font(.system(size: 42))
            Text(isEnglish ? "This battle isn't available" : "هذه المعركة غير متاحة")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BossStyle.textPrimary)
            Button(action: onClose) {
                Text(isEnglish ? "Close" : "إغلاق")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1206"))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(BossStyle.gold))
            }
            .buttonStyle(.plain)
        }
    }

}
