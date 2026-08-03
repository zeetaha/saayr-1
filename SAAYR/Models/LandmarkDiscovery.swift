//
//  LandmarkDiscovery.swift
//  SAAYR
//
//  Landmarks stay a mystery on the map until the player physically stands
//  inside them. This file owns that state: what has been revealed, how it is
//  kept across launches and devices, and how a reveal is detected.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Server payloads

/// Response to reporting a discovery. Every field is optional: the endpoint
/// isn't live yet, and when it is, the client should still work against a
/// slimmer payload than this.
struct LandmarkDiscoveryResponse: Decodable {
    let success: Bool?
    let xp_awarded: Int?
    let total_xp: Int?
    let already_discovered: Bool?
}

/// Everything this player has revealed, for a fresh install or second device.
/// Accepts either a list of objects or a bare list of ids, so whichever shape
/// the backend lands on works without another client release.
struct LandmarkDiscoveriesResponse: Decodable {

    struct Entry: Decodable {
        let location_id: Int
        let discovered_at: String?
    }

    let discoveries: [Entry]?
    let location_ids: [Int]?

    var ids: [Int] {
        if let discoveries { return discoveries.map(\.location_id) }
        return location_ids ?? []
    }
}

// MARK: - Storage

/// Discovered landmarks, per user, on disk.
///
/// Discovery is permanent, so this never removes an id — it only ever adds.
/// The server is the long-term record; this store is what makes a reveal
/// survive a force-quit, a flight-mode walk, or an endpoint that isn't
/// deployed yet.
final class LandmarkDiscoveryStore {

    static let shared = LandmarkDiscoveryStore()

    private let defaults = UserDefaults(suiteName: "com.saayr.discoveries")
    private let guestKey = "guest"

    /// Which user's shelf we're reading. Set once the profile is known;
    /// anything discovered before that is filed under `guest` and adopted.
    private(set) var userKey: String

    private init() {
        userKey = UserModel.shared.user.map { String($0.id) } ?? guestKey
    }

    // MARK: Keys

    private func discoveredKey(for user: String) -> String { "discovered_v1_\(user)" }
    private func pendingKey(for user: String) -> String { "pending_sync_v1_\(user)" }
    private func timestampsKey(for user: String) -> String { "discovered_at_v1_\(user)" }
    private func coordinatesKey(for user: String) -> String { "discovered_coord_v1_\(user)" }

    // MARK: User

    /// Points the store at a specific user, carrying over anything discovered
    /// before the profile loaded. Called when the profile arrives.
    func adoptUser(id: Int?) {
        let newKey = id.map(String.init) ?? guestKey
        guard newKey != userKey else { return }

        // Only the guest shelf is ever carried across. Switching from one
        // account to another must not hand over the first player's discoveries.
        let wasGuest = userKey == guestKey
        let carriedOver = wasGuest ? discoveredIDs() : []
        let carriedPending = wasGuest ? pendingIDs() : []
        let carriedTimestamps = wasGuest ? timestamps() : [:]
        let carriedCoordinates = wasGuest ? coordinates() : [:]

        userKey = newKey

        guard wasGuest, !carriedOver.isEmpty else { return }

        write(discoveredIDs().union(carriedOver), forKey: discoveredKey(for: userKey))
        write(pendingIDs().union(carriedPending), forKey: pendingKey(for: userKey))

        var mergedStamps = timestamps()
        for (id, date) in carriedTimestamps where mergedStamps[id] == nil { mergedStamps[id] = date }
        defaults?.set(mergedStamps, forKey: timestampsKey(for: userKey))

        var mergedCoords = coordinates()
        for (id, pair) in carriedCoordinates where mergedCoords[id] == nil { mergedCoords[id] = pair }
        defaults?.set(mergedCoords, forKey: coordinatesKey(for: userKey))

        // Folded in — don't let it reappear under the next account.
        defaults?.removeObject(forKey: discoveredKey(for: guestKey))
        defaults?.removeObject(forKey: pendingKey(for: guestKey))
        defaults?.removeObject(forKey: timestampsKey(for: guestKey))
        defaults?.removeObject(forKey: coordinatesKey(for: guestKey))
    }

    // MARK: Reads

    func discoveredIDs() -> Set<Int> {
        Set(defaults?.array(forKey: discoveredKey(for: userKey)) as? [Int] ?? [])
    }

    func isDiscovered(_ locationID: Int) -> Bool {
        discoveredIDs().contains(locationID)
    }

