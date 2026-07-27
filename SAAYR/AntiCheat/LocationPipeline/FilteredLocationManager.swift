import Foundation
import CoreLocation
import Combine

final class FilteredLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published

    @Published private(set) var currentLocation: CLLocation?

    /// The newest fix Core Location handed us, before any of the anti-cheat
    /// filtering below. Only for display — pointing the camera somewhere is
    /// harmless, so it shouldn't wait on a fix good enough to check in with.
    /// Anything that grants a reward must still use `currentLocation`.
    @Published private(set) var lastRawLocation: CLLocation?
    @Published private(set) var filteredLocations: [CLLocation] = []
    @Published private(set) var isStationary: Bool = false
    @Published private(set) var horizontalAccuracy: Double = 0
    @Published private(set) var isSimulated: Bool = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Why Core Location last failed, so the UI can say something better than
    /// "try again". Cleared as soon as a fix arrives.
    @Published private(set) var lastLocationError: CLError.Code?

    // MARK: - Debug / Simulator Support

    private var allowMockLocations: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Configuration

    var maxAcceptableAccuracy: Double = 50
    var minDistanceDelta: Double = 2.0
    var maxPlausibleSpeedKMH: Double = 200

    // MARK: - Private state

    private let manager: CLLocationManager
    private var lastKnownGoodLocation: CLLocation?
    private var stationaryCount: Int = 0
    private let stationaryThreshold = 5
    private var locationUpdateCount: Int = 0

    // MARK: - Init

    override init() {
        self.manager = CLLocationManager()
        super.init()
        configureManager()
    }

    func trace(lastSeconds: TimeInterval = 30) -> [CLLocation] {
        let cutoff = Date().addingTimeInterval(-lastSeconds)
        return filteredLocations.filter { $0.timestamp >= cutoff }
    }
    
    private func configureManager() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone

        // IMPORTANT: safe for simulator + avoids crash if capability missing
        manager.pausesLocationUpdatesAutomatically = false

        // Only enable background updates if you REALLY need them
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Public API

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func resetBuffer() {
        filteredLocations.removeAll()
        lastKnownGoodLocation = nil
        locationUpdateCount = 0
    }

    // MARK: - Delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        DispatchQueue.main.async {
            self.authorizationStatus = status
        }

        if status == .authorizedWhenInUse || status == .authorizedAlways {
            startUpdating()
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            processLocation(location)
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        if code == .locationUnknown {
            // Transient before the first fix — but permanent on a Simulator with
            // no location set, which looks identical to a device that is simply
            // still searching.
            print("⚠️ Location unknown. On the Simulator set Features → Location.")
        } else {
            print("⚠️ Location error: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            self.lastLocationError = code
        }
    }

    // MARK: - Core pipeline

    private func processLocation(_ location: CLLocation) {

        // Recorded before the filters so the map always has somewhere to look,
        // even while every fix is being rejected below.
        DispatchQueue.main.async {
            self.lastRawLocation = location
            self.lastLocationError = nil
        }

        // 1. Simulated location detection
        let simulated: Bool
        if #available(iOS 15.0, *) {
            simulated = location.sourceInformation?.isSimulatedBySoftware ?? false
        } else {
            simulated = false
        }

        DispatchQueue.main.async {
            self.isSimulated = simulated
        }

        if simulated && !(allowMockLocations || isSimulator) {
            print("🔴 Rejected simulated location")
            return
        }

        if simulated {
            print("🟡 ACCEPTING simulated location (DEBUG)")
        }

        // 2. Stale check
        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard age < 10 else {
            print("⚠️ stale location")
            return
        }

        // 3. Accuracy check
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= maxAcceptableAccuracy else {
            print("⚠️ poor accuracy: \(location.horizontalAccuracy)")
            return
        }

        // 4. Distance filter
        if let last = lastKnownGoodLocation {
            let delta = location.distance(from: last)
            if delta < minDistanceDelta {
                DispatchQueue.main.async {
                    self.currentLocation = location
                    self.horizontalAccuracy = location.horizontalAccuracy
                }
                return
            }
        }

        // 5. Speed calculation
        let speedKMH: Double
        if location.speed >= 0 {
            speedKMH = location.speed * 3.6
        } else if let last = lastKnownGoodLocation {
            let d = location.distance(from: last)
            let t = location.timestamp.timeIntervalSince(last.timestamp)
            speedKMH = t > 0 ? (d / t) * 3.6 : 0
        } else {
            speedKMH = 0
        }

        // 6. Accept location
        lastKnownGoodLocation = location
        locationUpdateCount += 1

        DispatchQueue.main.async {
            self.currentLocation = location
            self.horizontalAccuracy = location.horizontalAccuracy

            self.filteredLocations.append(location)

            let cutoff = Date().addingTimeInterval(-60)
            self.filteredLocations = self.filteredLocations.filter {
                $0.timestamp >= cutoff
            }

            self.updateStationaryState(speedKMH: speedKMH)
        }
    }

    private func updateStationaryState(speedKMH: Double) {
        if speedKMH < 1.8 { // 0.5 m/s
            stationaryCount += 1
        } else {
            stationaryCount = 0
        }
        isStationary = stationaryCount >= stationaryThreshold
    }
}
