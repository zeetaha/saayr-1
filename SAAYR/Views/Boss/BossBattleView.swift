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

// MARK: - Screen

struct BossBattleView: View {

    let bossID: Int
    let isEnglish: Bool
    let onClose: () -> Void
    /// Fires when the stream reports the fight is over, so the host can show
    /// the rewards screen.
    let onEnded: (BossOutcome) -> Void
    /// Checking in doesn't happen here. The map owns that flow — dwell
    /// verification, the dry run, the fraud evidence — and a second path to
    /// the endpoint would be a way around all of it. This hands the player
    /// over instead.
    let onCheckInRequested: () -> Void

    @StateObject private var model: BossBattleModel
    @StateObject private var locationManager = FilteredLocationManager()
    @State private var showRewardsSheet = false

    init(
        bossID: Int,
        isEnglish: Bool,
        onClose: @escaping () -> Void,
        onEnded: @escaping (BossOutcome) -> Void,
        onCheckInRequested: @escaping () -> Void
    ) {
        self.bossID = bossID
        self.isEnglish = isEnglish
        self.onClose = onClose
        self.onEnded = onEnded
        self.onCheckInRequested = onCheckInRequested
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
        .sheet(isPresented: $showRewardsSheet) {
            RewardsView()
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
                weapons(battle.weapons)

                // Feed above the leaderboard: it's the part that moves, and
                // the leaderboard only refreshes every ~15s. Always shown,
                // with a waiting state — a section that appears out of nowhere
                // on the first hit is easy to miss.
                feedSection

                if !model.leaderboard.isEmpty {
                    leaderboardSection
                }
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
                BossCountdownText(deadline: model.deadline)
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

    // MARK: Weapons

    private func weapons(_ weapons: BossWeapons) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isEnglish ? "YOUR WEAPONS" : "أسلحتك")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundColor(BossStyle.textDim)

            checkInWeapon(weapons.checkin)

            // Its own row rather than a chip on the check-in row: it carries
            // its own damage, used count and nearest location, none of which
            // fit in another row's subtitle.
            if let partner = weapons.partner_checkin {
                partnerCheckInWeapon(partner)
            }

            stepsWeapon(weapons.steps)

            // Hidden rather than shown as zero when the admin hasn't
            // configured voucher damage for this boss.
            if let damage = weapons.voucher.damage {
                voucherWeapon(weapons.voucher, damage: damage)
            }

        }
    }

    private func checkInWeapon(_ weapon: WeaponCheckin) -> some View {
        weaponRow(
            icon: "📍",
            title: damageTitle(
                base: isEnglish ? "Check in" : "تسجيل حضور",
                damage: weapon.damage,
                // Only a fallback now: when the server sends partner check-in
                // as its own weapon it gets a row of its own instead.
                extra: weapon.partner_damage.map {
                    isEnglish ? "partner ~\($0)" : "شريك ~\($0)"
                }
            ),
            subtitle: weaponSubtitle(nearestText(weapon), usedCount: weapon.used_count),
            // Sends the player to the map rather than checking in here, so the
            // hit goes through the same verification as any other check-in.
            action: onCheckInRequested,
            actionTitle: isEnglish ? "Open map" : "افتح الخريطة",
            isBusy: false
        )
    }

    private func partnerCheckInWeapon(_ weapon: WeaponCheckin) -> some View {
        weaponRow(
            icon: "🤝",
            title: damageTitle(
                base: isEnglish ? "Check in at a partner" : "تسجيل حضور لدى شريك",
                damage: weapon.damage
            ),
            subtitle: weaponSubtitle(nearestText(weapon), usedCount: weapon.used_count),
            action: onCheckInRequested,
            actionTitle: isEnglish ? "Open map" : "افتح الخريطة",
            isBusy: false
        )
    }

    private func stepsWeapon(_ weapon: WeaponSteps) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("👟").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(damageTitle(
                        base: isEnglish ? "Steps" : "خطوات",
                        damage: weapon.damage_per_250
                    ))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BossStyle.textPrimary)

                    Text(stepsSubtitle(weapon))
                        .font(.system(size: 11))
                        .foregroundColor(BossStyle.textDim)
                }
                Spacer(minLength: 0)
            }

            // Walking has no button — it's counted in the background, so the
            // bar is the whole interaction.
            if let progress = weapon.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(BossStyle.gold)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(BossStyle.surface))
    }

    private func voucherWeapon(_ weapon: WeaponVoucher, damage: Int) -> some View {
        weaponRow(
            icon: "🎟️",
            title: isEnglish ? "Redeem voucher ~\(damage)" : "استبدل قسيمة ~\(damage)",
            subtitle: weaponSubtitle(
                isEnglish
                    ? "At any partner inside the zone"
                    : "لدى أي شريك داخل المنطقة",
                usedCount: weapon.used_count
            ),
            action: { showRewardsSheet = true },
            actionTitle: isEnglish ? "Redeem" : "استبدل",
            isBusy: false
        )
    }

    private func weaponRow(
        icon: String,
        title: String,
        subtitle: String?,
        action: @escaping () -> Void,
        actionTitle: String,
        isBusy: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Text(icon).font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BossStyle.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(BossStyle.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 6)

            Button(action: action) {
                Group {
                    if isBusy {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#1A1206")))
                    } else {
                        Text(actionTitle)
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundColor(Color(hex: "#1A1206"))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(BossStyle.gold))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(BossStyle.surface))
    }

    // MARK: Feed & leaderboard

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isEnglish ? "TOP FIGHTERS" : "أفضل المقاتلين")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundColor(BossStyle.textDim)

            VStack(spacing: 6) {
                ForEach(model.leaderboard) { entry in
                    HStack(spacing: 10) {
                        Text("#\(entry.rank)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(entry.rank == 1 ? BossStyle.gold : BossStyle.textDim)
                            .frame(width: 28, alignment: .leading)
                        Text(entry.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BossStyle.textPrimary)
                        Spacer(minLength: 0)
                        Text(entry.damage.formatted())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(BossStyle.ember)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BossStyle.surface))
                }
            }
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

    // MARK: Copy helpers

    /// "Check in ~30 · partner ~50" — the tilde is doing real work: the server
    /// applies level and streak modifiers, so these are indicative, not exact.
    private func damageTitle(base: String, damage: Int?, extra: String? = nil) -> String {
        var text = base
        if let damage { text += " ~\(damage)" }
        if let extra { text += " · \(extra)" }
        return text
    }

    /// Appends "used 1x" to a weapon's subtitle. Silent at zero — a weapon
    /// the player hasn't used yet reads better without a count on it.
    private func weaponSubtitle(_ base: String?, usedCount: Int) -> String? {
        guard usedCount > 0 else { return base }
        let used = isEnglish ? "used \(usedCount)x" : "استُخدم \(usedCount) مرة"
        guard let base else { return used }
        return "\(base) · \(used)"
    }

    /// Walking is passive, so this line has to carry the whole story: how much
    /// it has already contributed and whether it's maxed out for this boss.
    private func stepsSubtitle(_ weapon: WeaponSteps) -> String {
        let steps = "\(weapon.steps_counted.formatted()) \(isEnglish ? "steps" : "خطوة")"

        guard let cap = weapon.max_damage, cap > 0 else {
            guard weapon.damage_dealt > 0 else { return steps }
            return "\(steps) · \(weapon.damage_dealt) \(isEnglish ? "dmg" : "ضرر")"
        }

        if weapon.damage_dealt >= cap {
            return "\(steps) · \(isEnglish ? "max reached" : "بلغت الحد الأقصى")"
        }
        return "\(steps) · \(weapon.damage_dealt)/\(cap) \(isEnglish ? "dmg" : "ضرر")"
    }

    private func nearestText(_ weapon: WeaponCheckin) -> String? {
        guard let name = weapon.nearest_location_name else {
            // Only ever nil when the screen loaded without a location fix.
            return isEnglish ? "Nearest location loading…" : "…جارٍ تحديد أقرب مكان"
        }
        guard let metres = weapon.nearest_location_distance_m else { return name }
        return "\(name) · \(Int(metres.rounded())) m"
    }
}