    /// Discoveries the server hasn't acknowledged yet.
    func pendingIDs() -> Set<Int> {
        Set(defaults?.array(forKey: pendingKey(for: userKey)) as? [Int] ?? [])
    }

    func discoveredAt(_ locationID: Int) -> Date? {
        timestamps()[String(locationID)].map(Date.init(timeIntervalSince1970:))
    }

    /// Where the player was standing when they revealed this landmark. Kept so
    /// a discovery made offline can still be reported with the fix that earned
    /// it, however much later the server hears about it.
    func discoveredCoordinate(_ locationID: Int) -> CLLocationCoordinate2D? {
        guard let pair = coordinates()[String(locationID)], pair.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
    }

    // MARK: Writes

    /// Records a reveal. `needsSync` is false when the server told us about it.
    func markDiscovered(
        _ locationID: Int,
        at date: Date = Date(),
        coordinate: CLLocationCoordinate2D? = nil,
        needsSync: Bool = true
    ) {
        write(discoveredIDs().union([locationID]), forKey: discoveredKey(for: userKey))

        var stamps = timestamps()
        if stamps[String(locationID)] == nil {
            stamps[String(locationID)] = date.timeIntervalSince1970
            defaults?.set(stamps, forKey: timestampsKey(for: userKey))
        }

        if let coordinate {
            var coords = coordinates()
            coords[String(locationID)] = [coordinate.latitude, coordinate.longitude]
            defaults?.set(coords, forKey: coordinatesKey(for: userKey))
        }

        if needsSync {
            write(pendingIDs().union([locationID]), forKey: pendingKey(for: userKey))
        }
    }

    func markSynced(_ locationID: Int) {
        write(pendingIDs().subtracting([locationID]), forKey: pendingKey(for: userKey))

        // The fix only mattered as evidence for the report that just landed.
        var coords = coordinates()
        coords.removeValue(forKey: String(locationID))
        defaults?.set(coords, forKey: coordinatesKey(for: userKey))
    }

    /// Folds the server's record into the local one. Union, never replace: a
    /// discovery made offline is still real and still queued for sync.
    func merge(serverIDs: [Int]) {
        guard !serverIDs.isEmpty else { return }
        write(discoveredIDs().union(serverIDs), forKey: discoveredKey(for: userKey))
        write(pendingIDs().subtracting(serverIDs), forKey: pendingKey(for: userKey))
    }

    // MARK: Helpers

    private func timestamps() -> [String: Double] {
        defaults?.dictionary(forKey: timestampsKey(for: userKey)) as? [String: Double] ?? [:]
    }

    private func coordinates() -> [String: [Double]] {
        defaults?.dictionary(forKey: coordinatesKey(for: userKey)) as? [String: [Double]] ?? [:]
    }

    private func write(_ ids: Set<Int>, forKey key: String) {
        defaults?.set(Array(ids), forKey: key)
    }
}

// MARK: - API

/// Talks to the discovery endpoints. Both calls are best-effort: nothing here
/// is allowed to block a reveal, because the local store already made it
/// permanent.
final class LandmarkAPI {

    static let shared = LandmarkAPI()

    private init() {}

