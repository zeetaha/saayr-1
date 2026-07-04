import Foundation
import Combine

/// Thread‑safe manager for OAuth tokens stored in the Keychain.
/// Handles proactive refresh (5‑minute buffer) and mutual exclusion via NSLock.
final class TokenManager {

    static let shared = TokenManager()

    // MARK: - Constants

    private let keychainKey = "com.saayr.auth.tokens"
    /// Refresh the access token when fewer than this many seconds remain.
    private let refreshBuffer: TimeInterval = 300 // 5 minutes

    // MARK: - Lock

    private let lock = NSLock()
    private var isRefreshing = false

    // MARK: - Codable payload

    private struct TokenPayload: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    // MARK: - Queries

    var accessToken: String? {
        lock.lock(); defer { lock.unlock() }
        return loadPayloadUnsafe()?.accessToken
    }

    var refreshToken: String? {
        lock.lock(); defer { lock.unlock() }
        return loadPayloadUnsafe()?.refreshToken
    }

    var isTokenExpired: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let payload = loadPayloadUnsafe() else { return true }
        return Date() >= payload.expiresAt
    }

    var isTokenExpiringSoon: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let payload = loadPayloadUnsafe() else { return true }
        return Date().addingTimeInterval(refreshBuffer) >= payload.expiresAt
    }

    /// Returns `true` if a valid (non‑expired) token exists in the Keychain.
    var isAuthenticated: Bool {
        accessToken != nil && !isTokenExpired
    }

    // MARK: - Save / Clear

    func saveTokens(access: String, refresh: String, expiresIn: TimeInterval) {
        let payload = TokenPayload(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        lock.lock()
        KeychainHelper.save(key: keychainKey, data: data)
        lock.unlock()
        print("🔐 Tokens saved to Keychain (expires in \(Int(expiresIn))s)")
    }

    func clearTokens() {
        lock.lock()
        KeychainHelper.delete(key: keychainKey)
        lock.unlock()
        print("🔐 Tokens cleared from Keychain")
    }

    // MARK: - Refresh

    /// Refresh the access token **if** it is expiring within the buffer window.
    /// This method is safe to call from multiple threads – only one refresh request
    /// will be issued at a time.
    func refreshIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()

        // Inline check — we already hold the lock, so reading the payload directly
        // avoids deadlocking on the locking variants (isTokenExpiringSoon, etc.).
        let needsRefresh: Bool = {
            guard let payload = loadPayloadUnsafe() else { return true }
            return Date().addingTimeInterval(refreshBuffer) >= payload.expiresAt
        }()

        if !needsRefresh {
            lock.unlock()
            completion(.success(()))
            return
        }

        // Another thread is already refreshing — wait by polling
        guard !isRefreshing else {
            lock.unlock()
            // Poll briefly for the in-flight refresh to finish
            pollForRefresh(attempt: 0, completion: completion)
            return
        }

        isRefreshing = true
        guard let oldRefreshToken = loadPayloadUnsafe()?.refreshToken else {
            isRefreshing = false
            lock.unlock()
            completion(.failure(TokenError.noRefreshToken))
            return
        }
        lock.unlock()

        performRefresh(refreshToken: oldRefreshToken) { [weak self] result in
            guard let self else { return }
            self.lock.lock()
            self.isRefreshing = false
            self.lock.unlock()

            switch result {
            case .success(let payload):
                self.saveTokens(access: payload.access, refresh: payload.refresh, expiresIn: payload.expiresIn)
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Private

    /// Thread‑safe read: acquires the lock and reads from Keychain.
    private func loadPayload() -> TokenPayload? {
        lock.lock(); defer { lock.unlock() }
        return loadPayloadUnsafe()
    }

    /// Unsafe read: caller MUST already hold the lock.
    private func loadPayloadUnsafe() -> TokenPayload? {
        guard let data = KeychainHelper.load(key: keychainKey),
              let payload = try? JSONDecoder().decode(TokenPayload.self, from: data)
        else { return nil }
        return payload
    }

    /// Poll briefly for another thread's in-flight refresh to complete.
    private func pollForRefresh(attempt: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard attempt < 20 else { // ~2 seconds total
            completion(.failure(TokenError.refreshTimedOut))
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            if !self.isRefreshing {
                // Refresh finished — check if token is now valid
                if self.isTokenExpired {
                    completion(.failure(TokenError.refreshFailed))
                } else {
                    completion(.success(()))
                }
            } else {
                self.pollForRefresh(attempt: attempt + 1, completion: completion)
            }
        }
    }

    /// Actual HTTP call to the refresh endpoint.
    /// Uses `URLSession.shared` directly to avoid triggering the Alamofire interceptor.
    private func performRefresh(
        refreshToken: String,
        completion: @escaping (Result<(access: String, refresh: String, expiresIn: TimeInterval), Error>) -> Void
    ) {
        guard let url = URL(string: WebService.authRefresh) else {
            completion(.failure(TokenError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let body: [String: String] = ["refresh_token": refreshToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data = data else {
                completion(.failure(TokenError.invalidResponse))
                return
            }

            switch httpResponse.statusCode {
            case 200:
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let access = json["access_token"] as? String,
                      let refresh = json["refresh_token"] as? String,
                      let expiresIn = json["expires_in"] as? TimeInterval
                else {
                    completion(.failure(TokenError.invalidResponse))
                    return
                }
                completion(.success((access, refresh, expiresIn)))

            case 401:
                // Refresh token itself has expired (90-day window) — force logout
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .sessionExpired, object: nil)
                }
                completion(.failure(TokenError.sessionExpired))

            case 403:
                // Account blocked
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = json["detail"] as? String {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .userAccountBlocked, object: detail)
                    }
                } else {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .userAccountBlocked, object: nil)
                    }
                }
                completion(.failure(TokenError.accountBlocked))

            default:
                completion(.failure(TokenError.serverError(httpResponse.statusCode)))
            }
        }.resume()
    }
}

// MARK: - Errors

enum TokenError: LocalizedError {
    case noRefreshToken
    case refreshTimedOut
    case refreshFailed
    case invalidURL
    case invalidResponse
    case sessionExpired
    case accountBlocked
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:     return "No refresh token available"
        case .refreshTimedOut:    return "Token refresh timed out"
        case .refreshFailed:      return "Token refresh failed"
        case .invalidURL:         return "Invalid refresh endpoint URL"
        case .invalidResponse:    return "Invalid refresh response"
        case .sessionExpired:     return "Session expired — please log in again"
        case .accountBlocked:     return "Account blocked"
        case .serverError(let c): return "Refresh server error (\(c))"
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Posted when the refresh token is expired (401 from /auth/refresh).
    /// AuthManager should listen and force logout.
    static let sessionExpired = Notification.Name("sessionExpired")
}
