import Foundation
import CoreLocation

/// Cross-checks GPS-derived movement against pedometer data.
///
/// A real visit shows both GPS movement and step count increasing together.
/// Location changes + zero steps = strong fraud signal.
struct MotionCorroborator {

    /// Computes a discrepancy score between GPS movement and pedometer steps.
    ///
    /// - Parameters:
    ///   - gpsTrace: Time-ordered GPS samples from the dwell period.
    ///   - pedometerSteps: Steps counted by CMPedometer during the same period.
    ///   - averageStrideMeters: Estimated stride length. Defaults to 0.5 m
    ///     (conservative average). In practice the server already has this value
    ///     from the user's HealthKit profile, but we use a sensible default
    ///     client-side for the proof bundle.
    /// - Returns: A score from 0.0 (perfect match) to 1.0 (complete mismatch).
    static func discrepancyScore(
        gpsTrace: [GPSSample],
        pedometerSteps: Int,
        averageStrideMeters: Double = 0.5
    ) -> Double {
        guard pedometerSteps > 0 else {
            // No steps at all — if GPS also shows no movement, score stays low.
            let gpsDistanceMeters = totalDistance(from: gpsTrace)
            return gpsDistanceMeters > 10 ? 0.8 : 0.0
        }

        let gpsDistanceMeters = totalDistance(from: gpsTrace)
        let estimatedPedometerMeters = Double(pedometerSteps) * averageStrideMeters

        guard estimatedPedometerMeters > 0 else { return 0.5 }

        let ratio = gpsDistanceMeters / estimatedPedometerMeters

        // ratio near 1.0 = GPS and pedometer agree
        // ratio >> 1.0 = GPS moved but phone says no steps (spoof)
        // ratio << 1.0 = steps but no GPS movement (walking in place, stationary spoof)

        if ratio > 3.0 { return 1.0 }   // GPS moving, no steps — strong spoof
        if ratio < 0.3 { return 0.7 }   // steps but no GPS movement — suspicious

        return abs(1.0 - ratio).clamped(to: 0...1)
    }

    // MARK: - Helpers

    static func totalDistance(from trace: [GPSSample]) -> Double {
        guard trace.count >= 2 else { return 0 }

        var distance: Double = 0
        for i in 1..<trace.count {
            let prev = CLLocation(latitude: trace[i-1].latitude, longitude: trace[i-1].longitude)
            let curr = CLLocation(latitude: trace[i].latitude, longitude: trace[i].longitude)
            distance += curr.distance(from: prev)
        }
        return distance
    }
}

// MARK: - Clamping helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
