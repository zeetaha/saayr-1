//
//  APILogger.swift
//  SAAYR
//
//  Console logging for every request the app makes. DEBUG only — none of this
//  compiles into a release build, where logging request bodies and tokens
//  would be a liability rather than a convenience.
//

#if DEBUG
import Foundation
import Alamofire

/// Logs each request as it's sent and each response as it lands.
///
/// ```
/// ⬆️ POST /api/v1/locations/nearby
///    body: {"latitude":24.7136,"longitude":46.6753,"radius_km":20}
/// ⬇️ 200 POST /api/v1/locations/nearby (412 ms)
///    {"locations":[…]}
/// ```
final class APILogger: EventMonitor {

    /// Set to `false` to silence the log without unpicking the wiring.
    static var isEnabled = true

    /// Response bodies are trimmed to this many characters — a nearby fetch
    /// returns far more than is useful to read in a console.
    static var bodyCharacterLimit = 2_000

    /// Authorization is redacted by default: the console is shoulder-surfable
    /// and tokens end up in saved logs. Flip it on when you need to copy one
    /// for curl.
    static var logsAuthorizationHeader = false

    let queue = DispatchQueue(label: "com.saayr.apilogger")

    // MARK: - Request

    /// Hooked on URL-request creation rather than on `requestDidResume`:
    /// Alamofire builds the `URLRequest` asynchronously, so at resume time
    /// `request.request` is usually still nil and there is nothing to print.
    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        guard Self.isEnabled else { return }

        let method = urlRequest.httpMethod ?? "?"
        var lines = ["⬆️ \(method) \(Self.path(of: urlRequest.url))"]

        if let headers = urlRequest.allHTTPHeaderFields, !headers.isEmpty {
            let rendered = headers
                .filter { Self.logsAuthorizationHeader || $0.key.lowercased() != "authorization" }
                .map { "\($0.key): \($0.value)" }
                .sorted()
                .joined(separator: ", ")
            if !rendered.isEmpty { lines.append("   headers: \(rendered)") }
        }

        if let body = urlRequest.httpBody, let text = String(data: body, encoding: .utf8) {
            lines.append("   body: \(Self.truncated(text))")
        }

        print(lines.joined(separator: "\n"))
    }

    // MARK: - Response

    /// The generic hook is the one that fires for `responseData`, which is how
    /// every call in `ServiceModel` is made. The `Data?` variant below only
    /// fires for the raw `response()` form.
    func request<Value: Sendable>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        log(request: request,
            status: response.response?.statusCode,
            duration: response.metrics?.taskInterval.duration,
            data: response.data,
            error: response.error)
    }

    func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>) {
        log(request: request,
            status: response.response?.statusCode,
            duration: response.metrics?.taskInterval.duration,
            data: response.data,
            error: response.error)
    }

    private func log(
        request: DataRequest,
        status: Int?,
        duration seconds: TimeInterval?,
        data: Data?,
        error: AFError?
    ) {
        guard Self.isEnabled else { return }

        let method = request.request?.httpMethod ?? "?"
        let path = Self.path(of: request.request?.url)
        let duration = Int((seconds ?? 0) * 1000)

        // A failure is what you're usually hunting for, so it gets a louder mark
        // and always prints its body, however long.
        let isFailure = status.map { $0 >= 400 } ?? true
        let marker = isFailure ? "❌" : "⬇️"
        let statusText = status.map(String.init) ?? "no response"

        var lines = ["\(marker) \(statusText) \(method) \(path) (\(duration) ms)"]

        if let error {
            lines.append("   error: \(error.localizedDescription)")
        }

        if let data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
            lines.append("   \(isFailure ? text : Self.truncated(text))")
        }

        print(lines.joined(separator: "\n"))
    }

    // MARK: - Helpers

    /// Path only: the host is the same for every call and just pushes the
    /// interesting part off the line.
    private static func path(of url: URL?) -> String {
        guard let url else { return "(no url)" }
        let query = url.query.map { "?\($0)" } ?? ""
        return url.path + query
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > bodyCharacterLimit else { return text }
        return text.prefix(bodyCharacterLimit) + "… (\(text.count) chars)"
    }
}
#endif
