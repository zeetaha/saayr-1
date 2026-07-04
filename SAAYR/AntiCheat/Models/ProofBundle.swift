import Foundation
import CoreLocation

// MARK: - GPS Sample

struct GPSSample: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    let speed: Double
    let course: Double
    let altitude: Double

    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.accuracy = location.horizontalAccuracy
        self.timestamp = location.timestamp
        self.speed = location.speed >= 0 ? location.speed : -1
        self.course = location.course >= 0 ? location.course : -1
        self.altitude = location.altitude
    }
}

// MARK: - Proof Bundle

struct ProofBundle: Codable {
    let location_id: Int
    let session_id: String

    // GPS trace (last 30 seconds, 1 Hz sample)
    let gps_trace: [GPSSample]

    // Final position
    let final_latitude: Double
    let final_longitude: Double
    let final_horizontal_accuracy: Double
    let final_timestamp: Date
    let final_speed: Double

    // Motion signals
    let pedometer_steps_since_dwell_start: Int
    let pedometer_average_pace: Double?
    let gps_average_speed: Double
    let gps_travel_distance_meters: Double

    // Device integrity
    let is_jailbroken: Bool
    let is_debugger_attached: Bool
    let is_simulator: Bool
    let is_mock_location: Bool

    // Network
    let ip_address: String?
    let wifi_ssid: String?

    // Timing
    let dwell_started_at: Date
    let dwell_duration_seconds: TimeInterval
    let device_time_at_submission: Date
    let timezone_offset: Int

    // Configuration snapshot
    let threshold_version: String
}

// MARK: - Fraud Flag

struct FraudFlag: Codable {
    let signal: String
    let severity: String      // "low" | "medium" | "high"
    let description: String
}

// MARK: - Verification Result

struct VerificationResult: Codable {
    let verdict: String           // "approved" | "rejected" | "shadow_queue"
    let confidence_score: Double
    let reason_codes: [String]
    let xp_earned: Int
    let total_xp: Int
    let level_up: Bool
    let new_level: Int
    let checkin_id: Int?
    let fraud_flags: [FraudFlag]
}

// MARK: - Anti-Cheat Signal

struct AntiCheatSignal: Codable {
    let name: String
    let passed: Bool
    let score: Double         // 0.0 (clean) – 1.0 (definite fraud)
    let details: String?
}

// MARK: - Threshold Configuration

struct ThresholdConfig: Codable {
    let version: String
    let dwell_seconds_min: Int
    let enter_buffer_meters: Double
    let exit_hysteresis_meters: Double
    let max_gps_accuracy: Double
    let max_plausible_speed_kmh: Double
    let motion_discrepancy_max: Double
    let min_confidence_approve: Double
    let min_confidence_shadow: Double

    static let `default` = ThresholdConfig(
        version: "1.0",
        dwell_seconds_min: 30,
        enter_buffer_meters: 10,
        exit_hysteresis_meters: 20,
        max_gps_accuracy: 50,
        max_plausible_speed_kmh: 150,
        motion_discrepancy_max: 0.7,
        min_confidence_approve: 0.7,
        min_confidence_shadow: 0.4
    )
}
