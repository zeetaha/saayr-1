//
//  GroupsModel.swift
//  SAAYR
//
//  What the Groups screens read from, and the one object that talks to
//  `GroupsAPI` on their behalf.
//
//  The API splits a group across several endpoints — detail, members,
//  requests, feed, leaderboard — so the store keeps a cache per group keyed
//  by its id, and each screen asks for the slice it shows. The `live` stream
//  never carries state into these caches; it only says which slice is stale,
//  which keeps the client honest about a payload shape the contract doesn't
//  pin down.
//

import Combine
import SwiftUI

// MARK: - Vocabularies
//
// Each of these is an open string on the wire. They are parsed leniently on
// purpose: a cover the app has never heard of should draw *something*, not
// drop the group out of the list.

/// The four woven covers. `sadu_a`…`sadu_d` on the wire.
enum GroupCover: String, CaseIterable, Identifiable {
    case palm   = "sadu_a"
    case falcon = "sadu_b"
    case earth  = "sadu_c"
    case sky    = "sadu_d"

    var id: String { rawValue }

    init(key: String?) {
        self = GroupCover(rawValue: key?.lowercased() ?? "") ?? .palm
    }

    var stripes: (Color, Color) {
        switch self {
        case .palm:   return (GroupStyle.palm, GroupStyle.palmDeep)
        case .falcon: return (GroupStyle.falcon, Color(hex: "#D08D2B"))
        case .earth:  return (Color(hex: "#7A5C3E"), Color(hex: "#5E4630"))
        case .sky:    return (Color(hex: "#3E6E8C"), Color(hex: "#2F5670"))
        }
    }

    /// The falcon and sky weaves run the other way, which is what keeps four
    /// covers from reading as one pattern in four colours.
    var leansRight: Bool {
        switch self {
        case .palm, .earth:  return false
        case .falcon, .sky:  return true
        }
    }
}

/// Where the player stands with a group. Drives every screen: what the card
/// shows, whether the feed opens, whether the gear appears.
enum GroupRole {
    case admin
    case member
    case pending
    case none

    /// The server says `owner` for the one who made the group; the app has no
    /// second tier of admin, so both read as admin here.
    init(_ raw: String?) {
        switch raw?.lowercased() {
        case "owner", "admin":       self = .admin
        case "member":               self = .member
        case "pending", "requested": self = .pending
        default:                     self = .none
        }
    }
}

enum GroupVisibility: String {
    case isPublic  = "public"
    case isPrivate = "private"
}

enum GroupReaction: String, CaseIterable, Identifiable {
    case up, fire, clap

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .up:   return "👍"
        case .fire: return "🔥"
        case .clap: return "👏"
        }
    }
}

/// The reasons the report sheet offers. Slugs, so the backend gets something
/// stable to group on rather than display text that changes with the locale.
enum GroupReportReason: String, CaseIterable, Identifiable {
    case inappropriateName  = "inappropriate_name"
    case inappropriatePhoto = "inappropriate_photo"
    case other

    var id: String { rawValue }
}

// MARK: - Screen model

/// One group as the screens want it: the summary and the detail endpoints
/// answer overlapping shapes, and this is what both collapse to.
struct SaayrGroup: Identifiable, Equatable {
    let id: Int
    var name: String
    var detail: String
    var cover: GroupCover
    var isPublic: Bool
    var memberCount: Int
    var role: GroupRole
    /// Rank inside the group's own weekly board. Only the list endpoint
    /// carries it, so a group opened straight from Discover has none.
    var weeklyRank: Int?
    var lastActiveAt: Date?
    var joinedAt: Date?
    var ownerName: String?

    var isAdmin: Bool { role == .admin }
    var isJoined: Bool { role == .admin || role == .member }

    init(_ dto: GroupSummaryDTO) {
        id = dto.id
        name = dto.name
        detail = dto.description ?? ""
        cover = GroupCover(key: dto.coverKey)
        isPublic = dto.visibility.lowercased() != GroupVisibility.isPrivate.rawValue
        memberCount = dto.memberCount
        role = GroupRole(dto.myRole)
        weeklyRank = dto.myRankThisWeek
        lastActiveAt = dto.lastActiveAt
    }

