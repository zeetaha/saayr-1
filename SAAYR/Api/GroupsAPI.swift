//
//  GroupsAPI.swift
//  SAAYR
//
//  Every network call the Groups feature makes, and the shapes the server
//  answers with. The REST calls hydrate a screen once; `liveStream` says when
//  to re-read one. Nothing here polls.
//
//  The contract is `/api/v1/groups` on the Saayr API. Where a vocabulary is
//  an open string on the wire (role, visibility, cover, reaction), it is
//  parsed leniently — an unknown value degrades to the safe reading rather
//  than failing the whole decode.
//

import Alamofire
import Foundation

// MARK: - Wire types

/// A group as it appears in a list — My Groups and Discover both answer this.
struct GroupSummaryDTO: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String?
    let coverKey: String
    let visibility: String
    let memberCount: Int
    /// The city the group belongs to. Not shown anywhere yet.
    let city: String?
    let myRole: String?
    let myRankThisWeek: Int?
    let lastActiveAt: Date?
}

/// One group in full. `myRole` and `isMember` are what decide whether the
/// screen shows a feed or a locked preview.
struct GroupDetailDTO: Decodable, Equatable {
    let id: Int
    let name: String
    let description: String?
    let coverKey: String
    let visibility: String
    let memberCount: Int
    let city: String?
    let ownerId: Int
    let ownerName: String?
    let isMember: Bool
    let myRole: String?
    let joinedAt: Date?
    let createdAt: Date
}

struct DiscoverResponseDTO: Decodable {
    let groups: [GroupSummaryDTO]
    let nextCursor: String?
}

struct GroupMemberDTO: Decodable, Identifiable, Equatable {
    var id: Int { userId }
    let userId: Int
    let name: String
    let avatar: String?
    let role: String
    let joinedAt: Date
    let isActiveToday: Bool?
}

struct GroupMemberListDTO: Decodable {
    let members: [GroupMemberDTO]
    let total: Int
}

struct JoinRequestDTO: Decodable, Identifiable, Equatable {
    let id: Int
    let userId: Int
    let name: String
    let avatar: String?
    let level: Int
    let requestedAt: Date
}

struct JoinRequestListDTO: Decodable {
    let requests: [JoinRequestDTO]
    let total: Int
}

struct InviteLinkDTO: Decodable, Equatable {
    let code: String
    let url: String
    let expiresAt: Date
}

struct InviteSearchResultDTO: Decodable, Identifiable, Equatable {
    var id: Int { userId }
    let userId: Int
    let name: String
    let username: String?
    let level: Int
    /// Flipped locally the moment an invite is sent, then confirmed by the
    /// next search.
    var alreadyInvited: Bool?
}

/// The three counts plus which one is mine. The server has no list of who
/// reacted, only the totals.
struct FeedReactionCountsDTO: Decodable, Equatable {
    let up: Int?
    let fire: Int?
    let clap: Int?
    let myReaction: String?

    func count(_ reaction: GroupReaction) -> Int {
        switch reaction {
        case .up:   return up ?? 0
        case .fire: return fire ?? 0
        case .clap: return clap ?? 0
        }
    }

    var mine: GroupReaction? { GroupReaction(rawValue: myReaction ?? "") }
}

/// One line of the group feed. `text` is composed by the server in English;
/// the client shows it as it arrives and localises only the timestamp.
struct FeedEventDTO: Decodable, Identifiable, Equatable {
    let id: Int
    let eventType: String
    let actorUserId: Int?
    let actorName: String?
    let icon: String
    let text: String
    let createdAt: Date
    /// Replaced wholesale when the server answers a reaction — the totals
    /// it returns are authoritative.
    var reactions: FeedReactionCountsDTO
}

struct FeedResponseDTO: Decodable {
    let events: [FeedEventDTO]
    let nextCursor: String?
}

struct LeaderboardRowDTO: Decodable, Identifiable, Equatable {
    var id: Int { userId }
    let rank: Int
    let userId: Int
    let name: String
    let avatar: String?
    let level: Int
    let points: Int
    let isMe: Bool?
}

struct GroupLeaderboardDTO: Decodable {
    let rows: [LeaderboardRowDTO]
    let me: LeaderboardRowDTO?
    let resetsAt: Date
}

