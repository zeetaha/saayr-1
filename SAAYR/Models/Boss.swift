//
//  Boss.swift
//  SAAYR
//
//  The boss event: a community raid that everyone in the city fights at once.
//  Players don't attack it directly — checking in, walking and redeeming
//  vouchers is what deals damage, and the server credits it. Everything here
//  is read-only reporting plus one write (the waitlist toggle).
//
//  Decoding is deliberately forgiving. The backend is still moving, and a
//  strict model that throws on an unrecognised string would blank the whole
//  feature rather than one field.
//

import Foundation

// MARK: - Enumerations

/// Where a boss is in its lifecycle. Unrecognised values decode to `.unknown`
/// so a new server-side state hides the boss instead of failing the response.
enum BossState: String, Decodable, Sendable {
    case scheduled
    /// Named `idle` rather than `none`: a case literally called `none` on a
    /// type that is frequently optional reads as `Optional.none` at a glance
    /// and invites the wrong comparison.
    case idle = "none"
    case live
    case ended
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BossState(rawValue: raw.lowercased()) ?? .unknown
    }
}

/// `on_site` bosses can only be fought from inside the zone; `remote` ones
/// can be fought from anywhere.
enum BossType: String, Decodable, Sendable {
    case onSite = "on_site"
    case remote
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BossType(rawValue: raw.lowercased()) ?? .unknown
    }
}

/// How it finished. `cancelled` is an admin action, not a player outcome.
enum BossOutcome: String, Decodable, Sendable {
    case victory
    case defeat
    case cancelled
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BossOutcome(rawValue: raw.lowercased()) ?? .unknown
    }
}

// MARK: - Timestamps

/// Boss timestamps are **not** UTC, despite what they say.
///
/// The backend serializes Riyadh wall-clock time with a `Z` suffix, so a boss
/// an admin scheduled for 1:16 AM Riyadh arrives as
/// `"2026-08-23T01:16:00Z"` — which honestly read is 4:16 AM Riyadh, three
/// hours late. Every countdown in the boss feature is off by exactly Riyadh's
/// offset until that's corrected.
///
/// This subtracts the offset back off so the parsed value is the instant the
/// event actually happens, which is what the countdowns and the "FRI 8:00 PM"
/// slot need in order to be right in whatever timezone the player is in.
///
/// **Delete this the day the backend sends true UTC.** It is a compensation
/// for wrong data, not a conversion, and once the serializer is fixed it will
/// be three hours wrong in the other direction — with nothing on screen to
/// say so.
enum BossTime {

    /// Saudi Arabia has no DST, so this is a fixed +03:00 and doesn't need to
    /// be resolved per-date.
    private static let riyadhOffset: TimeInterval =
        TimeInterval(TimeZone(identifier: "Asia/Riyadh")?.secondsFromGMT() ?? 3 * 3600)

    /// Parses a boss timestamp into the instant it really refers to.
    ///
    /// Wraps the shared parser rather than replacing it, so the tolerant
    /// format chain — fractional seconds, and offset-less strings that are
    /// already pinned to UTC — keeps working, and both shapes land on the
    /// same corrected instant.
    static func parse(_ string: String?) -> Date? {
        UserManager.parseISODate(string).map { $0.addingTimeInterval(-riyadhOffset) }
    }
}

// MARK: - Home banner

/// Drives the poster above the pet on the home screen.
struct BossHomeBanner: Decodable, Sendable {
    let state: BossState
    let boss_id: Int?
    let boss_name: String?
    let image_url: String?
    /// Scheduled only.
    let starts_at: String?
    /// Live only.
    let ends_at: String?
    /// Live only — how many people are fighting right now.
    let attacker_count: Int?
    /// True while a boss is live *or* starts within the hour. PvP is off
    /// during that window, so its banner is greyed out.
    let pvp_blocked: Bool
    /// A global admin switch, **not** a per-user subscription: it says whether
    /// this boss sends notifications at all. Per-user opt-in doesn't exist
    /// server-side yet, so the bell is shown on this flag alone.
    let notifications_enabled: Bool

    var startsAtDate: Date? { BossTime.parse(starts_at) }
    var endsAtDate: Date? { BossTime.parse(ends_at) }

    /// Nothing to show — no boss scheduled, or one the client can't interpret.
    var isEmpty: Bool { state == .idle || state == .unknown || boss_id == nil }