    init(_ dto: GroupDetailDTO, weeklyRank: Int? = nil, lastActiveAt: Date? = nil) {
        id = dto.id
        name = dto.name
        detail = dto.description ?? ""
        cover = GroupCover(key: dto.coverKey)
        isPublic = dto.visibility.lowercased() != GroupVisibility.isPrivate.rawValue
        memberCount = dto.memberCount
        // `my_role` is the authority, but a group the player is in that comes
        // back with no role still has to open its feed.
        let parsed = GroupRole(dto.myRole)
        role = (parsed == .none && dto.isMember) ? .member : parsed
        self.weeklyRank = weeklyRank
        self.lastActiveAt = lastActiveAt
        joinedAt = dto.joinedAt
        ownerName = dto.ownerName
    }
}

// MARK: - Equatable helpers

extension GroupRole: Equatable {}

// MARK: - Store

/// Everything Groups knows, and the only thing that calls `GroupsAPI`.
///
/// One instance lives for as long as the Groups flow is on screen, so a
/// change made in the admin screen is already true when the back gesture
/// lands on the card that opened it.
final class GroupsStore: ObservableObject {

    // Lists
    @Published var mine: [SaayrGroup] = []
    @Published var discover: [SaayrGroup] = []
    @Published var isLoadingMine = false
    @Published var isLoadingDiscover = false
    @Published var hasLoadedMine = false
    @Published var hasLoadedDiscover = false

    // Per group, keyed by id
    @Published var details: [Int: SaayrGroup] = [:]
    @Published var feeds: [Int: [FeedEventDTO]] = [:]
    @Published var boards: [Int: GroupLeaderboardDTO] = [:]
    @Published var members: [Int: [GroupMemberDTO]] = [:]
    @Published var requests: [Int: [JoinRequestDTO]] = [:]
    @Published var inviteLinks: [Int: InviteLinkDTO] = [:]
    @Published var inviteResults: [InviteSearchResultDTO] = []
    @Published var isSearchingInvites = false

    /// Set when a write fails and the player needs the server's words for it.
    @Published var errorMessage: String?

    /// The next page of the feed, per group. Nil once the end is reached.
    private var feedCursors: [Int: Int] = [:]
    private var isLoadingFeed: Set<Int> = []

    // MARK: Lists

    func loadMine(force: Bool = false) {
        guard force || (!hasLoadedMine && !isLoadingMine) else { return }
        isLoadingMine = true
        GroupsAPI.shared.fetchMyGroups { [weak self] groups in
            guard let self else { return }
            isLoadingMine = false
            hasLoadedMine = true
            guard let groups else { return }
            mine = groups.map(SaayrGroup.init)
            // The list endpoint is the only one carrying the weekly rank, so
            // anything already open keeps its own copy fresh from here.
            for group in mine { details[group.id] = merge(group, into: details[group.id]) }
        }
    }

    func loadDiscover(search: String? = nil, force: Bool = false) {
        guard force || (!hasLoadedDiscover && !isLoadingDiscover) else { return }
        isLoadingDiscover = true
        GroupsAPI.shared.discover(search: search) { [weak self] response in
            guard let self else { return }
            isLoadingDiscover = false
            hasLoadedDiscover = true
            guard let response else { return }
            discover = response.groups.map(SaayrGroup.init)
        }
    }

    func group(_ id: Int) -> SaayrGroup? {
        details[id] ?? mine.first { $0.id == id } ?? discover.first { $0.id == id }
    }

    // MARK: One group

