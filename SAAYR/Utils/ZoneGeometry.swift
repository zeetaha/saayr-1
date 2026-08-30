//
//  ZoneGeometry.swift
//  SAAYR
//
//  Decides which merchants the player is allowed to see, given the zones
//  they've unlocked.
//

import Foundation
import CoreLocation

enum ZoneVisibility {

    /// Keeps only the locations standing inside an unlocked zone.
    ///
    /// The map blacks out everything outside those zones, so a pin on that
    /// ground would advertise a merchant the player can't reach — and tapping a
    /// pin is the only way into the check-in flow. Locked zones are shaded but
    /// still drawn, and they're off-limits too, so their pins go as well.
    ///
    /// Fails open: with no zones at all — the fetch failed, or hasn't returned
    /// yet — every location is kept. That matches the fog, which leaves the map
    /// uncovered rather than blacking out a screen it has no data for. Zones
    /// that loaded but are all locked is a real answer, not missing data, so
    /// that genuinely yields nothing.
    static func inUnlockedZones(
        _ locations: [NearbyLocationResponse],
        zones: [Zone]
    ) -> [NearbyLocationResponse] {

        guard !zones.isEmpty else { return locations }

        let unlocked = zones
            .filter(\.is_unlocked)
            .compactMap { zone in
                PolygonArea(ring: zone.boundary_polygon.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                })
            }

        guard !unlocked.isEmpty else { return [] }

        return locations.filter { location in
            unlocked.contains { $0.contains(location.coordinate) }
        }
    }

}

/// A closed boundary with its bounding box precomputed, so the common case —
/// a point nowhere near this ring — costs four comparisons instead of a walk
/// around a several-hundred-point ring. Used for zone visibility and for
/// landmark discovery.
struct PolygonArea {

    let ring: [CLLocationCoordinate2D]
    let minLat: Double
    let maxLat: Double
    let minLng: Double
    let maxLng: Double

    init?(ring: [CLLocationCoordinate2D]) {
        guard ring.count >= 3 else { return nil }

        let lats = ring.map(\.latitude)
        let lngs = ring.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max()
        else { return nil }

        self.ring = ring
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLng = minLng
        self.maxLng = maxLng
    }

    func contains(_ point: CLLocationCoordinate2D) -> Bool {
        guard point.latitude  >= minLat, point.latitude  <= maxLat,
              point.longitude >= minLng, point.longitude <= maxLng
        else { return false }

        // Ray casting: count how many times a ray heading west from the
        // point crosses the boundary. Odd means inside. Treats lat/lng as a
        // flat plane, which holds at city scale.
        var isInside = false
        var previous = ring.count - 1

        for current in ring.indices {
            let a = ring[current]
            let b = ring[previous]

            // Does this edge straddle the point's latitude? If so the
            // latitudes differ, so the division below is safe.
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let t = (point.latitude - a.latitude) / (b.latitude - a.latitude)
                let crossingLng = a.longitude + t * (b.longitude - a.longitude)
                if point.longitude < crossingLng {
                    isInside.toggle()
                }
            }
            previous = current
        }

        return isInside
    }
}

/// Whether the player is standing in a landmark.
///
/// The boundary polygon is the real answer when the backend supplies one; a
/// landmark that only has a centre and a radius falls back to that circle. The
/// floor on the radius keeps a landmark configured with a tiny (or zero) radius
/// from being impossible to walk into given normal GPS scatter.
enum LandmarkGeofence {

    static let minimumRadiusMeters: Double = 50

    static func contains(
        _ coordinate: CLLocationCoordinate2D,
        of location: NearbyLocationResponse
    ) -> Bool {
        if let ring = location.boundary_polygon, ring.count >= 3,
           let area = PolygonArea(ring: ring.map(\.coordinate)) {
            return area.contains(coordinate)
        }

        return distance(from: coordinate, to: location) <= radius(of: location)
    }

    static func radius(of location: NearbyLocationResponse) -> Double {
        max(Double(location.radius_meters), minimumRadiusMeters)
    }

    /// The ground the player has to stand on, as a drawable ring: the boundary
    /// polygon when the landmark has one, otherwise its geofence circle traced
    /// out. Matches what `contains` tests, so what's drawn is exactly what
    /// counts — including the floor applied to a tiny radius.
    static func boundaryRing(of location: NearbyLocationResponse, segments: Int = 64) -> [PolygonPoint] {
        if let ring = location.boundary_polygon, ring.count >= 3 { return ring }

        let radiusMeters = radius(of: location)
        let latitudeDegrees = radiusMeters / 111_000
        // Longitude degrees shrink towards the poles, so the circle stays round
        // on the map instead of being squashed into an ellipse.
        let longitudeDegrees = latitudeDegrees / max(cos(location.latitude * .pi / 180), 0.01)

        return (0..<segments).map { step in
            let angle = 2 * Double.pi * Double(step) / Double(segments)
            return PolygonPoint(
                lat: location.latitude + latitudeDegrees * cos(angle),
                lng: location.longitude + longitudeDegrees * sin(angle)
            )
        }
    }

    /// Metres between the player and the landmark's centre — for the "how close
    /// am I" readout on a pin that hasn't been revealed yet.
    static func distance(
        from coordinate: CLLocationCoordinate2D,
        to location: NearbyLocationResponse
    ) -> Double {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: location.latitude, longitude: location.longitude))
    }
}
