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
                Area(ring: zone.boundary_polygon.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                })
            }

        guard !unlocked.isEmpty else { return [] }

        return locations.filter { location in
            unlocked.contains { $0.contains(location.coordinate) }
        }
    }

    /// A zone boundary with its bounding box precomputed, so the common case —
    /// a merchant nowhere near this zone — costs four comparisons instead of a
    /// walk around a several-hundred-point ring.
    private struct Area {

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
}
