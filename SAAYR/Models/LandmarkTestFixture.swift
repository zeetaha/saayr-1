//
//  LandmarkTestFixture.swift
//  SAAYR
//
//  A fake landmark for exercising the discovery flow without waiting on the
//  backend. DEBUG only — none of this compiles into a release build.
//

#if DEBUG
import Foundation
import CoreLocation

enum LandmarkTestFixture {

    /// Master switch. Set to `false` to take the fake landmark off the map.
    static let isEnabled = true

    /// Its id is negative so it can never collide with a real location, which
    /// also keeps its saved "discovered" state out of the way of real data.
    static let id = -9001

    /// How far from the player it's planted, and how big it is. Placed just
    /// outside its own radius so the mystery pin is visible first and stepping
    /// towards it is what triggers the reveal.
    static let offsetMeters: Double = 90
    static let radiusMeters = 60

    /// Plants the landmark north of `anchor`.
    static func landmark(near anchor: CLLocationCoordinate2D) -> NearbyLocationResponse {
        // 1° of latitude ≈ 111 km, so this is a straight push north.
        let latitude = anchor.latitude + (offsetMeters / 111_000)
        let longitude = anchor.longitude

        return NearbyLocationResponse(
            id: id,
            name: "Al Masmak Fortress",
            description: "A clay-and-mud-brick fort at the heart of old Riyadh, "
                + "where the city's modern story began in 1902.",
            city: "Riyadh",
            address: "Al Dirah, Riyadh",
            latitude: latitude,
            longitude: longitude,
            radius_meters: radiusMeters,
            xp_reward: 250,
            cooldown_hours: 24,
            category: "Heritage",
            image_url: nil,
            can_checkin: true,
            is_partner: false,
            zone_id: nil,
            is_active: true,
            created_at: nil,
            last_checkin: nil,
            cooldown_remaining_minutes: nil,
            merchant_id: nil,
            merchant_name: nil,
            king_user_id: nil,
            king_falcon_name: nil,
            king_full_name: nil,
            type: "landmark",
            boundary_polygon: nil,
            is_landmark: true,
            is_discovered: nil,
            discovered_at: nil,
            description_ar: "قلعة من الطين في قلب الرياض القديمة، حيث بدأت قصة المدينة الحديثة عام ١٩٠٢.",
            icon: "🏰"
        )
    }
}
#endif