// MARK: - Errors

/// A failed groups request, carrying whatever the server said about it. Same
/// shape as `BossAPIError` — the API answers `{"detail": "..."}` throughout,
/// and the server's own wording ("You can't create more groups") beats
/// anything written here.
struct GroupsAPIError: Error {
    let body: Data?
    let status: Int?
    let underlying: Error?

    /// Nothing there yet rather than something broken — a group with no
    /// invite link issued, most often.
    var isNotFound: Bool { status == 404 }

    var serverMessage: String? {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        if let detail = json["detail"] as? String, !detail.isEmpty { return detail }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        if let error = json["error"] as? String, !error.isEmpty { return error }
        return nil
    }

    func displayMessage(isEnglish: Bool) -> String {
        if let serverMessage { return serverMessage }
        if let status {
            return isEnglish
                ? "Something went wrong — server returned \(status)."
                : "حدث خطأ ما — استجابة الخادم \(status)."
        }
        return isEnglish
            ? "Something went wrong. Check your connection and try again."
            : "حدث خطأ ما. تحقّق من اتصالك وحاول مرة أخرى."
    }
}

// MARK: - API

final class GroupsAPI {

    static let shared = GroupsAPI()
    private init() {}

    /// Snake case on the wire, ISO-8601 timestamps — with and without
    /// fractional seconds, because the API sends both.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = GroupsAPI.isoWithFraction.date(from: text) { return date }
            if let date = GroupsAPI.iso.date(from: text) { return date }
            // A timestamp with no zone at all. FastAPI writes these for a
            // naive datetime, and ISO8601DateFormatter rejects every one of
            // them — reading it as UTC is right for a server that stores UTC,
            // and is the only reading available from the string itself.
            if let date = GroupsAPI.zoneless.date(from: text) { return date }
            if let date = GroupsAPI.zonelessWhole.date(from: text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date: \(text)")
            )
        }
        return decoder
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let zoneless = GroupsAPI.utcFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSS")
    private static let zonelessWhole = GroupsAPI.utcFormatter("yyyy-MM-dd'T'HH:mm:ss")

    private static func utcFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    // MARK: Lists

    func fetchMyGroups(completion: @escaping ([GroupSummaryDTO]?) -> Void) {
        get([GroupSummaryDTO].self, WebService.groups, label: "my-groups", completion: completion)
    }

    /// Discover, filtered by name. The server sorts by recent activity when
    /// there is no search term.
    func discover(search: String?, limit: Int = 20, completion: @escaping (DiscoverResponseDTO?) -> Void) {
        var parameters: [String: Any] = ["limit": limit]
        if let search, !search.isEmpty { parameters["search"] = search }
        get(DiscoverResponseDTO.self, WebService.groupsDiscover,
            parameters: parameters, label: "discover", completion: completion)
    }

    func fetchDetail(_ id: Int, completion: @escaping (GroupDetailDTO?) -> Void) {
        get(GroupDetailDTO.self, WebService.group(id), label: "detail", completion: completion)
    }

    // MARK: Writes on the group itself

    func create(
        name: String,
        description: String?,
        coverKey: String,
        visibility: String,
        completion: @escaping (Result<GroupDetailDTO, GroupsAPIError>) -> Void
    ) {
        var parameters: [String: Any] = [
            "name": name,
            "cover_key": coverKey,
            "visibility": visibility
        ]
        if let description, !description.isEmpty { parameters["description"] = description }
        post(GroupDetailDTO.self, WebService.groups, parameters: parameters,
             label: "create", completion: completion)
    }

    /// Only the fields that changed need to be sent — every one is optional
    /// on the server.
    func update(
        _ id: Int,
        name: String?,
        description: String?,
        coverKey: String?,
        visibility: String?,
        completion: @escaping (Result<GroupDetailDTO, GroupsAPIError>) -> Void
    ) {
        var parameters: [String: Any] = [:]
        if let name { parameters["name"] = name }
        // An empty description is a real value here: it clears the line.
        if let description { parameters["description"] = description }
        if let coverKey { parameters["cover_key"] = coverKey }
        if let visibility { parameters["visibility"] = visibility }

        ServiceModel.shared.putRequest(endpoint: WebService.group(id), parameters: parameters) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let value = try? self.decoder.decode(GroupDetailDTO.self, from: data) {
                        completion(.success(value))
                    } else {
                        completion(.failure(GroupsAPIError(body: data, status: nil, underlying: nil)))
                    }
                case .failure(let error):
                    completion(.failure(GroupsAPIError(body: nil, status: error.responseCode, underlying: error)))
                }
            }
        }
    }

    func disband(_ id: Int, completion: @escaping (Bool) -> Void) {
        delete(WebService.group(id), label: "disband", completion: completion)
    }

    func leave(_ id: Int, completion: @escaping (Bool) -> Void) {
        postIgnoringBody(WebService.groupLeave(id), label: "leave", completion: completion)
    }

    func report(_ id: Int, reason: String, note: String?, completion: @escaping (Bool) -> Void) {
        var parameters: [String: Any] = ["reason": reason]
        if let note, !note.isEmpty { parameters["note"] = note }
        postIgnoringBody(WebService.groupReport(id), parameters: parameters,
                         label: "report", completion: completion)
    }

    // MARK: Members and requests

    func fetchMembers(_ id: Int, completion: @escaping ([GroupMemberDTO]?) -> Void) {
        get(GroupMemberListDTO.self, WebService.groupMembers(id), label: "members") { response in
            completion(response?.members)
        }
    }

    func removeMember(_ id: Int, userID: Int, completion: @escaping (Bool) -> Void) {
        delete(WebService.groupMember(id, userID: userID), label: "remove-member", completion: completion)
    }

    func fetchRequests(_ id: Int, completion: @escaping ([JoinRequestDTO]?) -> Void) {
        get(JoinRequestListDTO.self, WebService.groupRequests(id), label: "requests") { response in
            completion(response?.requests)
        }
    }

    /// Asks to join. The answer carries no body worth reading — the group's
    /// own detail is re-read afterwards to learn the new role.
    func requestJoin(_ id: Int, completion: @escaping (Result<Void, GroupsAPIError>) -> Void) {
        ServiceModel.shared.postRequestReportingBody(endpoint: WebService.groupRequests(id)) { result, body, status in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(GroupsAPIError(body: body, status: status, underlying: error)))
                }
            }
        }
    }

    func approve(_ id: Int, requestID: Int, completion: @escaping (Bool) -> Void) {
        postIgnoringBody(WebService.groupRequestApprove(id, requestID: requestID),
                         label: "approve", completion: completion)
    }

    func decline(_ id: Int, requestID: Int, completion: @escaping (Bool) -> Void) {
        postIgnoringBody(WebService.groupRequestDecline(id, requestID: requestID),
                         label: "decline", completion: completion)
    }

    // MARK: Invites

    /// The link that is live right now. A group that has never issued one
    /// answers 404, which is "none yet", not a failure — the caller offers to
    /// generate one instead.
    func currentInviteLink(_ id: Int, completion: @escaping (InviteLinkDTO?) -> Void) {
        get(InviteLinkDTO.self, WebService.groupInviteLinkCurrent(id),
            label: "invite-link", completion: completion)
    }

    func rotateInviteLink(_ id: Int, completion: @escaping (InviteLinkDTO?) -> Void) {
        post(InviteLinkDTO.self, WebService.groupInviteLinks(id), label: "rotate-invite") { result in
            completion(try? result.get())
        }
    }

    func inviteSearch(_ id: Int, query: String, completion: @escaping ([InviteSearchResultDTO]?) -> Void) {
        get([InviteSearchResultDTO].self, WebService.groupInviteSearch(id),
            parameters: ["q": query], label: "invite-search", completion: completion)
    }

    /// Invites one player, and answers with the single-use link that was
    /// minted for them.
    func inviteUser(_ id: Int, userID: Int, completion: @escaping (Bool) -> Void) {
        post(InviteLinkDTO.self, WebService.groupInviteUsers(id),
             parameters: ["user_id": userID], label: "invite-user") { result in
            completion((try? result.get()) != nil)
        }
    }

    /// Joining from a shared link. Nothing routes here yet — a universal-link
    /// handler would.
    func redeemInvite(code: String, completion: @escaping (Result<GroupDetailDTO, GroupsAPIError>) -> Void) {
        post(GroupDetailDTO.self, WebService.groupInviteRedeem(code), label: "redeem", completion: completion)
    }

    // MARK: Feed and board

    func fetchFeed(
        _ id: Int,
        cursor: Int? = nil,
        limit: Int = 20,
        completion: @escaping (FeedResponseDTO?) -> Void
    ) {
        var parameters: [String: Any] = ["limit": limit]
        if let cursor { parameters["cursor"] = cursor }
        get(FeedResponseDTO.self, WebService.groupFeed(id),
            parameters: parameters, label: "feed", completion: completion)
    }

    /// Sets or clears this player's reaction. The answer is the new totals —
    /// authoritative, so the row takes them rather than counting locally.
    func react(
        _ id: Int,
        eventID: Int,
        reaction: GroupReaction?,
        completion: @escaping (FeedReactionCountsDTO?) -> Void
    ) {
        // `nil` is meaningful: it removes the reaction. Alamofire drops nil
        // values from a dictionary, so NSNull carries it through.
        let parameters: [String: Any] = ["reaction": reaction?.rawValue ?? NSNull()]
        post(FeedReactionCountsDTO.self, WebService.groupFeedReact(id, eventID: eventID),
             parameters: parameters, label: "react") { result in
            completion(try? result.get())
        }
    }

    func fetchLeaderboard(_ id: Int, completion: @escaping (GroupLeaderboardDTO?) -> Void) {
        get(GroupLeaderboardDTO.self, WebService.groupLeaderboard(id),
            label: "leaderboard", completion: completion)
    }

    // MARK: Live

    /// Everything happening in one group: `feed_event`, `reaction_update`,
    /// `leaderboard_update`, `member_update`, `request_update`,
    /// `group_updated`. Open on entering the group screen, close on leaving.
    func liveStream(_ id: Int) -> EventSource? {
        guard let url = URL(string: WebService.groupLive(id)) else { return nil }
        return EventSource(url: url)
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(
        _ type: T.Type,
        _ endpoint: String,
        parameters: [String: Any]? = nil,
        label: String,
        completion: @escaping (T?) -> Void
    ) {
        ServiceModel.shared.getRequest(endpoint: endpoint, parameters: parameters) { [weak self] result in
            guard let self else { return }
            let value = self.decode(type, from: result, label: label)
            DispatchQueue.main.async { completion(value) }
        }
    }

    private func post<T: Decodable>(
        _ type: T.Type,
        _ endpoint: String,
        parameters: [String: Any]? = nil,
        label: String,
        completion: @escaping (Result<T, GroupsAPIError>) -> Void
    ) {
        ServiceModel.shared.postRequestReportingBody(endpoint: endpoint, parameters: parameters) { [weak self] result, body, status in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let value = try? self.decoder.decode(type, from: data) {
                        completion(.success(value))
                    } else {
                        print("⚠️ Groups \(label): decode failed")
                        completion(.failure(GroupsAPIError(body: body, status: status, underlying: nil)))
                    }
                case .failure(let error):
                    completion(.failure(GroupsAPIError(body: body, status: status, underlying: error)))
                }
            }
        }
    }

    /// For the endpoints that answer nothing worth reading — approve, leave,
    /// report. Success is the status code.
    private func postIgnoringBody(
        _ endpoint: String,
        parameters: [String: Any]? = nil,
        label: String,
        completion: @escaping (Bool) -> Void
    ) {
        ServiceModel.shared.postRequest(endpoint: endpoint, parameters: parameters) { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    print("⚠️ Groups \(label): request failed —", error.localizedDescription)
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }
    }

    private func delete(_ endpoint: String, label: String, completion: @escaping (Bool) -> Void) {
        ServiceModel.shared.deleteRequest(endpoint: endpoint) { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    print("⚠️ Groups \(label): request failed —", error.localizedDescription)
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from result: Result<Data, some Error>,
        label: String
    ) -> T? {
        switch result {
        case .success(let data):
            do {
                return try decoder.decode(type, from: data)
            } catch {
                print("⚠️ Groups \(label): decode failed —", error)
                return nil
            }
        case .failure(let error):
            print("⚠️ Groups \(label): request failed —", error.localizedDescription)
            return nil
        }
    }
}
