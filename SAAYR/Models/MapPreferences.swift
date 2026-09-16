//
//  MapPreferences.swift
//  SAAYR
//
//  What the player has chosen to see on the map. Stored rather than derived,
//  so a preference survives a relaunch, and kept here rather than in either
//  screen because the toggle lives in Settings and the effect lives on the
//  map.
//

import Foundation

enum MapPreferences {

    /// Whether landmarks the player has already found stay pinned.
    ///
    /// Defaults to on. A player with three discoveries wants to see them —
    /// that's the progress. It only becomes clutter once the count is large,
    /// and when that happens is their judgement, not ours.
    static let showsDiscoveredLandmarksKey = "map.showsDiscoveredLandmarks"

    /// `@AppStorage` reads a missing key as `false`, which would hide the pins
    /// for everyone who has never opened the setting. Writing the default once
    /// means the stored value and the intended default agree.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [showsDiscoveredLandmarksKey: true])
    }
}
