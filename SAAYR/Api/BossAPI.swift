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

    /// Joins or leaves the waitlist. Idempotent in both directions; the server
    /// answers 400 if the boss isn't scheduled any more.
    func toggleWaitlist(
        bossID: Int,
        join: Bool,
        completion: @escaping (WaitlistToggleResponse?) -> Void
    ) {
        ServiceModel.shared.postRequest(
            endpoint: WebService.bossWaitlist(bossID),
            parameters: ["join": join]
        ) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                completion(self.decode(WaitlistToggleResponse.self, from: result, label: "waitlist toggle"))
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
