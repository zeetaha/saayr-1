import Foundation
import CoreLocation
import UIKit
import Combine

/// Assembles a `ProofBundle` from all available signal sources when a dwell
/// period completes.
///
/// The collector runs for a short window (`proofCollectionSeconds`) after the
/// dwell is verified, snapshots the GPS trace, pedometer data, device integrity
/// signals, and network info, then submits to the server.
final class SignalCollector: ObservableObject {

    // MARK: - Published

    /// Current collection progress (0.0 → 1.0 during the collection window).
    @Published private(set) var collectionProgress: Double = 0.0

    /// Whether the collector is actively gathering signals.
    @Published private(set) var isCollecting: Bool = false

    /// The assembled bundle (non-nil once collection completes).
    @Published private(set) var bundle: ProofBundle?

    // MARK: - Private

    private var collectionTimer: Timer?
    private var collectionElapsed: Int = 0
    private let collectionSeconds: Int
    private var locationId: Int = 0
    private var dwellStartDate: Date?
    private var sessionId: String = ""
    private weak var locationManager: FilteredLocationManager?

    // MARK: - Init

    init(collectionSeconds: Int = 5) {
        self.collectionSeconds = collectionSeconds
    }

    // MARK: - Public API

    /// Begins the final signal collection window.
    /// Call this when `DwellMonitor.state` transitions to `.verifiedDwell`.
    func startCollection(
        for locationId: Int,
        dwellMonitor: DwellMonitor,
        locationManager: FilteredLocationManager
    ) {
        self.locationId = locationId
        self.locationManager = locationManager
        self.sessionId = UUID().uuidString
        self.collectionElapsed = 0
        self.isCollecting = true
        self.bundle = nil

        // Snapshot dwell start time from the monitor's state
        if case .dwelling(let startedAt) = dwellMonitor.state {
            self.dwellStartDate = startedAt
        } else {
            self.dwellStartDate = Date()
        }

        dwellMonitor.startCollecting()

        collectionTimer?.invalidate()
        collectionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick(dwellMonitor: dwellMonitor)
        }
    }

    /// Cancels collection (e.g. if the user dismisses mid-collection).
    func cancel() {
        collectionTimer?.invalidate()
        collectionTimer = nil
        isCollecting = false
        collectionProgress = 0
        bundle = nil
    }

    // MARK: - Private

    private func tick(dwellMonitor: DwellMonitor) {
        collectionElapsed += 1
        collectionProgress = Double(collectionElapsed) / Double(collectionSeconds)

        if collectionElapsed >= collectionSeconds {
            finalize(dwellMonitor: dwellMonitor)
        }
    }

    private func finalize(dwellMonitor: DwellMonitor) {
        collectionTimer?.invalidate()
        collectionTimer = nil
        isCollecting = false
        collectionProgress = 1.0

        guard let manager = locationManager else {
            dwellMonitor.markFailed(reason: "Location manager unavailable during collection")
            return
        }

        // 1. GPS trace — last 30 seconds
        let gpsTrace = manager.trace(lastSeconds: 30).map { GPSSample(from: $0) }

        // 2. Final position
        let finalLocation = manager.currentLocation
        let finalLat = finalLocation?.coordinate.latitude ?? 0
        let finalLng = finalLocation?.coordinate.longitude ?? 0
        let finalAccuracy = finalLocation?.horizontalAccuracy ?? 0
        let finalTimestamp = finalLocation?.timestamp ?? Date()
        let finalSpeed = finalLocation?.speed ?? -1

        // 3. GPS-derived metrics
        let gpsDistance = MotionCorroborator.totalDistance(from: gpsTrace)
        let gpsAvgSpeed: Double = {
            guard gpsTrace.count >= 2 else { return 0 }
            let first = gpsTrace.first!, last = gpsTrace.last!
            let deltaT = last.timestamp.timeIntervalSince(first.timestamp)
            return deltaT > 0 ? gpsDistance / deltaT : 0
        }()

        // 4. Pedometer data (from HealthKitManager)
        let pedometerSteps = HealthKitManager.shared.liveStepCount
        let pedometerPace: Double? = nil   // CMPedometer doesn't expose pace directly per-session

        // 5. Device integrity
        let isJailbroken = DeviceIntegrity.isJailbroken()
        let isDebugger = DeviceIntegrity.isDebuggerAttached()
        let isSimulator = DeviceIntegrity.isSimulator()
        let isMockLocation = manager.isSimulated

        // 6. Network info
        let wifiSSID = Self.fetchCurrentSSID()

        // 7. Timing
        let dwellDuration = dwellStartDate.map { Date().timeIntervalSince($0) } ?? 0
        let timezoneOffset = TimeZone.current.secondsFromGMT()

        // 8. Assemble bundle
        let bundle = ProofBundle(
            location_id: locationId,
            session_id: sessionId,
            gps_trace: gpsTrace,
            final_latitude: finalLat,
            final_longitude: finalLng,
            final_horizontal_accuracy: finalAccuracy,
            final_timestamp: finalTimestamp,
            final_speed: finalSpeed,
            pedometer_steps_since_dwell_start: pedometerSteps,
            pedometer_average_pace: pedometerPace,
            gps_average_speed: gpsAvgSpeed,
            gps_travel_distance_meters: gpsDistance,
            is_jailbroken: isJailbroken,
            is_debugger_attached: isDebugger,
            is_simulator: isSimulator,
            is_mock_location: isMockLocation,
            ip_address: nil,      // Server fills this from the TCP connection
            wifi_ssid: wifiSSID,
            dwell_started_at: dwellStartDate ?? Date(),
            dwell_duration_seconds: dwellDuration,
            device_time_at_submission: Date(),
            timezone_offset: timezoneOffset,
            threshold_version: AntiCheatAPI.thresholds.version
        )

        self.bundle = bundle
        dwellMonitor.markSubmitted()

        print("✅ SignalCollector: proof bundle assembled for location \(locationId)")
        print("   GPS trace: \(gpsTrace.count) samples, "
              + "distance: \(String(format: "%.1f", gpsDistance))m, "
              + "steps: \(pedometerSteps)")
    }

    // MARK: - Helpers

    private static func fetchCurrentSSID() -> String? {
        // iOS requires the "Wi-Fi Access" capability and location access
        // to read the SSID. Return nil silently if unavailable.
        return nil
    }

    deinit {
        collectionTimer?.invalidate()
    }
}