    private enum CodingKeys: String, CodingKey {
        case state, boss_id, boss_name, image_url
        case starts_at, ends_at, attacker_count
        case pvp_blocked, notifications_enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = (try? c.decode(BossState.self, forKey: .state)) ?? .unknown
        boss_id = try? c.decodeIfPresent(Int.self, forKey: .boss_id)
        boss_name = try? c.decodeIfPresent(String.self, forKey: .boss_name)
        image_url = try? c.decodeIfPresent(String.self, forKey: .image_url)
        starts_at = try? c.decodeIfPresent(String.self, forKey: .starts_at)
        ends_at = try? c.decodeIfPresent(String.self, forKey: .ends_at)
        attacker_count = try? c.decodeIfPresent(Int.self, forKey: .attacker_count)
        pvp_blocked = (try? c.decodeIfPresent(Bool.self, forKey: .pvp_blocked)) ?? false
        notifications_enabled =
            (try? c.decodeIfPresent(Bool.self, forKey: .notifications_enabled)) ?? false
    }
}

// MARK: - Zones

/// One area the boss is fought in, drawn in red over the map for as long as
/// the home banner is showing a boss.
///
/// Deliberately not the fog-of-war `Zone`: that one carries unlock state and
/// drives the blackout, while this is a plain overlay. Everything but the
/// boundary is optional — a zone the client can't label is still a zone it
/// can draw.
struct BossZone: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String?
    let name_ar: String?
    let boundary_polygon: [ZoneCoordinate]

    private enum CodingKeys: String, CodingKey {
        case id, name, name_ar, boundary_polygon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        name_ar = try? c.decodeIfPresent(String.self, forKey: .name_ar)
        boundary_polygon =
            (try? c.decodeIfPresent([ZoneCoordinate].self, forKey: .boundary_polygon)) ?? []
    }
}

// MARK: - Challenges card

/// The `boss` field the challenges endpoint now carries. One object covers all
/// three states, with only the relevant fields populated for each.
struct BossChallengeSummary: Decodable, Sendable {
    let state: BossState
    let boss_id: Int
    let boss_name: String
    let boss_type: BossType?
    let image_url: String?

    // Scheduled
    let starts_at: String?
    let interested_count: Int?
    let user_on_waitlist: Bool?
    let hp_total: Int?

    // Live
    let ends_at: String?
    let attacker_count: Int?

    // Ended
    let outcome: BossOutcome?
    let user_rank: Int?
    let rewards_available: Bool?

    var startsAtDate: Date? { BossTime.parse(starts_at) }
    var endsAtDate: Date? { BossTime.parse(ends_at) }
}

// MARK: - Battle state

struct BossBattleState: Decodable, Sendable {
    let boss_id: Int
    let boss_name: String
    let boss_type: BossType
    let image_url: String?
    let state: BossState?

    let hp_percent: Int
    let max_hp: Int
    let current_hp: Int
    let attacker_count: Int

    let ends_at: String?
    let time_remaining_seconds: Int
    /// True for an on-site boss: the player has to be in the zone to fight.
    let zone_required: Bool

    let user_stats: UserBattleStats
    let weapons: BossWeapons

    /// The countdown target. Derived from `time_remaining_seconds` rather than
    /// `ends_at` so it stays correct even if the device clock is skewed —
    /// anchor it once, when the response lands.
    func deadline(from now: Date = Date()) -> Date {
        now.addingTimeInterval(TimeInterval(time_remaining_seconds))
    }
}

struct UserBattleStats: Decodable, Sendable {
    let damage_dealt: Int
    let contribution_percent: Double
    let rank: Int
    /// False until the player lands their first hit.
    let is_participant: Bool

    private enum CodingKeys: String, CodingKey {
        case damage_dealt, contribution_percent, rank, is_participant
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        damage_dealt = (try? c.decodeIfPresent(Int.self, forKey: .damage_dealt)) ?? 0
        contribution_percent =
            (try? c.decodeIfPresent(Double.self, forKey: .contribution_percent)) ?? 0
        rank = (try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? 0
        is_participant = (try? c.decodeIfPresent(Bool.self, forKey: .is_participant)) ?? false
    }

    static let empty = UserBattleStats(damage_dealt: 0, contribution_percent: 0, rank: 0, is_participant: false)

