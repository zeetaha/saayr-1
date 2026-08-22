//
//  BossLiveFeedDebug.swift
//  SAAYR
//
//  TEMPORARY. Holds the boss live-feed stream open for as long as the app is
//  running, so the SSE log can be watched without standing on the battle
//  screen. Nothing in the product depends on it.
//
//  To turn it off: `BossLiveFeedDebug.isEnabled = false`, or delete this file
//  and the two `#if DEBUG` call sites that reference it (`SAAYRApp.onAppear`
//  and `BossBattleModel.stop()`).
//

#if DEBUG
import Foundation

enum BossLiveFeedDebug {

    /// Master switch for the whole thing.
    static var isEnabled = true

    /// Which boss to watch when the home banner hasn't named one — the
    /// playground uses id 1, so that's the default.
    static var fallbackBossID = 1

    /// Held for the process lifetime on purpose: this is the "do not close"
    /// part. Reconnection is `EventSource`'s own backoff, so a boss that
    /// hasn't started yet will keep being retried until it does.
    private static var stream: EventSource?
    private static var openBossID: Int?

    /// Opens the stream if it isn't already open. Safe to call repeatedly.
    ///
    /// Asks the home banner for the live boss first so the feed is pointed at
    /// something real; falls back to `fallbackBossID` when there's no boss
    /// running, since a stream against a quiet id still proves the connection
    /// and the logging work.
    static func start() {
        guard isEnabled, stream == nil else { return }

        BossAPI.shared.fetchHomeBanner { banner in
            let bossID = banner?.boss_id ?? fallbackBossID
            open(bossID: bossID)
        }
    }

    private static func open(bossID: Int) {
        guard stream == nil, let source = BossAPI.shared.liveFeedStream(bossID: bossID) else { return }

        openBossID = bossID
        stream = source

        source.onOpen = {
            print("🧪 DEBUG live-feed held open for boss \(bossID) — it will not be closed")
        }
        // Frames are already printed by SSELogger; nothing is consumed here.
        source.onMessage = { _ in }
        source.onError = { _, _ in }

        source.connect()
    }

    /// True while the debug stream is the one watching `bossID` — the battle
    /// screen uses this to leave its own stream open too.
    static func holdsStream(for bossID: Int) -> Bool {
        isEnabled && openBossID == bossID
    }

    /// Escape hatch, since nothing else will ever close it.
    static func stop() {
        stream?.close()
        stream = nil
        openBossID = nil
        print("🧪 DEBUG live-feed released")
    }
}
#endif