    func reportDiscovery(
        locationID: Int,
        coordinate: CLLocationCoordinate2D,
        discoveredAt: Date,
        completion: @escaping (LandmarkDiscoveryResponse?) -> Void
    ) {
        let params: [String: Any] = [
            "location_id": locationID,
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "discovered_at": ISO8601DateFormatter().string(from: discoveredAt)
        ]

        ServiceModel.shared.postRequest(
            endpoint: WebService.landmarkDiscover,
            parameters: params
        ) { result in
            switch result {
            case .success(let data):
                let decoded = try? JSONDecoder().decode(LandmarkDiscoveryResponse.self, from: data)
                DispatchQueue.main.async { completion(decoded) }
            case .failure(let error):
                print("⚠️ Landmark discovery not recorded server-side:", error.localizedDescription)
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    func fetchDiscoveries(completion: @escaping ([Int]?) -> Void) {
        ServiceModel.shared.getRequest(endpoint: WebService.landmarkDiscoveries) { result in
            switch result {
            case .success(let data):
                if let decoded = try? JSONDecoder().decode(LandmarkDiscoveriesResponse.self, from: data) {
                    DispatchQueue.main.async { completion(decoded.ids) }
                } else if let ids = try? JSONDecoder().decode([Int].self, from: data) {
                    DispatchQueue.main.async { completion(ids) }
                } else {
                    print("⚠️ Unrecognised discoveries response shape")
                    DispatchQueue.main.async { completion(nil) }
                }
            case .failure(let error):
                print("⚠️ Discoveries unavailable:", error.localizedDescription)
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}

// MARK: - Service

/// The reveal moment: which landmark, and what it paid out.
struct LandmarkReveal: Identifiable, Equatable {
    let landmark: NearbyLocationResponse
    /// The landmark's advertised reward until the server confirms the actual
    /// award, which is then filled in here.
    var xpAwarded: Int

    var id: Int { landmark.id }

    static func == (lhs: LandmarkReveal, rhs: LandmarkReveal) -> Bool {
        lhs.landmark.id == rhs.landmark.id && lhs.xpAwarded == rhs.xpAwarded
    }
}

/// Owns discovery state for the map: what's still a mystery, when a landmark
/// is entered, and what to show when one is revealed.
final class LandmarkDiscoveryService: ObservableObject {

    /// Ids the player has revealed. Drives the pins, so it's published.
    @Published private(set) var discoveredIDs: Set<Int> = []
    /// Non-nil while a reveal is on screen.
    @Published var reveal: LandmarkReveal?

    /// A fix this coarse can't be trusted to place someone inside a boundary.
    private let maximumAccuracyMeters: Double = 100

    private let store = LandmarkDiscoveryStore.shared
    /// Reveals wait their turn — walking into overlapping landmarks shouldn't
    /// stack popups on top of each other.
    private var queued: [LandmarkReveal] = []

    #if DEBUG
    private var lastProximityLog = Date.distantPast
    #endif

    // MARK: Lifecycle

    func load() {
        store.adoptUser(id: UserModel.shared.user?.id)
        discoveredIDs = store.discoveredIDs()
        syncWithServer()
    }

    /// Pulls the server's record and replays anything it hasn't acknowledged.
    func syncWithServer() {
        LandmarkAPI.shared.fetchDiscoveries { [weak self] ids in
            guard let self else { return }
            if let ids, !ids.isEmpty {
                self.store.merge(serverIDs: ids)
                self.discoveredIDs = self.store.discoveredIDs()
            }
            self.flushPending()
        }
    }

    /// Adopts `is_discovered` when the nearby payload starts carrying it.
    func adoptServerState(from locations: [NearbyLocationResponse]) {
        let discovered = locations.filter { $0.is_discovered == true }.map(\.id)
        guard !discovered.isEmpty else { return }

        store.merge(serverIDs: discovered)
        discoveredIDs = store.discoveredIDs()
    }

    // MARK: Queries

    func isDiscovered(_ location: NearbyLocationResponse) -> Bool {
        if location.is_discovered == true { return true }
        return discoveredIDs.contains(location.id)
    }

    /// A mystery pin: a landmark this player hasn't reached yet.
    func isLocked(_ location: NearbyLocationResponse) -> Bool {
        location.isLandmark && !isDiscovered(location)
    }

    func lockedKeys(in locations: [NearbyLocationResponse]) -> Set<String> {
        Set(locations.filter(isLocked).map(\.uniqueKey))
    }

    // MARK: Detection

    /// Reveals every landmark the player is currently standing in.
    ///
    /// Runs off the anti-cheat filtered fix: `FilteredLocationManager` only
    /// publishes `currentLocation` for a fix that already passed its staleness,
    /// accuracy and speed checks, so a position good enough to check in with is
    /// good enough to discover with.
    func evaluate(
        userLocation: CLLocation?,
        isSimulated: Bool,
        locations: [NearbyLocationResponse]
    ) {
        guard let userLocation else { return }

        // Simulated fixes are rejected by the pipeline itself in release builds
        // — they never reach `currentLocation`. In DEBUG it deliberately accepts
        // them, and re-banning them here would make the feature untestable on
        // the Simulator, where every fix is flagged as simulated.
        #if !DEBUG
        guard !isSimulated else { return }
        #endif

        guard userLocation.horizontalAccuracy > 0,
              userLocation.horizontalAccuracy <= maximumAccuracyMeters else { return }

        let entered = locations.filter { location in
            isLocked(location) && LandmarkGeofence.contains(userLocation.coordinate, of: location)
        }

        #if DEBUG
        logProximity(from: userLocation, locations: locations, entered: entered.count)
        #endif

        for landmark in entered {
            discover(landmark, at: userLocation.coordinate)
        }
    }

    #if DEBUG
    private var proximityLogInterval: TimeInterval { 2 }

    /// How far off the nearest mystery pin is and whether the fix counts as
    /// inside it — the two things worth knowing when a reveal doesn't fire.
    private func logProximity(from location: CLLocation, locations: [NearbyLocationResponse], entered: Int) {
        guard lastProximityLog.timeIntervalSinceNow < -proximityLogInterval else { return }
        lastProximityLog = Date()

        let locked = locations.filter(isLocked)
        guard let nearest = locked.min(by: {
            LandmarkGeofence.distance(from: location.coordinate, to: $0)
                < LandmarkGeofence.distance(from: location.coordinate, to: $1)
        }) else {
            print("🏛️ no undiscovered landmarks in range")
            return
        }

        let distance = LandmarkGeofence.distance(from: location.coordinate, to: nearest)
        let inside = LandmarkGeofence.contains(location.coordinate, of: nearest)
        print(String(
            format: "🏛️ nearest mystery #%d %.0fm away (radius %.0fm) — inside: %@, accuracy %.0fm, entered %d",
            nearest.id, distance, LandmarkGeofence.radius(of: nearest),
            inside ? "YES" : "no", location.horizontalAccuracy, entered
        ))
    }
    #endif

    /// Marks a landmark discovered, queues its reveal, and tells the server.
    private func discover(_ landmark: NearbyLocationResponse, at coordinate: CLLocationCoordinate2D) {
        guard !discoveredIDs.contains(landmark.id) else { return }

        let discoveredAt = Date()
        store.markDiscovered(landmark.id, at: discoveredAt, coordinate: coordinate)
        discoveredIDs.insert(landmark.id)

        enqueue(LandmarkReveal(landmark: landmark, xpAwarded: landmark.xp_reward))

        LandmarkAPI.shared.reportDiscovery(
            locationID: landmark.id,
            coordinate: coordinate,
            discoveredAt: discoveredAt
        ) { [weak self] response in
            guard let self, let response else { return }   // still pending; replayed on next sync
            self.store.markSynced(landmark.id)

            // Trust the server's number over the advertised one.
            guard let awarded = response.xp_awarded else { return }
            if self.reveal?.landmark.id == landmark.id {
                self.reveal?.xpAwarded = awarded
            }
            if let index = self.queued.firstIndex(where: { $0.landmark.id == landmark.id }) {
                self.queued[index].xpAwarded = awarded
            }
        }
    }

    /// Sends discoveries the server never acknowledged — made offline, or while
    /// the endpoint was still unbuilt.
    private func flushPending() {
        let pending = store.pendingIDs()
        guard !pending.isEmpty else { return }

        for id in pending {
            // Reported with the fix and time that actually earned it, not with
            // where the player happens to be standing now.
            guard let coordinate = store.discoveredCoordinate(id) else { continue }
            let at = store.discoveredAt(id) ?? Date()

            LandmarkAPI.shared.reportDiscovery(
                locationID: id,
                coordinate: coordinate,
                discoveredAt: at
            ) { [weak self] response in
                guard response != nil else { return }
                self?.store.markSynced(id)
            }
        }
    }

    // MARK: Reveal queue

    private func enqueue(_ item: LandmarkReveal) {
        if reveal == nil {
            reveal = item
        } else if !queued.contains(where: { $0.landmark.id == item.landmark.id }) {
            queued.append(item)
        }
    }

    /// Dismisses the current reveal and shows the next one, if any.
    func dismissReveal() {
        reveal = queued.isEmpty ? nil : queued.removeFirst()
    }

    #if DEBUG
    /// Reveals a landmark without walking to it, for testing the moment itself.
    func debugDiscover(_ landmark: NearbyLocationResponse) {
        discover(landmark, at: landmark.coordinate)
    }

    /// Puts every landmark back to undiscovered so the reveal can be run again.
    /// Local only — anything the server has already recorded comes back on the
    /// next sync, which is the correct behaviour for a permanent discovery.
    func debugResetDiscoveries() {
        for id in discoveredIDs { store.markSynced(id) }
        UserDefaults(suiteName: "com.saayr.discoveries")?
            .removeObject(forKey: "discovered_v1_\(store.userKey)")
        discoveredIDs = []
        reveal = nil
        queued = []
    }
    #endif
}