    private init(damage_dealt: Int, contribution_percent: Double, rank: Int, is_participant: Bool) {
        self.damage_dealt = damage_dealt
        self.contribution_percent = contribution_percent
        self.rank = rank
        self.is_participant = is_participant
    }
}

/// The three ways to damage a boss. None of them is a button that hits the
/// boss directly — each is an ordinary app action the server scores.
struct BossWeapons: Decodable, Sendable {
    let checkin: WeaponCheckin
    /// The server sends partner check-in as its own weapon, with its own
    /// damage, used count and nearest location — not as a field on `checkin`.
    /// Optional because a boss can be configured without one.
    let partner_checkin: WeaponCheckin?
    let steps: WeaponSteps
    let voucher: WeaponVoucher
}

struct WeaponCheckin: Decodable, Sendable {
    let damage: Int?
    /// Checking in at a partner location hits harder.
    let partner_damage: Int?
    let used_count: Int
    /// Only populated when `lat`/`lng` were passed to battle-state.
    let nearest_location_name: String?
    let nearest_location_distance_m: Double?

    private enum CodingKeys: String, CodingKey {
        case damage, partner_damage, used_count
        case nearest_location_name, nearest_location_distance_m
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        damage = try? c.decodeIfPresent(Int.self, forKey: .damage)
        partner_damage = try? c.decodeIfPresent(Int.self, forKey: .partner_damage)
        used_count = (try? c.decodeIfPresent(Int.self, forKey: .used_count)) ?? 0
        nearest_location_name = try? c.decodeIfPresent(String.self, forKey: .nearest_location_name)
        nearest_location_distance_m = try? c.decodeIfPresent(Double.self, forKey: .nearest_location_distance_m)
    }
}

struct WeaponSteps: Decodable, Sendable {
    let damage_per_250: Int?
    /// Cap on how much walking can contribute for this boss.
    let max_damage: Int?
    let damage_dealt: Int
    let steps_counted: Int

    private enum CodingKeys: String, CodingKey {
        case damage_per_250, max_damage, damage_dealt, steps_counted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        damage_per_250 = try? c.decodeIfPresent(Int.self, forKey: .damage_per_250)
        max_damage = try? c.decodeIfPresent(Int.self, forKey: .max_damage)
        damage_dealt = (try? c.decodeIfPresent(Int.self, forKey: .damage_dealt)) ?? 0
        steps_counted = (try? c.decodeIfPresent(Int.self, forKey: .steps_counted)) ?? 0
    }

    /// Fill for the steps progress bar, 0…1. Nil when the boss has no cap
    /// configured, in which case there's no bar to draw.
    var progress: Double? {
        guard let max_damage, max_damage > 0 else { return nil }
        return min(1, Double(damage_dealt) / Double(max_damage))
    }
}

struct WeaponVoucher: Decodable, Sendable {
    /// Nil when the admin hasn't configured voucher damage for this boss —
    /// the weapon is then hidden rather than shown as worth zero.
    let damage: Int?
    /// How many vouchers the player has already redeemed against this boss.
    let used_count: Int

    private enum CodingKeys: String, CodingKey {
        case damage, used_count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        damage = try? c.decodeIfPresent(Int.self, forKey: .damage)
        used_count = (try? c.decodeIfPresent(Int.self, forKey: .used_count)) ?? 0
    }
}

// MARK: - Waitlist

struct WaitlistMember: Decodable, Sendable, Identifiable, Hashable {
    /// First letter, for the avatar.
    let initial: String
    /// First name only — the backend deliberately sends no further PII.
    let display_name: String
    let level: Int
    let joined_seconds_ago: Int
    let is_you: Bool

    /// No server-side id is sent, and names repeat, so identity is the name
    /// plus how long ago they joined — stable enough for a list that only ever
    /// gains and loses whole rows.
    var id: String { "\(display_name)|\(level)|\(joined_seconds_ago)" }
}

struct WaitlistToggleResponse: Decodable, Sendable {
    let boss_id: Int
    let joined: Bool
    let interested_count: Int
}

struct WaitlistListResponse: Decodable, Sendable {
    let boss_id: Int?
    let total: Int
    let page: Int?
    let page_size: Int?
    let members: [WaitlistMember]
}

// MARK: - Rewards

struct BossRewards: Decodable, Sendable {
    let boss_id: Int
    let boss_name: String
    let boss_type: BossType?
    let outcome: BossOutcome
    /// False when the player never landed a hit; `user_stats` and `rewards`
    /// are then both null.
    let participated: Bool
    let user_stats: BossRewardUserStats?
    let rewards: BossRewardDetail?
}

struct BossRewardUserStats: Decodable, Sendable {
    let damage_dealt: Int
    let contribution_percent: Double
    let rank: Int
    let total_participants: Int
}

struct BossRewardDetail: Decodable, Sendable {
    let xp_earned: Int
    /// Placeholders on the backend today — always false / null. The XP is
    /// granted regardless; these exist for a claim flow that isn't built yet.
    let claimed: Bool?
    let claimed_at: String?
}

// MARK: - Stream events

/// Pushed once when the waitlist stream connects, so the screen never needs
/// the REST endpoint to draw its first frame.
struct WaitlistSnapshotEvent: Decodable, Sendable {
    let total: Int
    let members: [WaitlistMember]
}

struct WaitlistJoinedEvent: Decodable, Sendable {
    let initial: String
    let display_name: String
    let level: Int
    let joined_seconds_ago: Int
    let is_you: Bool
    let total: Int

