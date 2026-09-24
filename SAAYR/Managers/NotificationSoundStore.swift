//
//  NotificationSoundStore.swift
//  SAAYR
//
//  Keeps the admin-managed push sounds on the phone, so a notification can
//  play its own sound instead of the default chime.
//
//  iOS only plays a push's `aps.sound` from the app bundle or from
//  Library/Sounds, and only in a format it can decode there — CAF/WAV/AIFF,
//  not MP3, at most 30 seconds. The backend hosts MP3s, so each one is
//  downloaded, converted to 16-bit PCM CAF and saved as
//  `Library/Sounds/<name>.caf`. A push then names it with
//  `"aps": { "sound": "checkin.caf" }`, and iOS plays it whether the app is
//  open, in the background or not running. A name with no file on the phone
//  falls back to the default sound.
//
//  Each file is fetched with its ETag, so a sound an admin replaces is picked
//  up on the next launch and an unchanged one costs a 304.
//

import AVFoundation
import os

enum NotificationSoundStore {

    /// Every sound the backend's templates can name. The list the admin panel
    /// shows comes from an admin-only endpoint the app can't call, so it's
    /// mirrored here — add a name when the backend adds a sound.
    static let names = [
        "checkin",
        "level_up",
        "pvp_match_start",
        "pvp_win",
        "pvp_loss",
        "boss_scheduled",
        "boss_live",
        "boss_victory",
        "boss_defeat",
        "weekly_reset",
        "dethroned",
    ]

    static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.saayr.app",
        category: "NotificationSounds"
    )

    /// Longest sound iOS will play for a notification; longer ones are
    /// silently replaced with the default, so they aren't installed.
    private static let maxDuration: Double = 30

    private static let queue = DispatchQueue(label: "NotificationSoundStore", qos: .utility)
    private static var isSyncing = false

    /// Library/Sounds — the one writable folder iOS looks in for push sounds.
    static var soundsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// The file name a push's `aps.sound` must use for `name`.
    static func fileName(for name: String) -> String { "\(name).caf" }

    /// Downloads any sound that is missing or has changed on the server.
    /// Safe to call on every launch; overlapping calls are dropped.
    static func sync() {
        queue.async {
            guard !isSyncing else { return }
            isSyncing = true

            do {
                try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
            } catch {
                log.error("Can't create Library/Sounds: \(error.localizedDescription, privacy: .public)")
                isSyncing = false
                return
            }

            let group = DispatchGroup()
            for name in names {
                group.enter()
                fetch(name) { group.leave() }
            }
            group.notify(queue: queue) { isSyncing = false }
        }
    }

    // MARK: - Download

    private static func remoteURL(for name: String) -> URL? {
        URL(string: WebService.domainUrl + "/uploads/notification_sounds/\(name).mp3")
    }

    private static func etagKey(for name: String) -> String { "notificationSound.etag.\(name)" }

    private static func fetch(_ name: String, completion: @escaping () -> Void) {
        guard let url = remoteURL(for: name) else { completion(); return }

        let destination = soundsDirectory.appendingPathComponent(fileName(for: name))
        let installed = FileManager.default.fileExists(atPath: destination.path)

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        // Only worth asking "has it changed?" when there's a file to keep.
        if installed, let etag = UserDefaults.standard.string(forKey: etagKey(for: name)) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        URLSession.shared.downloadTask(with: request) { tempURL, response, error in
            defer { completion() }

            if let error {
                log.error("\(name, privacy: .public): download failed — \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let http = response as? HTTPURLResponse else { return }

            switch http.statusCode {
            case 304:
                log.debug("\(name, privacy: .public): unchanged")
            case 200:
                guard let tempURL else { return }
                do {
                    try install(tempURL, as: destination)
                    let etag = http.value(forHTTPHeaderField: "ETag")
                    UserDefaults.standard.set(etag, forKey: etagKey(for: name))
                    log.log("\(name, privacy: .public): installed as \(destination.lastPathComponent, privacy: .public)")
                } catch {
                    log.error("\(name, privacy: .public): not installed — \(error.localizedDescription, privacy: .public)")
                }
            default:
                // 404 = the backend has no file for this name yet. Any file
                // already installed stays, so the sound keeps working.
                log.error("\(name, privacy: .public): HTTP \(http.statusCode)")
            }
        }.resume()
    }

    // MARK: - Convert

    enum InstallError: LocalizedError {
        case tooLong(Double)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .tooLong(let seconds):
                return String(format: "%.1f s is over the 30 s iOS allows for a notification sound", seconds)
            case .unreadable:
                return "not a readable audio file"
            }
        }
    }

    /// Decodes whatever the server sent (MP3 today) and writes it as 16-bit
    /// PCM CAF, which iOS plays for notifications. Written beside the target
    /// and then swapped in, so a push arriving mid-write never finds half a
    /// file.
    static func install(_ source: URL, as destination: URL) throws {
        // AVAudioFile picks the decoder from the extension, and the download
        // lands as .tmp — give it the real one first.
        let typed = source.deletingPathExtension().appendingPathExtension("mp3")
        try? FileManager.default.removeItem(at: typed)
        try FileManager.default.moveItem(at: source, to: typed)
        defer { try? FileManager.default.removeItem(at: typed) }

        let input = try AVAudioFile(forReading: typed)
        let format = input.processingFormat
        guard input.length > 0, format.sampleRate > 0 else { throw InstallError.unreadable }

        let seconds = Double(input.length) / format.sampleRate
        guard seconds <= maxDuration else { throw InstallError.tooLong(seconds) }

        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).partial")
        try? FileManager.default.removeItem(at: staging)

        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            // Scoped so the output file is closed — and fully written — before
            // it's moved into place.
            do {
                let output = try AVAudioFile(
                    forWriting: staging,
                    settings: settings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
                    throw InstallError.unreadable
                }
                while input.framePosition < input.length {
                    try input.read(into: buffer)
                    if buffer.frameLength == 0 { break }
                    try output.write(from: buffer)
                }
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}
