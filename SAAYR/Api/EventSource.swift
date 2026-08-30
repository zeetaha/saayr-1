//
//  EventSource.swift
//  SAAYR
//
//  A minimal Server-Sent Events client, built on URLSession's streaming
//  delegate. Alamofire is request/response shaped and can't hold an open feed,
//  and the boss screens are specified to take one persistent connection each
//  rather than poll.
//
//  Scope is deliberately small: named events with a JSON `data:` payload,
//  which is the only shape the backend sends. No `id:`/Last-Event-ID replay,
//  no multi-line data frames beyond simple concatenation.
//

import Foundation

/// One decoded frame off the wire.
struct SSEMessage {
    /// The `event:` name. Defaults to "message" when the server omits it,
    /// matching the SSE spec.
    let event: String
    /// The accumulated `data:` lines, newline-joined.
    let data: String

    /// Decodes the payload as JSON. Returns nil rather than throwing: one
    /// malformed frame should drop that frame, not tear down the stream.
    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let raw = data.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: raw)
        } catch {
            #if DEBUG
            print("⚠️ SSE \(event): could not decode \(type) — \(error)")
            #endif
            return nil
        }
    }
}

/// An open SSE connection. Create it, read `onMessage`, and call `close()`
/// when the screen goes away — the connection stays open until you do.
///
/// Callbacks are delivered on the main queue, so they can drive SwiftUI state
/// directly.
final class EventSource: NSObject {

    // MARK: Configuration

    /// How long to wait before re-opening after the connection drops. Doubles
    /// on each consecutive failure, so a backend that's down doesn't get
    /// hammered, and resets as soon as one connect succeeds.
    private static let baseRetryDelay: TimeInterval = 2
    private static let maxRetryDelay: TimeInterval = 30

    // MARK: Callbacks

    var onMessage: ((SSEMessage) -> Void)?
    var onOpen: (() -> Void)?
    /// Called when the connection drops. `willRetry` is false once the caller
    /// has closed the stream, or the server ended it deliberately.
    var onError: ((Error?, _ willRetry: Bool) -> Void)?

    // MARK: State

    private let url: URL
    private var session: URLSession?
    private var task: URLSessionDataTask?

    /// Bytes that arrived without a frame terminator yet — SSE frames can be
    /// split across packets, so a partial line is normal.
    private var buffer = ""

    private var isClosed = false
    private var retryDelay = EventSource.baseRetryDelay
    private var retryWorkItem: DispatchWorkItem?

    // MARK: Lifecycle

    init(url: URL) {
        self.url = url
        super.init()
    }

    deinit {
        // Without this a screen that forgets to close leaks an open socket and
        // keeps waking the app up.
        close()
    }

    func connect() {
        guard !isClosed, task == nil else { return }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // The stream must never be killed by the request timeout — that's the
        // point of it. Only the resource timeout is left unbounded too.
        request.timeoutInterval = .infinity

        if let token = TokenManager.shared.accessToken ?? UserModel.shared.user?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(UserModel.shared.languageCode, forHTTPHeaderField: "Language-Code")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.timeoutIntervalForResource = .infinity
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.dataTask(with: request)
        self.task = task
        task.resume()

        #if DEBUG
        SSELogger.connecting(url)
        #endif
    }

    /// Ends the stream for good. Safe to call more than once, and safe to call
    /// from `deinit`.
    func close() {
        #if DEBUG
        // Only worth a line if there was something open to close — `deinit`
        // calls this on streams that were never connected.
        if task != nil { SSELogger.closed(url) }
        #endif

        isClosed = true
        retryWorkItem?.cancel()
        retryWorkItem = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        buffer = ""
    }

    // MARK: Reconnection

    private func scheduleReconnect(after error: Error?) {
        guard !isClosed else {
            deliverError(error, willRetry: false)
            return
        }

        task = nil
        session?.invalidateAndCancel()
        session = nil

        deliverError(error, willRetry: true)

        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.maxRetryDelay)

        let work = DispatchWorkItem { [weak self] in self?.connect() }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)

        #if DEBUG
        SSELogger.dropped(url, error: error, retryIn: delay)
        #endif
    }

    private func deliverError(_ error: Error?, willRetry: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error, willRetry)
        }
    }

    // MARK: Parsing

    /// Frames are separated by a blank line. Anything after the last blank line
    /// is an incomplete frame and stays in the buffer.
    private func consume(_ text: String) {
        buffer += text

        // Normalise line endings first so the frame split doesn't depend on
        // which the server used.
        buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        while let range = buffer.range(of: "\n\n") {
            let frame = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            if let message = Self.parseFrame(frame) {
                #if DEBUG
                SSELogger.event(url, name: message.event, data: message.data)
                #endif
                DispatchQueue.main.async { [weak self] in
                    self?.onMessage?(message)
                }
            }
        }
    }

    private static func parseFrame(_ frame: String) -> SSEMessage? {
        var event = "message"
        var dataLines: [String] = []

        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            // A leading colon is a comment — servers send these as keep-alives.
            if line.hasPrefix(":") { continue }

            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = String(line[line.startIndex..<colon])
            // One optional space after the colon is part of the framing, not
            // the value.
            var value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }

            switch field {
            case "event": event = value
            case "data":  dataLines.append(value)
            default:      break   // id / retry — unused here
            }
        }

        guard !dataLines.isEmpty else { return nil }
        return SSEMessage(event: event, data: dataLines.joined(separator: "\n"))
    }
}

// MARK: - URLSessionDataDelegate

extension EventSource: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }

        guard (200..<300).contains(http.statusCode) else {
            // An auth failure or a 404 will fail again on retry, but the retry
            // backs off, and letting it retry covers a token that refreshes
            // moments later.
            completionHandler(.cancel)
            scheduleReconnect(after: NSError(
                domain: "EventSource",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "SSE HTTP \(http.statusCode)"]
            ))
            return
        }

        // A successful connect clears the backoff.
        retryDelay = Self.baseRetryDelay
        completionHandler(.allow)

        #if DEBUG
        SSELogger.opened(url, status: http.statusCode)
        #endif

        DispatchQueue.main.async { [weak self] in self?.onOpen?() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        consume(text)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A cancel from `close()` is expected and not worth reconnecting over.
        if let error = error as NSError?, error.code == NSURLErrorCancelled, isClosed { return }
        scheduleReconnect(after: error)
    }
}