    var member: WaitlistMember {
        WaitlistMember(
            initial: initial,
            display_name: display_name,
            level: level,
            joined_seconds_ago: joined_seconds_ago,
            is_you: is_you
        )
    }
}

struct WaitlistLeftEvent: Decodable, Sendable {
    let display_name: String
    let total: Int
}

/// Closes the waitlist stream. `reason == "live"` means the fight has started
/// and the player should be moved to the battle screen.
struct WaitlistEndedEvent: Decodable, Sendable {
    let reason: String?

    var didGoLive: Bool { reason?.lowercased() == "live" }
}

/// The ~3s tick on the battle stream.
struct BattleStateEvent: Decodable, Sendable {
    let hp_percent: Int?
    let current_hp: Int?
    let attacker_count: Int?
    let time_remaining_seconds: Int?
}

/// One line in the live feed. Only sent when someone actually did damage.
struct BattleFeedEvent: Decodable, Sendable, Identifiable {
    let actor: String?
    let action: String?
    let damage: Int?
    let ts: String?

    /// The feed carries no id; the timestamp plus actor is unique enough for
    /// a list that only ever has rows prepended.
    var id: String { "\(ts ?? UUID().uuidString)|\(actor ?? "")|\(damage ?? 0)" }

    /// Server sends a machine value; this is what the player reads.
    /// The action values the reference documents are
    /// `checkin_partner | real_world | tap_energy | voucher_redemption`, but
    /// the server also sends plain `checkin`, so matching is by substring
    /// rather than exact equality. An unrecognised action still reads as a
    /// sentence — "attacked" — instead of leaking a raw enum at the player.
    func summary(isEnglish: Bool) -> String {
        let who = actor ?? (isEnglish ? "Someone" : "أحدهم")
        return "\(who) \(verb(isEnglish: isEnglish))"
    }

    private func verb(isEnglish: Bool) -> String {
        guard let action = action?.lowercased(), !action.isEmpty else {
            return isEnglish ? "attacked" : "هاجم"
        }

        // Partner is checked first: "checkin_partner" contains "checkin", so
        // the more specific match has to win.
        if action.contains("partner") {
            return isEnglish ? "checked in at a partner" : "سجّل حضوره لدى شريك"
        }
        if action.contains("checkin") || action.contains("check_in") || action == "real_world" {
            return isEnglish ? "checked in" : "سجّل حضوره"
        }
        if action.contains("voucher") {
            return isEnglish ? "redeemed a voucher" : "استبدل قسيمة"
        }
        if action.contains("tap") || action.contains("energy") {
            return isEnglish ? "spent energy" : "استخدم طاقته"
        }
        if action.contains("step") || action.contains("walk") {
            return isEnglish ? "walked" : "مشى"
        }
        return isEnglish ? "attacked" : "هاجم"
    }

    /// Icon for the row, so the feed scans without reading every line.
    var symbol: String {
        guard let action = action?.lowercased() else { return "⚔️" }
        if action.contains("voucher") { return "🎟️" }
        if action.contains("step") || action.contains("walk") { return "👟" }
        if action.contains("tap") || action.contains("energy") { return "⚡️" }
        if action.contains("checkin") || action.contains("check_in") || action == "real_world" {
            return "📍"
        }
        return "⚔️"
    }

    var timestamp: Date? { UserManager.parseISODate(ts) }

    /// Wall-clock time of the hit, in the player's timezone. The feed only
    /// covers the length of one fight, so the hour and minute is enough.
    func timeText(isEnglish: Bool) -> String? {
        guard let timestamp else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en" : "ar")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

struct BattleLeaderboardEntry: Decodable, Sendable, Identifiable {
    let rank: Int
    let name: String
    let damage: Int

    var id: Int { rank }
}

/// Closes the battle stream; the player is moved to the rewards screen.
struct BattleEndedEvent: Decodable, Sendable {
    let outcome: BossOutcome?
    let final_hp: Int?
}
