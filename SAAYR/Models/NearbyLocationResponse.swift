//
//  NearbyLocationResponse.swift
//  SAAYR
//
//  Created by Awais Raza on 19/01/2026.
//

import Foundation
import CoreLocation
import Alamofire


struct NearbyLocationResponse: Identifiable, Sendable, Codable {

    // MARK: - Core fields
    let id: Int
    let name: String
    let description: String?
    let city: String
    let address: String?

    let latitude: Double
    let longitude: Double

    let radius_meters: Int
    let xp_reward: Int
    let cooldown_hours: Int

    let category: String?
    let image_url: String?

    let can_checkin: Bool
    let is_partner: Bool
    let zone_id: Int?

    // MARK: - Extended backend fields
    let is_active: Bool?
    let created_at: String?

    let last_checkin: String?
    let cooldown_remaining_minutes: Int?

    let merchant_id: Int?
    let merchant_name: String?

    // MARK: - King / ownership metadata (NEW)
    let king_user_id: Int?
    let king_falcon_name: String?
    let king_full_name: String?
    
    let type: String?

    /// Polygon boundary (nil = circular geofence only)
    let boundary_polygon: [PolygonPoint]?

    // MARK: - Landmark discovery
    /// All optional: the discovery endpoints aren't live yet, so a response
    /// without them still decodes and the client falls back to `type` and to
    /// locally stored discoveries.
    let is_landmark: Bool?
    let is_discovered: Bool?
    let discovered_at: String?
    let description_ar: String?
    /// Emoji the backend picks for the pin, e.g. "📍".
    let icon: String?

    // MARK: - Helpers

    /// Description in the player's language, falling back to the other one
    /// rather than showing nothing — a landmark with only an Arabic write-up
    /// should still say something to an English player.
    func localizedDescription(isEnglish: Bool) -> String? {
        let preferred = isEnglish ? description : description_ar
        let fallback  = isEnglish ? description_ar : description
        let chosen = [preferred, fallback]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return chosen
    }

    /// Landmarks are the pins that stay a mystery until the player stands in
    /// them. The server flag wins; `type` is the fallback until it ships.
    var isLandmark: Bool {
        if let is_landmark { return is_landmark }
        guard let type = type?.lowercased() else { return false }
        return ["landmark", "landmarks", "hidden_gem", "hidden_gems", "mystery"].contains(type)
    }

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    var uniqueKey: String {
        let typeValue = type ?? "unknown"
        let latText = String(format: "%.6f", latitude)
        let lngText = String(format: "%.6f", longitude)
        return "\(id)|\(typeValue)|\(latText)|\(lngText)"
    }

    var hasPolygon: Bool {
        boundary_polygon?.isEmpty == false
    }

    // Optional: safe center fallback for UI / map camera
    var polygonCenter: CLLocationCoordinate2D? {
        guard let boundary_polygon, !boundary_polygon.isEmpty else { return nil }

        let lat = boundary_polygon.map(\.lat).reduce(0, +) / Double(boundary_polygon.count)
        let lng = boundary_polygon.map(\.lng).reduce(0, +) / Double(boundary_polygon.count)

        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case city
        case address
        case latitude
        case longitude
        case radius_meters
        case xp_reward
        case cooldown_hours
        case category
        case image_url
        case can_checkin
        case is_partner
        case zone_id

        case is_active
        case created_at
        case last_checkin
        case cooldown_remaining_minutes
        case merchant_id
        case merchant_name

        case king_user_id
        case king_falcon_name
        case king_full_name

        case boundary_polygon
        case type

        case is_landmark
        case is_discovered
        case discovered_at
        case description_ar
        case icon
    }
}


struct PolygonPoint: Codable, Sendable, Hashable {
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: lat, longitude: lng)
    }
}
// MARK: - Fog of War models

struct ZoneCoordinate: Decodable {
    let lat: Double
    let lng: Double
}

struct Zone: Identifiable, Decodable {
    let id: Int
    let name: String
    let name_ar: String
    let description: String?
    let description_ar: String?
    let boundary_polygon: [ZoneCoordinate]
    let center_lat: String
    let center_lng: String
    let is_unlocked: Bool
}

struct ZoneUnlockInfo: Decodable {
    let zone_id: Int
    let headline_en: String
    let headline_ar: String
    let body_en: String
    let body_ar: String
    let cta_en: String
    let cta_ar: String
    let center_lat: String
    let center_lng: String
}

// MARK: - Landmark detail

/// A landmark this player has already found.
///
/// The detail lives here rather than on the location itself: an undiscovered
/// landmark comes back with `description` nulled out, so the payload can't be
/// read to spoil what a mystery pin is. Once discovered, the same landmark
/// appears in `discovered_landmarks` with everything filled in.
struct DiscoveredLandmark: Decodable, Sendable, Hashable {
    let landmark_id: Int
    let name: String?
    let name_ar: String?
    let description: String?
    let description_ar: String?
    let icon: String?
    let xp_earned: Int?

    func localizedName(isEnglish: Bool) -> String? {
        Self.pick(isEnglish ? name : name_ar, isEnglish ? name_ar : name)
    }

    func localizedDescription(isEnglish: Bool) -> String? {
        Self.pick(isEnglish ? description : description_ar,
                  isEnglish ? description_ar : description)
    }

