import Foundation
import CoreLocation

/// Detects impossible travel between consecutive GPS fixes.
///
/// Iterates through a time-ordered GPS trace and flags any adjacent pair
/// whose implied speed exceeds the threshold — a hallmark of teleport-style
/// location spoofing.
struct ImpossibleTravel {

    /// Checks whether the GPS trace contains any impossible-speed transitions.
    ///
    /// - Parameters:
    ///   - trace: Time-ordered array of `GPSSample` values.
    ///   - maxPlausibleSpeedKMH: Speed threshold in km/h (default 150 km/h
    ///     — covers highway driving with margin). Use a lower value like
    ///     120 km/h for stricter urban detection.
    /// - Returns: `true` if any adjacent pair exceeds the speed threshold.
    static func check(trace: [GPSSample],
                      maxPlausibleSpeedKMH: Double = 150) -> Bool {
        guard trace.count >= 2 else { return false }

        for i in 1..<trace.count {
            let prev = trace[i - 1]
            let curr = trace[i]

            let deltaT = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard deltaT > 0 else { continue }

            let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
            let distanceMeters = currLoc.distance(from: prevLoc)

            let speedKMH = (distanceMeters / deltaT) * 3.6

            if speedKMH > maxPlausibleSpeedKMH {
                print("🔴 ImpossibleTravel: \(Int(speedKMH)) km/h between samples "
                      + "(\(i-1)→\(i), Δt=\(String(format: "%.1f", deltaT))s)")
                return true
            }
        }

        return false
    }
}