    func loadDetail(_ id: Int) {
        GroupsAPI.shared.fetchDetail(id) { [weak self] dto in
            guard let self, let dto else { return }
            let known = group(id)
            var fresh = SaayrGroup(dto, weeklyRank: known?.weeklyRank, lastActiveAt: known?.lastActiveAt)
            // A request already on file has to survive this. The contract
            // doesn't say whether `my_role` comes back as "pending" for
            // someone waiting, and if it doesn't, the join button would flip
            // back to "Request to join" a moment after being tapped. This
            // can't strand anyone: an approval arrives as `member`, and a
            // decline leaves the group joinable again on the next open.
            if fresh.role == .none, known?.role == .pending, !dto.isMember {
                fresh.role = .pending
            }
            details[id] = fresh
            replaceInLists(fresh)
        }
    }

    func loadFeed(_ id: Int, reset: Bool = true) {
        guard !isLoadingFeed.contains(id) else { return }
        let cursor = reset ? nil : feedCursors[id]
        if !reset && cursor == nil { return }   // the end of the feed
        isLoadingFeed.insert(id)

        GroupsAPI.shared.fetchFeed(id, cursor: cursor) { [weak self] response in
            guard let self else { return }
            isLoadingFeed.remove(id)
            guard let response else { return }
            if reset {
                feeds[id] = response.events
            } else {
                let known = Set((feeds[id] ?? []).map(\.id))
                feeds[id, default: []] += response.events.filter { !known.contains($0.id) }
            }
            feedCursors[id] = response.nextCursor.flatMap(Int.init)
        }
    }

    func loadMoreFeed(_ id: Int) {
        guard feedCursors[id] != nil else { return }
        loadFeed(id, reset: false)
    }

    func loadLeaderboard(_ id: Int) {
        GroupsAPI.shared.fetchLeaderboard(id) { [weak self] board in
            guard let self, let board else { return }
            boards[id] = board
        }
    }

    func loadMembers(_ id: Int) {
        GroupsAPI.shared.fetchMembers(id) { [weak self] list in
            guard let self, let list else { return }
            members[id] = list
        }
    }

    func loadRequests(_ id: Int) {
        GroupsAPI.shared.fetchRequests(id) { [weak self] list in
            guard let self, let list else { return }
            requests[id] = list
        }
    }

    func loadInviteLink(_ id: Int) {
        GroupsAPI.shared.currentInviteLink(id) { [weak self] link in
            guard let self else { return }
            // A group that has never issued one answers 404. That's "none
            // yet", so the sheet offers to generate rather than showing an
            // error.
            if let link { inviteLinks[id] = link }
        }
    }

    // MARK: Writes

