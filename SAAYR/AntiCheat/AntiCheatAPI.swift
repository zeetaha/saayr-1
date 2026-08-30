import Foundation
import UIKit

/// Server communication for the anti-cheat verification pipeline.
///
/// Uses `URLSession` directly (not Alamofire) to match the reliability pattern
/// already established by `HealthKitManager` — Alamofire's session can be
/// suspended during short background execution windows.
final class AntiCheatAPI {

    /// Thresholds fetched from the server. Falls back to `ThresholdConfig.default`.
    private(set) static var thresholds: ThresholdConfig = .default

    // MARK: - Verify Check-In

    /// Submits a `ProofBundle` to the server for independent scoring.
    ///
    /// - Parameters:
    ///   - bundle: The full evidence bundle collected during the dwell period.
    ///   - completion: Called on the main queue with the server's verdict.
//    static func verifyCheckIn(
//        bundle: ProofBundle,
//        completion: @escaping @Sendable (Result<VerificationResult, Error>) -> Void
//    ) {
//        guard let url = URL(string: WebService.verifyCheckin) else {
//            DispatchQueue.main.async {
//                completion(.failure(AntiCheatError.invalidURL))
//            }
//            return
//        }
//
//        var request = URLRequest(url: url, timeoutInterval: 30)
//        request.httpMethod = "POST"
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.setValue("application/json", forHTTPHeaderField: "accept")
//        request.setValue(UserModel.shared.languageCode, forHTTPHeaderField: "Language-Code")
//
//        if let token = UserModel.shared.currentAccessToken, !token.isEmpty {
//            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
//        }
//
//        let encoder = JSONEncoder()
//        encoder.outputFormatting = [.sortedKeys]
//        encoder.dateEncodingStrategy = .iso8601
//
//        do {
//            request.httpBody = try encoder.encode(bundle)
//        } catch {
//            DispatchQueue.main.async {
//                completion(.failure(AntiCheatError.encodingFailed(error)))
//            }
//            return
//        }
//
//        URLSession.shared.dataTask(with: request) { data, response, error in
//            if let error {
//                DispatchQueue.main.async {
//                    completion(.failure(AntiCheatError.networkError(error)))
//                }
//                return
//            }
//
//            guard let httpResponse = response as? HTTPURLResponse,
//                  let data = data else {
//                DispatchQueue.main.async {
//                    completion(.failure(AntiCheatError.invalidResponse))
//                }
//                return
//            }
//
//            guard (200...299).contains(httpResponse.statusCode) else {
//                DispatchQueue.main.async {
//                    completion(.failure(AntiCheatError.httpError(httpResponse.statusCode)))
//                }
//                return
//            }
//
//            let decoder = JSONDecoder()
//            decoder.dateDecodingStrategy = .iso8601
//
//            do {
//                let result = try decoder.decode(VerificationResult.self, from: data)
//                DispatchQueue.main.async {
//                    completion(.success(result))
//                }
//            } catch {
//                DispatchQueue.main.async {
//                    completion(.failure(AntiCheatError.decodingFailed(error)))
//                }
//            }
//        }.resume()
//    }
//
//    // MARK: - Fetch Thresholds
//
//    /// Fetches the latest anti-cheat threshold configuration from the server.
//    /// Call on app launch and periodically to pick up remote changes.
//    static func fetchThresholds(completion: @escaping @Sendable (Bool) -> Void = { _ in }) {
//        guard let url = URL(string: WebService.thresholds) else {
//            completion(false)
//            return
//        }
//
//        var request = URLRequest(url: url, timeoutInterval: 15)
//        request.setValue("application/json", forHTTPHeaderField: "accept")
//        request.setValue(UserModel.shared.languageCode, forHTTPHeaderField: "Language-Code")
//
//        if let token = UserModel.shared.currentAccessToken, !token.isEmpty {
//            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
//        }
//
//        URLSession.shared.dataTask(with: request) { data, _, error in
//            guard let data, error == nil else {
//                DispatchQueue.main.async { completion(false) }
//                return
//            }
//
//            let decoder = JSONDecoder()
//            if let config = try? decoder.decode(ThresholdConfig.self, from: data) {
//                DispatchQueue.main.async {
//                    thresholds = config
//                    print("✅ Anti-cheat thresholds updated to v\(config.version)")
//                    completion(true)
//                }
//            } else {
//                DispatchQueue.main.async { completion(false) }
//            }
//        }.resume()
//    }
//
//    // MARK: - Submit Fraud Report
//
//    /// Submits a client-detected local fraud signal for server-side logging.
//    static func submitFraudReport(
//        locationId: Int,
//        signal: AntiCheatSignal,
//        sessionId: String,
//        completion: @escaping @Sendable (Bool) -> Void = { _ in }
//    ) {
//        guard let url = URL(string: WebService.fraudReport) else {
//            completion(false)
//            return
//        }
//
//        let body: [String: Any] = [
//            "location_id": locationId,
//            "session_id": sessionId,
//            "signal_name": signal.name,
//            "signal_passed": signal.passed,
//            "signal_score": signal.score,
//            "signal_details": signal.details ?? ""
//        ]
//
//        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
//            completion(false)
//            return
//        }
//
//        var request = URLRequest(url: url, timeoutInterval: 15)
//        request.httpMethod = "POST"
//        request.httpBody = httpBody
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.setValue("application/json", forHTTPHeaderField: "accept")
//        if let token = UserModel.shared.currentAccessToken, !token.isEmpty {
//            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
//        }
//
//        URLSession.shared.dataTask(with: request) { _, response, _ in
//            let success = (response as? HTTPURLResponse)?.statusCode == 200
//            DispatchQueue.main.async { completion(success) }
//        }.resume()
//    }
}

// MARK: - Errors

enum AntiCheatError: LocalizedError {
    case invalidURL
    case encodingFailed(Error)
    case networkError(Error)
    case invalidResponse
    case httpError(Int)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid verification URL"
        case .encodingFailed(let e): return "Failed to encode proof: \(e.localizedDescription)"
        case .networkError(let e):   return "Network error: \(e.localizedDescription)"
        case .invalidResponse:       return "Invalid server response"
        case .httpError(let code):   return "Server error (HTTP \(code))"
        case .decodingFailed(let e): return "Failed to decode server response: \(e.localizedDescription)"
        }
    }
}
