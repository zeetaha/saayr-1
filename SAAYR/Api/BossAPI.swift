//
//  BossAPI.swift
//  SAAYR
//
//  Every network call the boss feature makes. The REST calls hydrate a screen
//  once; the two streams keep it current afterwards. Nothing here polls — the
//  contract is explicit that the REST endpoints are for the initial load and
//  the offline fallback only.
//

import Foundation
import CoreLocation

final class BossAPI {

    static let shared = BossAPI()
    private init() {}

    private let decoder = JSONDecoder()

    // MARK: - REST

    /// Poster state for the home screen. Called on home load and refresh.
    func fetchHomeBanner(completion: @escaping (BossHomeBanner?) -> Void) {
        ServiceModel.shared.getRequest(endpoint: WebService.bossHomeBanner) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                completion(self.decode(BossHomeBanner.self, from: result, label: "home-banner"))
            }
        }
    }

    /// The boss's zones, for the map overlay. Called when the home banner
    /// starts showing a boss, not on a timer.
    func fetchZones(completion: @escaping ([BossZone]) -> Void) {
        ServiceModel.shared.getRequest(endpoint: WebService.bossZones) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                completion(self.decode([BossZone].self, from: result, label: "zones") ?? [])
            }
        }
    }

    /// Initial load for the battle screen, called once on entry.
    ///
    /// `coordinate` is what lets the server work out the nearest check-in
    /// location and how far away it is — without it the check-in weapon can
    /// still be used, but the card can't say where to go.
    func fetchBattleState(
        bossID: Int,
        coordinate: CLLocationCoordinate2D?,
        completion: @escaping (BossBattleState?) -> Void
    ) {
        var params: [String: Any] = [:]
        if let coordinate {
            params["lat"] = coordinate.latitude
            params["lng"] = coordinate.longitude
        }

        ServiceModel.shared.getRequest(
            endpoint: WebService.bossBattleState(bossID),
            parameters: params.isEmpty ? nil : params
        ) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                completion(self.decode(BossBattleState.self, from: result, label: "battle-state"))
            }
        }
    }

    /// Joins or leaves the waitlist. Idempotent in both directions.
    ///
    /// The server answers 400 with a reason the player can act on — the boss
    /// isn't scheduled any more, or joining hasn't opened yet — so failures
    /// carry the body through rather than collapsing to nil.
    func toggleWaitlist(
        bossID: Int,
        join: Bool,
        completion: @escaping (Result<WaitlistToggleResponse, BossAPIError>) -> Void
    ) {
        ServiceModel.shared.postRequestReportingBody(
            endpoint: WebService.bossWaitlist(bossID),
            parameters: ["join": join]
        ) { [weak self] result, body, status in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let response = try? self.decoder.decode(WaitlistToggleResponse.self, from: data) {
                        completion(.success(response))
                    } else {
                        completion(.failure(BossAPIError(body: data, status: status, underlying: nil)))
                    }
                case .failure(let error):
                    print("⚠️ Boss waitlist-toggle: \(status.map(String.init) ?? "no status") —",
                          String(data: body ?? Data(), encoding: .utf8) ?? error.localizedDescription)
                    completion(.failure(BossAPIError(body: body, status: status, underlying: error)))
                }
            }
        }
    }

    /// Snapshot of who's waiting.
    ///
    /// Only needed when the stream can't be opened — a successful stream sends
    /// the same snapshot on connect, so calling both duplicates the work.
    func fetchWaitlist(
        bossID: Int,
        page: Int = 1,
        pageSize: Int = 20,
        completion: @escaping (WaitlistListResponse?) -> Void
    ) {
        ServiceModel.shared.getRequest(
            endpoint: WebService.bossWaitlist(bossID),
            parameters: ["page": page, "page_size": pageSize]
        ) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                completion(self.decode(WaitlistListResponse.self, from: result, label: "waitlist"))
            }
        }
    }

    /// Post-event summary. Only valid once the boss has ended.
    func fetchRewards(bossID: Int, completion: @escaping (BossRewards?) -> Void) {
        ServiceModel.shared.getRequest(endpoint: WebService.bossRewards(bossID)) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                completion(self.decode(BossRewards.self, from: result, label: "rewards"))
            }
        }
    }

    // MARK: - Streams

    /// Collects the boss reward. The XP itself is settled server-side; this
    /// marks it acknowledged so the ended card stops coming back in the
    /// challenges payload.
    ///
    /// Idempotent by contract, so a retry after a dropped response is safe.
    /// The reward detail is optional on success: the XP has been credited by
    /// the time a 2xx comes back, so the status is what decides the outcome. A
    /// body that doesn't decode must not be reported as a failure — that would
    /// tell the player it didn't work after it already did.
    func claimRewards(
        bossID: Int,
        completion: @escaping (Result<BossRewardDetail?, BossAPIError>) -> Void
    ) {
        ServiceModel.shared.postRequestReportingBody(
            endpoint: WebService.bossClaimRewards(bossID)
        ) { [weak self] result, body, status in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    completion(.success(try? self.decoder.decode(BossRewardDetail.self, from: data)))
                case .failure(let error):
                    print("⚠️ Boss claim-rewards: \(status.map(String.init) ?? "no status") —",
                          String(data: body ?? Data(), encoding: .utf8) ?? error.localizedDescription)
                    completion(.failure(BossAPIError(body: body, status: status, underlying: error)))
                }
            }
        }
    }

    /// Live membership of the waitlist. Open on entering the waitlist screen,
    /// close on leaving it.
    func waitlistStream(bossID: Int) -> EventSource? {
        guard let url = URL(string: WebService.bossWaitlistStream(bossID)) else { return nil }
        return EventSource(url: url)
    }

    /// HP, attacker count, feed and leaderboard for a live boss. Open after
    /// battle-state has loaded, close on leaving the battle screen.
    func liveFeedStream(bossID: Int) -> EventSource? {
        guard let url = URL(string: WebService.bossLiveFeed(bossID)) else { return nil }
        return EventSource(url: url)
    }

    // MARK: - Helpers

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
                print("⚠️ Boss \(label): decode failed —", error)
                return nil
            }
        case .failure(let error):
            print("⚠️ Boss \(label): request failed —", error.localizedDescription)
            return nil
        }
    }
}

/// A failed boss request, carrying whatever the server said about it.
///
/// The API answers errors as `{"detail": "..."}`, so that's preferred; the
/// status code is the fallback, because "something went wrong" tells the
/// player nothing they can act on.
struct BossAPIError: Error {
    let body: Data?
    let status: Int?
    let underlying: Error?

    /// The reward was already collected. The endpoint is idempotent by
    /// contract and answers 409 on a repeat, which is a success from the
    /// player's side — a retry after a dropped response must not look broken.
    var isAlreadyClaimed: Bool { status == 409 }

    /// The server's own words, when it sent any.
    var serverMessage: String? {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }

        if let detail = json["detail"] as? String, !detail.isEmpty { return detail }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        if let error = json["error"] as? String, !error.isEmpty { return error }
        return nil
    }

    /// What to put in front of the player: the server's message when there is
    /// one, otherwise something that at least names the failure.
    ///
    /// The server's wording is nearly always better than anything written
    /// here — "Joining opens in 2m 17s" tells the player what to do, where a
    /// generic retry line doesn't — so the fallbacks stay deliberately plain
    /// and are only reached when there's no body to quote.
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