    func create(
        name: String,
        detail: String,
        cover: GroupCover,
        isPublic: Bool,
        isEnglish: Bool,
        completion: @escaping (SaayrGroup?) -> Void
    ) {
        GroupsAPI.shared.create(
            name: name,
            description: detail,
            coverKey: cover.rawValue,
            visibility: (isPublic ? GroupVisibility.isPublic : .isPrivate).rawValue
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let dto):
                let group = SaayrGroup(dto)
                details[group.id] = group
                mine.insert(group, at: 0)
                completion(group)
            case .failure(let error):
                errorMessage = error.displayMessage(isEnglish: isEnglish)
                completion(nil)
            }
        }
    }

    func update(
        _ id: Int,
        name: String,
        detail: String,
        cover: GroupCover,
        isPublic: Bool,
        isEnglish: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        GroupsAPI.shared.update(
            id,
            name: name,
            description: detail,
            coverKey: cover.rawValue,
            visibility: (isPublic ? GroupVisibility.isPublic : .isPrivate).rawValue
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let dto):
                let known = group(id)
                let updated = SaayrGroup(dto, weeklyRank: known?.weeklyRank, lastActiveAt: known?.lastActiveAt)
                details[id] = updated
                replaceInLists(updated)
                completion(true)
            case .failure(let error):
                errorMessage = error.displayMessage(isEnglish: isEnglish)
                completion(false)
            }
        }
    }

    func requestJoin(_ id: Int, isEnglish: Bool, completion: @escaping (Bool) -> Void) {
        GroupsAPI.shared.requestJoin(id) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                // The button has to change now. The server's own answer is
                // read on the next open of the screen rather than immediately
                // — see `loadDetail`, which is careful not to undo this.
                if var group = self.group(id) {
                    group.role = .pending
                    details[id] = group
                    replaceInLists(group)
                }
                completion(true)
            case .failure(let error):
                errorMessage = error.displayMessage(isEnglish: isEnglish)
                completion(false)
            }
        }
    }

    func react(_ reaction: GroupReaction, on eventID: Int, in groupID: Int) {
        guard let index = feeds[groupID]?.firstIndex(where: { $0.id == eventID }) else { return }
        let current = feeds[groupID]?[index].reactions.mine
        let next: GroupReaction? = current == reaction ? nil : reaction

        // Move the vote locally so the tap lands immediately, then take the
        // server's totals as final — which also makes a racing
        // `reaction_update` harmless.
        apply(counts: optimistic(from: feeds[groupID]?[index].reactions, moving: next),
              to: eventID, in: groupID)

        GroupsAPI.shared.react(groupID, eventID: eventID, reaction: next) { [weak self] counts in
            guard let self, let counts else { return }
            apply(counts: counts, to: eventID, in: groupID)
        }
    }

    func approve(_ request: JoinRequestDTO, in groupID: Int) {
        requests[groupID]?.removeAll { $0.id == request.id }
        GroupsAPI.shared.approve(groupID, requestID: request.id) { [weak self] ok in
            guard let self else { return }
            guard ok else { loadRequests(groupID); return }
            loadMembers(groupID)
            loadDetail(groupID)
        }
    }

    func decline(_ request: JoinRequestDTO, in groupID: Int) {
        requests[groupID]?.removeAll { $0.id == request.id }
        GroupsAPI.shared.decline(groupID, requestID: request.id) { [weak self] ok in
            guard let self, !ok else { return }
            loadRequests(groupID)
        }
    }

    func remove(_ member: GroupMemberDTO, from groupID: Int) {
        members[groupID]?.removeAll { $0.userId == member.userId }
        GroupsAPI.shared.removeMember(groupID, userID: member.userId) { [weak self] ok in
            guard let self else { return }
            guard ok else { loadMembers(groupID); return }
            loadDetail(groupID)
        }
    }

    func disband(_ id: Int, completion: @escaping (Bool) -> Void) {
        GroupsAPI.shared.disband(id) { [weak self] ok in
            guard let self else { return }
            if ok { forget(id) }
            completion(ok)
        }
    }

    func leave(_ id: Int, completion: @escaping (Bool) -> Void) {
        GroupsAPI.shared.leave(id) { [weak self] ok in
            guard let self else { return }
            if ok {
                forget(id)
                // A public group the player just left is still discoverable,
                // so the next Discover load should see it fresh.
                hasLoadedDiscover = false
            }
            completion(ok)
        }
    }

    func regenerateInvite(_ id: Int) {
        GroupsAPI.shared.rotateInviteLink(id) { [weak self] link in
            guard let self, let link else { return }
            inviteLinks[id] = link
        }
    }

    func searchInvites(_ id: Int, query: String) {
        guard !query.isEmpty else {
            inviteResults = []
            return
        }
        isSearchingInvites = true
        GroupsAPI.shared.inviteSearch(id, query: query) { [weak self] results in
            guard let self else { return }
            isSearchingInvites = false
            inviteResults = results ?? []
        }
    }

    func invite(_ person: InviteSearchResultDTO, in groupID: Int) {
        // The row says "Sent" straight away; the search is re-read afterwards
        // so `already_invited` from the server is what survives.
        markInvited(person.userId)
        GroupsAPI.shared.inviteUser(groupID, userID: person.userId) { [weak self] ok in
            guard let self, !ok else { return }
            markInvited(person.userId, invited: false)
        }
    }

    func report(_ id: Int, reason: GroupReportReason, completion: @escaping (Bool) -> Void) {
        GroupsAPI.shared.report(id, reason: reason.rawValue, note: nil, completion: completion)
    }

    // MARK: - Live

    private var live: EventSource?
    private var liveGroupID: Int?

    /// Holds `/live` open for one group. The stream is treated as a set of
    /// invalidation signals rather than a source of state: the contract names
    /// the events but not their payloads, so each one re-reads the slice it
    /// concerns. That costs one small request per real change, which is what
    /// "scales with activity, not with viewers" already assumes.
    func openLive(_ id: Int) {
        guard liveGroupID != id else { return }
        closeLive()

        guard let stream = GroupsAPI.shared.liveStream(id) else { return }
        liveGroupID = id
        live = stream

        stream.onMessage = { [weak self] message in
            guard let self, liveGroupID == id else { return }
            switch message.event {
            case "feed_event", "reaction_update":
                loadFeed(id)
            case "leaderboard_update":
                loadLeaderboard(id)
            case "member_update":
                loadMembers(id)
                loadDetail(id)
            case "request_update":
                loadRequests(id)
            case "group_updated":
                loadDetail(id)
            default:
                break
            }
        }
        stream.connect()
    }

    func closeLive() {
        live?.close()
        live = nil
        liveGroupID = nil
    }

    deinit {
        live?.close()
    }

    // MARK: - Helpers

    private func optimistic(
        from counts: FeedReactionCountsDTO?,
        moving next: GroupReaction?
    ) -> FeedReactionCountsDTO {
        var up = counts?.up ?? 0
        var fire = counts?.fire ?? 0
        var clap = counts?.clap ?? 0

        func adjust(_ reaction: GroupReaction, by delta: Int) {
            switch reaction {
            case .up:   up = max(0, up + delta)
            case .fire: fire = max(0, fire + delta)
            case .clap: clap = max(0, clap + delta)
            }
        }

        if let previous = counts?.mine { adjust(previous, by: -1) }
        if let next { adjust(next, by: 1) }

        return FeedReactionCountsDTO(up: up, fire: fire, clap: clap, myReaction: next?.rawValue)
    }

    private func apply(counts: FeedReactionCountsDTO, to eventID: Int, in groupID: Int) {
        guard let index = feeds[groupID]?.firstIndex(where: { $0.id == eventID }) else { return }
        feeds[groupID]?[index].reactions = counts
    }

    private func markInvited(_ userID: Int, invited: Bool = true) {
        guard let index = inviteResults.firstIndex(where: { $0.userId == userID }) else { return }
        inviteResults[index].alreadyInvited = invited
    }

    /// Keeps the rank and activity the list endpoint knows about when a
    /// fresher copy of the same group arrives from elsewhere.
    private func merge(_ incoming: SaayrGroup, into existing: SaayrGroup?) -> SaayrGroup {
        var merged = incoming
        merged.joinedAt = incoming.joinedAt ?? existing?.joinedAt
        merged.ownerName = incoming.ownerName ?? existing?.ownerName
        return merged
    }

    private func replaceInLists(_ group: SaayrGroup?) {
        guard let group else { return }
        if let index = mine.firstIndex(where: { $0.id == group.id }) { mine[index] = group }
        if let index = discover.firstIndex(where: { $0.id == group.id }) { discover[index] = group }
    }

    /// Drops every trace of a group the player is no longer in.
    private func forget(_ id: Int) {
        mine.removeAll { $0.id == id }
        details[id] = nil
        feeds[id] = nil
        boards[id] = nil
        members[id] = nil
        requests[id] = nil
        inviteLinks[id] = nil
        feedCursors[id] = nil
        if liveGroupID == id { closeLive() }
    }
}

// MARK: - Formatting

/// Dates arrive as instants; the screens want the phrases the design asked
/// for. Relative times come from Foundation, so Arabic gets Arabic even
/// though the feed text itself is composed in English by the server.
enum GroupsFormat {

    static func relative(_ date: Date?, isEnglish: Bool) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en" : "ar")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func day(_ date: Date?, isEnglish: Bool) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en" : "ar")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    /// "6 days left" for the leaderboard reset strip.
    static func daysLeft(until date: Date) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0)
    }
}
