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

    /// Prints the bearer token on its own, in a form that can be pasted
    /// straight into a shell, whenever it changes.
    ///
    /// Separate from `logsAuthorizationHeader` on purpose: that one repeats the
    /// token on every single request, which buries it. This prints once per
    /// token — including after a refresh, so what's on screen is always the one
    /// that currently works.
    static var logsTokenForCurl = true

    /// Last token printed, so a refresh re-prints and nothing else does.
    private static var lastPrintedToken: String?

    let queue = DispatchQueue(label: "com.saayr.apilogger")

    // MARK: - Request

    /// Hooked on URL-request creation rather than on `requestDidResume`:
    /// Alamofire builds the `URLRequest` asynchronously, so at resume time
    /// `request.request` is usually still nil and there is nothing to print.
    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        guard Self.isEnabled else { return }

        Self.logTokenIfChanged(in: urlRequest)

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

    // MARK: - Token

    /// Reads the token off an outgoing request rather than from `TokenManager`,
    /// so what's printed is provably the one being sent — if the header is
    /// missing, that's the bug, and the log says so instead of showing a stored
    /// token that never made it onto the wire.
    private static func logTokenIfChanged(in urlRequest: URLRequest) {
        guard logsTokenForCurl else { return }

        guard let header = urlRequest.value(forHTTPHeaderField: "Authorization") else {
            // Only worth saying once, and only before any token has been seen —
            // plenty of calls legitimately go out unauthenticated (login).
            if lastPrintedToken == nil {
                lastPrintedToken = ""
                print("🔑 No Authorization header on \(path(of: urlRequest.url)) — not signed in yet?")
            }
            return
        }

        let token = header.hasPrefix("Bearer ")
            ? String(header.dropFirst("Bearer ".count))
            : header

        guard token != lastPrintedToken else { return }
        lastPrintedToken = token

        let base = WebService.baseUrl

        print("""

        ┌───────────── 🔑 BEARER TOKEN (DEBUG) ─────────────
        \(token)

        Paste into your shell:
        export TOKEN='\(token)'
        export BASE='\(base)'

        Then, for the map pins:
        curl -s -X POST "$BASE"locations/nearby \\
          -H 'Content-Type: application/json' \\
          -H "Authorization: Bearer $TOKEN" \\
          -d '{"latitude":24.88580,"longitude":46.63710,"radius_km":20}'
        └───────────────────────────────────────────────────

        """)
    }

    // MARK: - Helpers

    /// Path only: the host is the same for every call and just pushes the
    /// interesting part off the line.
    ///
    /// Not private: `SSELogger` renders its lines the same way, and the two
    /// logs are read side by side.
    static func path(of url: URL?) -> String {
        guard let url else { return "(no url)" }
        let query = url.query.map { "?\($0)" } ?? ""
        return url.path + query
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > bodyCharacterLimit else { return text }
        return text.prefix(bodyCharacterLimit) + "… (\(text.count) chars)"
    }
}

// MARK: - SSE

/// The same treatment for the streams. They don't go through Alamofire, so
/// `EventSource` calls this directly rather than an `EventMonitor` picking
/// them up.
///
/// ```
/// 📡 OPEN   /api/v1/boss/1/live-feed
/// 📡 200    /api/v1/boss/1/live-feed (connected)
/// 📨 state  /api/v1/boss/1/live-feed  {"hp_percent":67,…}
/// 📨 feed   /api/v1/boss/1/live-feed  {"actor":"Sultan",…}
/// ⚠️ DROP   /api/v1/boss/1/live-feed — retrying in 4s
/// 🔌 CLOSE  /api/v1/boss/1/live-feed
/// ```
enum SSELogger {

    static var isEnabled = true

    /// Whether to print each frame's payload. Off leaves just the event names,
    /// which is usually enough once you know the shapes.
    static var logsEventData = true

    /// Shorter than the request logger's limit: stream frames arrive every few
    /// seconds, so a long one scrolls the interesting lines away.
    static var dataCharacterLimit = 400

    /// Event names to skip entirely. Add `"state"` to mute the battle
    /// heartbeat — it ticks every ~3s and drowns out `feed` and `ended`.
    static var mutedEvents: Set<String> = []

    static func connecting(_ url: URL) {
        guard isEnabled else { return }
        print("📡 OPEN   \(APILogger.path(of: url))")
    }

    static func opened(_ url: URL, status: Int) {
        guard isEnabled else { return }
        print("📡 \(status)    \(APILogger.path(of: url)) (connected)")
    }

    static func event(_ url: URL, name: String, data: String) {
        guard isEnabled, !mutedEvents.contains(name) else { return }

        // Padded so the paths line up in a column when several events
        // interleave.
        let label = name.padding(toLength: max(6, name.count), withPad: " ", startingAt: 0)
        var line = "📨 \(label) \(APILogger.path(of: url))"
        if logsEventData {
            line += "  \(truncated(data))"
        }
        print(line)
    }

    static func dropped(_ url: URL, error: Error?, retryIn delay: TimeInterval?) {
        guard isEnabled else { return }

        var line = "⚠️ DROP   \(APILogger.path(of: url))"
        if let delay { line += " — retrying in \(Int(delay))s" }
        if let error { line += "\n   \(error.localizedDescription)" }
        print(line)
    }

    static func closed(_ url: URL) {
        guard isEnabled else { return }
        print("🔌 CLOSE  \(APILogger.path(of: url))")
    }

    private static func truncated(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > dataCharacterLimit else { return flat }
        return flat.prefix(dataCharacterLimit) + "… (\(flat.count) chars)"
    }
}
#endif
