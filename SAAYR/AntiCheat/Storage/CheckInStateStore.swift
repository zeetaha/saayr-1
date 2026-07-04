import Foundation

/// Persists the active dwell session so we can recover from a force-quit
/// mid-check-in and prevent the user from re-entering to get a free award.
final class CheckInStateStore {

    private let defaults = UserDefaults(suiteName: "com.saayr.anticheat")
    private let stateKey = "active_dwell_state"
    private let locationKey = "active_dwell_location_id"
    private let startedAtKey = "active_dwell_started_at"

    // MARK: - Save

    func saveDwellState(locationId: Int, startedAt: Date) {
        defaults?.set("dwelling", forKey: stateKey)
        defaults?.set(locationId, forKey: locationKey)
        defaults?.set(startedAt.timeIntervalSince1970, forKey: startedAtKey)
    }

    // MARK: - Restore

    func restoreDwellState() -> (locationId: Int, startedAt: Date)? {
        guard let state = defaults?.string(forKey: stateKey), state == "dwelling" else {
            return nil
        }
        let locationId = defaults?.integer(forKey: locationKey) ?? 0
        let interval = defaults?.double(forKey: startedAtKey) ?? 0
        guard locationId > 0, interval > 0 else { return nil }

        // Only restore if the dwell started within the last 5 minutes
        let startedAt = Date(timeIntervalSince1970: interval)
        guard abs(startedAt.timeIntervalSinceNow) < 300 else {
            clear()
            return nil
        }

        return (locationId, startedAt)
    }

    // MARK: - Clear

    func clear() {
        defaults?.removeObject(forKey: stateKey)
        defaults?.removeObject(forKey: locationKey)
        defaults?.removeObject(forKey: startedAtKey)
    }
}
