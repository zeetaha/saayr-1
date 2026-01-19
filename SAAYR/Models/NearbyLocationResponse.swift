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
        completion: @escaping @Sendable ([NearbyLocationResponse]) -> Void
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
                do {
                    let decoded = try JSONDecoder().decode(
                        [NearbyLocationResponse].self,
                        from: data
                    )

                    DispatchQueue.main.async {
                        completion(decoded)
                    }

                } catch {
                    print("❌ Decoding error:", error)
                    DispatchQueue.main.async {
                        completion([])
                    }
                }

            case .failure(let error):
                print("❌ API error:", error.localizedDescription)
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    func checkIn(
            locationId: Int,
            userCoordinate: CLLocationCoordinate2D,
            completion: @escaping @Sendable (Result<CheckInResponse, Error>) -> Void
        ) {


            let params: [String: Any] = [
                "location_id": locationId,
                "latitude": userCoordinate.latitude,
                "longitude": userCoordinate.longitude
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
