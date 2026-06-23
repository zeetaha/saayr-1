import Foundation
import Alamofire

/// Alamofire interceptor that manages access‑token lifecycle:
/// - **Adapt**: proactively refresh before the token expires, then inject the Bearer header.
/// - **Retry**: on 401, refresh the token once and retry the original request.
final class TokenInterceptor: RequestInterceptor {

    private let queue = DispatchQueue(label: "com.saayr.token-interceptor", qos: .utility)

    // MARK: - Adapt

    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping (Result<URLRequest, Error>) -> Void
    ) {
        var request = urlRequest

        // Proactive refresh — runs synchronously on a background queue but
        // won't block the calling thread since Alamofire calls adapt on its own queue.
        let group = DispatchGroup()
        var refreshError: Error?

        group.enter()
        TokenManager.shared.refreshIfNeeded { result in
            if case .failure(let error) = result {
                refreshError = error
            }
            group.leave()
        }
        group.wait()

        if let error = refreshError {
            // If the session itself expired, there's no point attaching a token.
            // AuthManager will pick up the .sessionExpired notification and logout.
            completion(.success(request))
            return
        }

        // Inject Bearer token if available
        if let token = TokenManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        completion(.success(request))
    }

    // MARK: - Retry

    func retry(
        _ request: Request,
        for session: Session,
        dueTo error: Error,
        completion: @escaping (RetryResult) -> Void
    ) {
        guard let response = request.response,
              response.statusCode == 401,
              request.retryCount == 0          // only retry once
        else {
            completion(.doNotRetry)
            return
        }

        // Attempt to refresh the token
        TokenManager.shared.refreshIfNeeded { result in
            switch result {
            case .success:
                // Token refreshed — retry the original request
                completion(.retry)
            case .failure:
                // Could not refresh — don't retry
                completion(.doNotRetry)
            }
        }
    }
}
