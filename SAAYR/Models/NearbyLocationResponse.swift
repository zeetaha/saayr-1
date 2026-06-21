//
//  NearbyLocationResponse.swift
//  SAAYR
//
//  Created by Awais Raza on 19/01/2026.
//

import Foundation
import CoreLocation
import Alamofire


struct NearbyLocationResponse: Identifiable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let city: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let radius_meters: Int
    let xp_reward: Int
    let category: String
    let image_url: String?
    let can_checkin: Bool
    let is_partner: Bool
    let zone_id: Int?
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

// New response envelope for v1.0.7+ nearby
struct NearbyAPIResponse: Decodable {
    let locations: [NearbyLocationResponse]
    let newly_unlocked_zone: ZoneUnlockInfo?
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

extension NearbyLocationResponse: Decodable { }

extension NearbyLocationResponse {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}


final class LocationAPI {

    static let shared = LocationAPI()

    func fetchNearby(
        latitude: Double,
        longitude: Double,
        radiusKM: Int = 5,
        completion: @escaping @Sendable ([NearbyLocationResponse], ZoneUnlockInfo?) -> Void
    ) {
        let params: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "radius_km": radiusKM
        ]

        ServiceModel.shared.postRequest(
            endpoint: WebService.nearBy,
            parameters: params
        ) { result in
            switch result {
            case .success(let data):
                // Try new envelope format first, fall back to legacy array
                if let envelope = try? JSONDecoder().decode(NearbyAPIResponse.self, from: data) {
                    DispatchQueue.main.async {
                        completion(envelope.locations, envelope.newly_unlocked_zone)
                    }
                } else if let legacy = try? JSONDecoder().decode([NearbyLocationResponse].self, from: data) {
                    DispatchQueue.main.async {
                        completion(legacy, nil)
                    }
                } else {
                    print("❌ Decoding error: unrecognised nearby response shape")
                    DispatchQueue.main.async { completion([], nil) }
                }

            case .failure(let error):
                print("❌ API error:", error.localizedDescription)
                DispatchQueue.main.async { completion([], nil) }
            }
        }
    }
    
    func checkIn(
            locationId: Int,
            userCoordinate: CLLocationCoordinate2D,
            dryRun: Bool,
            completion: @escaping @Sendable (Result<CheckInResponse, Error>) -> Void,
        ) {


            let params: [String: Any] = [
                "location_id": locationId,
                "latitude": userCoordinate.latitude,
                "longitude": userCoordinate.longitude,
                "dry_run": dryRun
            ]

            

            ServiceModel.shared.postRequest(
                endpoint: WebService.checkIn,
                parameters: params
            ) { result in
                switch result {
                case .success(let data):
                    do {
                        let decoded = try JSONDecoder().decode(CheckInResponse.self, from: data)
                        
                        DispatchQueue.main.async {
                            if decoded.success {
                                completion(.success(decoded))  // Only call if success == true
                            } else {
                                print("❌ Check-in failed:", decoded.message)
                                // Optionally, send a failure or ignore
                                completion(.failure(NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: decoded.message])))
                            }
                        }
                        
                    } catch {
                        print("❌ Decode error:", error)
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }

                case .failure(let error):
                    print("❌ API error:", error.localizedDescription)
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }

        }
    }


struct MapCenter: Equatable {
    let latitude: Double
    let longitude: Double
}