    /// First of the two that has actual text in it. The backend sends `"\n"`
    /// and empty strings for unwritten copy, which would otherwise render as a
    /// blank paragraph.
    private static func pick(_ preferred: String?, _ fallback: String?) -> String? {
        [preferred, fallback]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

// New response envelope for v1.0.7+ nearby
struct NearbyAPIResponse: Decodable {
    let locations: [NearbyLocationResponse]
    let newly_unlocked_zone: ZoneUnlockInfo?
    /// Every landmark the player has found, with the detail to show for it.
    let discovered_landmarks: [DiscoveredLandmark]?
    /// Set on the one response that crosses the geofence, if the backend is
    /// driving discovery. Decoded so it's available; the reveal is currently
    /// still triggered client-side.
    let newly_discovered_landmark: DiscoveredLandmark?
}


struct CheckInResponse: Codable {
    let success: Bool
    let message: String
    let xp_earned: Int
    let total_xp: Int
    let new_level: Int
    let level_up: Bool
    let distance_meters: Double
    let checkin_id: Int?   // ✅ Now can accept null
}

//extension NearbyLocationResponse: Decodable { }
//
//extension NearbyLocationResponse {
//    var coordinate: CLLocationCoordinate2D {
//        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
//    }
//}


final class LocationAPI {
    
    static let shared = LocationAPI()
    
    // MARK: - Caching & Debouncing
    private var cachedNearby: [NearbyLocationResponse] = []
    /// Kept alongside the pins so a failed refresh doesn't blank the detail on
    /// a landmark card the player already has open.
    private var cachedLandmarks: [DiscoveredLandmark] = []
    private var cacheTimestamp: Date? = nil
    private let cacheExpiry: TimeInterval = 600 // 10 minutes
    private let debounceInterval: TimeInterval = 1.0 // 1 second
    private var lastFetchTime: Date? = nil
    private var pendingFetchTask: Task<Void, Never>? = nil
    
    // Request deduplication
    private var inFlightCheckIns: Set<String> = []
    
    func fetchNearby(
        latitude: Double,
        longitude: Double,
        radiusKM: Int = 5,
        completion: @escaping @Sendable ([NearbyLocationResponse], ZoneUnlockInfo?, [DiscoveredLandmark]) -> Void
    ) {
        // Debounce rapid requests
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < debounceInterval {
            return
        }
        
        lastFetchTime = Date()
        
        let params: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "radius_km": radiusKM
        ]
        
        ServiceModel.shared.postRequest(
            endpoint: WebService.nearBy,
            parameters: params,
            completion: { result in
                switch result {
                case .success(let data):
                    do {
                        // Try new envelope format first, fall back to legacy array
                        if let envelope = try? JSONDecoder().decode(NearbyAPIResponse.self, from: data) {
                            DispatchQueue.main.async {
                                self.cachedNearby = envelope.locations
                                self.cachedLandmarks = envelope.discovered_landmarks ?? []
                                self.cacheTimestamp = Date()
                                completion(
                                    envelope.locations,
                                    envelope.newly_unlocked_zone,
                                    envelope.discovered_landmarks ?? []
                                )
                            }
                        } else if let legacy = try? JSONDecoder().decode([NearbyLocationResponse].self, from: data) {
                            DispatchQueue.main.async {
                                self.cachedNearby = legacy
                                self.cacheTimestamp = Date()
                                completion(legacy, nil, [])
                            }
                        } else {
                            print("❌ Decoding error: unrecognised nearby response shape")
                            DispatchQueue.main.async { completion(self.cachedNearby, nil, self.cachedLandmarks) }
                        }
                    } catch {
                        print("❌ JSON decode error:", error)
                        DispatchQueue.main.async { completion(self.cachedNearby, nil, self.cachedLandmarks) }
                    }

                case .failure(let error):
                    print("❌ API error:", error.localizedDescription)
                    DispatchQueue.main.async {
                        // Return cached data if available, even if stale
                        completion(self.cachedNearby, nil, self.cachedLandmarks)
                    }
                }
            }
        )
    }
    
    func clearNearbyCache() {
        cachedNearby = []
        cachedLandmarks = []
        cacheTimestamp = nil
    }
    
    func checkIn(
        locationId: Int,
        type:String?,
        userCoordinate: CLLocationCoordinate2D,
        dryRun: Bool,
        completion: @escaping @Sendable (Result<CheckInResponse, Error>) -> Void
    ) {
        
        let requestKey = "\(locationId)_\(dryRun)"
        
        // Prevent duplicate requests in flight
        if inFlightCheckIns.contains(requestKey) {
            print("⚠️ Duplicate checkIn request blocked: \(requestKey)")
            return
        }
        
        inFlightCheckIns.insert(requestKey)
        
        let params: [String: Any] = [
            "location_id": locationId,
            "type": type ?? "",
            "latitude": userCoordinate.latitude,
            "longitude": userCoordinate.longitude,
            "dry_run": dryRun
        ]
        
        ServiceModel.shared.postRequest(
            endpoint: WebService.checkIn,
            parameters: params,
            completion: { [weak self] result in
                defer {
                    self?.inFlightCheckIns.remove(requestKey)
                }
                
                switch result {
                case .success(let data):
                    do {
                        let decoded = try JSONDecoder().decode(CheckInResponse.self, from: data)
                        
                        DispatchQueue.main.async {
                            if decoded.success {
                                completion(.success(decoded))
                            } else {
                                print("❌ Check-in failed:", decoded.message)
                                let error = NSError(
                                    domain: "CheckInError",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: decoded.message]
                                )
                                completion(.failure(error))
                            }
                        }
                        
                    } catch {
                        print("❌ Decode error:", error)
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                    
                case .failure(let error):
                    print("❌ API error:", error.localizedDescription)
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        )
    }
}


struct MapCenter: Equatable {
    let latitude: Double
    let longitude: Double
}
