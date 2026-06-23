import Foundation
import CoreLocation
import Combine

/// State machine that tracks how long a user stays inside a merchant's
/// geofence zone and publishes progress for the UI.
///
/// Flow: `idle → scanning → dwelling → verifiedDwell → collecting → submitted`
///
/// The merchant zone is defined by a centre point + radius (from the
/// `NearbyLocationResponse`). The server does the final polygon check
/// on the collected GPS trace — this is a client-side proximity gate
/// for UX responsiveness.
final class DwellMonitor: ObservableObject {

    // MARK: - Published

    /// Overall state of the dwell machine.
    @Published private(set) var state: DwellState = .idle

    /// Progress from 0.0 to 1.0 (maps to the progress bar in the UI).
    @Published private(set) var progress: Double = 0.0

    /// Seconds remaining in the minimum dwell period (for countdown display).
    @Published private(set) var secondsRemaining: Int = 0

    // MARK: - Configuration (overridden by server thresholds)

    /// Minimum seconds inside the merchant zone to count as a valid dwell.
    var dwellSecondsMin: Int = 30

    /// Extra radius added to the merchant's zone when entering (generous).
    var enterBufferMeters: Double = 10

    /// Extra radius for exiting (hysteresis prevents flicker at the edge).
    var exitHysteresisMeters: Double = 20

    /// Seconds to spend collecting the final proof bundle after dwell is verified.
    var proofCollectionSeconds: Int = 5

    // MARK: - Private

    private var dwellStartDate: Date?
    private var dwellTimer: Timer?
    private var dwellElapsed: Int = 0

    private var merchantCenter: CLLocationCoordinate2D?
    private var merchantRadiusMeters: Double = 0
    private var currentLocationManager: FilteredLocationManager?

    private var enterRadius: Double { merchantRadiusMeters + enterBufferMeters }
    private var exitRadius: Double { merchantRadiusMeters + exitHysteresisMeters }
    private var wasInside: Bool = false
    private var consecutiveInside: Int = 0
    private let requiredInsideCount: Int = 3   // 3 consecutive inside-fixes before dwelling starts

    private let checkInStore = CheckInStateStore()

    // MARK: - Public API

    /// Begins watching for the user to enter the merchant zone.
    /// Call this when the user taps "Check In".
    func beginMonitoring(
        merchantCenter: CLLocationCoordinate2D,
        merchantRadiusMeters: Double,
        locationManager: FilteredLocationManager
    ) {
        // Apply remote thresholds
        let config = AntiCheatAPI.thresholds
        dwellSecondsMin = config.dwell_seconds_min
        enterBufferMeters = config.enter_buffer_meters
        exitHysteresisMeters = config.exit_hysteresis_meters

        self.merchantCenter = merchantCenter
        self.merchantRadiusMeters = merchantRadiusMeters
        self.currentLocationManager = locationManager

        state = .scanning
        wasInside = false
        consecutiveInside = 0
        dwellElapsed = 0

        // Recover from force-quit
        if let restored = checkInStore.restoreDwellState(), restored.locationId > 0 {
            print("🔄 DwellMonitor: recovered interrupted dwell for location \(restored.locationId)")
            checkInStore.clear()
            state = .idle
        }
    }

    /// Cancels the dwell monitoring (user tapped cancel or left the zone).
    func cancel() {
        stopTimer()
        checkInStore.clear()
        merchantCenter = nil
        currentLocationManager = nil
        state = .idle
        progress = 0
        secondsRemaining = 0
        dwellElapsed = 0
    }

    /// Must be called periodically (e.g. from a Combine publisher or MapView
    /// camera update) with the latest user location.
    func updateUserLocation(_ location: CLLocation) {
        guard let center = merchantCenter else { return }

        let merchantLoc = CLLocation(
            latitude: center.latitude,
            longitude: center.longitude
        )
        let distance = location.distance(from: merchantLoc)

        switch state {
        case .idle, .submitted, .failed:
            return

        case .scanning:
            if distance <= enterRadius {
                consecutiveInside += 1
                if consecutiveInside >= requiredInsideCount {
                    startDwelling()
                }
            } else {
                consecutiveInside = max(0, consecutiveInside - 1)
            }

        case .dwelling:
            if distance > exitRadius {
                // Left the zone — cancel
                print("🔴 DwellMonitor: left zone (\(String(format: "%.0f", distance))m > \(Int(exitRadius))m)")
                cancel()
            }

        case .verifiedDwell, .collecting:
            // No-op during final collection phase; the user is committed.
            break
        }
    }

    /// Transitions from `verifiedDwell` to `collecting`.
    /// Called by `SignalCollector` when it begins assembling the proof bundle.
    func startCollecting() {
        state = .collecting
    }

    /// Transitions to `submitted` (called after server response).
    func markSubmitted() {
        stopTimer()
        checkInStore.clear()
        state = .submitted
    }

    /// Transitions to `failed` with a reason.
    func markFailed(reason: String) {
        stopTimer()
        checkInStore.clear()
        state = .failed(reason: reason)
    }

    // MARK: - Private

    private func startDwelling() {
        dwellStartDate = Date()
        state = .dwelling(startedAt: dwellStartDate!)
        consecutiveInside = 0
        dwellElapsed = 0

        checkInStore.saveDwellState(locationId: 0, startedAt: dwellStartDate!)

        // Start the progress timer
        dwellTimer?.invalidate()
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        dwellElapsed += 1
        let rawProgress = Double(dwellElapsed) / Double(dwellSecondsMin)
        progress = min(rawProgress, 1.0)
        secondsRemaining = max(dwellSecondsMin - dwellElapsed, 0)

        if dwellElapsed >= dwellSecondsMin {
            guard case .dwelling = state else { return }
            stopTimer()
            state = .verifiedDwell
            progress = 1.0
        }

        // Also re-check location inside-zone during dwell
        if let center = merchantCenter,
           let location = currentLocationManager?.currentLocation {
            let merchantLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let distance = location.distance(from: merchantLoc)
            if distance > exitRadius {
                cancel()
            }
        }
    }

    private func stopTimer() {
        dwellTimer?.invalidate()
        dwellTimer = nil
    }

    deinit {
        stopTimer()
    }
}
