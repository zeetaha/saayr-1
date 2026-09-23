//
//  BossLiveFeedDebug.swift
//  SAAYR
//
//  TEMPORARY. Holds the boss live-feed stream open while a boss is live and
//  the app is in the foreground, so the SSE log can be watched without
//  standing on the battle screen. Nothing in the product depends on it.
//
//  To turn it off: `BossLiveFeedDebug.isEnabled = false`, or delete this file
//  and the `#if DEBUG` call sites that reference it (`SAAYRApp`).
//

#if DEBUG
import Foundation

enum BossLiveFeedDebug {

    /// Master switch for the whole thing.
    static var isEnabled = true

    /// Held while the app is in the foreground and a boss is live; `stop()`
    /// on backgrounding, `start()` again on return re-checks the banner.
    private static var stream: EventSource?

    /// Opens the stream if it isn't already open. Safe to call repeatedly.
    ///
    /// Only connects when the home banner says a boss is live — with no boss
    /// there's nothing to watch, and the socket would just sit open.
    static func start() {
        guard isEnabled, stream == nil else { return }

        BossAPI.shared.fetchHomeBanner { banner in
            guard let banner, banner.state == .live, let bossID = banner.boss_id else {
                print("🧪 DEBUG live-feed not opened — no live boss")
                return
            }
            open(bossID: bossID)
        }
    }

    private static func open(bossID: Int) {
        guard stream == nil, let source = BossAPI.shared.liveFeedStream(bossID: bossID) else { return }

        stream = source

        source.onOpen = {
            print("🧪 DEBUG live-feed held open for boss \(bossID)")
        }
        // Frames are already printed by SSELogger; nothing is consumed here.
        source.onMessage = { _ in }
        source.onError = { _, _ in }

        source.connect()
    }

    /// Called when the app leaves the foreground or the player logs out.
    static func stop() {
        guard stream != nil else { return }
        stream?.close()
        stream = nil
        print("🧪 DEBUG live-feed released")
    }
}
#endif
