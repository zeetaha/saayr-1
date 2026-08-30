import Foundation

/// Local persistence for anti-cheat evidence.
///
/// Serves two purposes:
/// 1. **Offline queue**: proof bundles that couldn't be submitted are stored
///    and retried when connectivity returns.
/// 2. **Audit trail**: individual anti-cheat signals are logged locally so
///    the app can show the user why a check-in was rejected.
final class FraudEvidenceStore {

    private let defaults = UserDefaults(suiteName: "com.saayr.anticheat")

    // MARK: - Pending bundles (offline queue)

    func savePending(bundle: ProofBundle) {
        var pending = loadPending()
        pending.append(bundle)
        if let data = try? JSONEncoder().encode(pending) {
            defaults?.set(data, forKey: "pending_bundles")
        }
    }

    func loadPending() -> [ProofBundle] {
        guard let data = defaults?.data(forKey: "pending_bundles") else { return [] }
        return (try? JSONDecoder().decode([ProofBundle].self, from: data)) ?? []
    }

    func removePending(sessionId: String) {
        var pending = loadPending()
        pending.removeAll { $0.session_id == sessionId }
        if let data = try? JSONEncoder().encode(pending) {
            defaults?.set(data, forKey: "pending_bundles")
        }
    }

    func clearPending() {
        defaults?.removeObject(forKey: "pending_bundles")
    }

    // MARK: - Signal history (per location)

    func save(signal: AntiCheatSignal, for locationId: Int, timestamp: Date) {
        let key = "signal_history_\(locationId)"
        var history = loadHistory(for: locationId)
        let entry: [String: Any] = [
            "name": signal.name,
            "passed": signal.passed,
            "score": signal.score,
            "details": signal.details ?? "",
            "timestamp": timestamp.timeIntervalSince1970
        ]
        history.append(entry)

        // Keep only the last 50 entries per location
        if history.count > 50 {
            history = Array(history.suffix(50))
        }

        defaults?.set(history, forKey: key)
    }

    func loadHistory(for locationId: Int) -> [[String: Any]] {
        let key = "signal_history_\(locationId)"
        return (defaults?.array(forKey: key) as? [[String: Any]]) ?? []
    }

    func clearHistory(for locationId: Int) {
        let key = "signal_history_\(locationId)"
        defaults?.removeObject(forKey: key)
    }

    // MARK: - General

    func clearAll() {
        clearPending()
        if let dict = defaults?.dictionaryRepresentation() {
            for key in dict.keys where key.hasPrefix("signal_history_") {
                defaults?.removeObject(forKey: key)
            }
        }
    }
}
