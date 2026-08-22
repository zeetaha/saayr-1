//
//  BossZoneStore.swift
//  SAAYR
//
//  The boss zones live here rather than on either screen because two screens
//  disagree about who owns them: the home banner decides *whether* there are
//  any, and the map is what draws them. One shared object lets the banner's
//  appearance and disappearance drive the overlay without the map having to
//  know anything about bosses.
//

import Foundation
import Combine

@MainActor
final class BossZoneStore: ObservableObject {

    static let shared = BossZoneStore()
    private init() {}

    /// Empty whenever no boss is being advertised, which is what removes the
    /// overlay from the map.
    @Published private(set) var zones: [BossZone] = []

    /// The boss the loaded zones belong to, so a second banner read for the
    /// same boss doesn't refetch.
    private var loadedBossID: Int?
    private var isLoading = false

    /// Called every time the home banner is re-read. `banner` is exactly what
    /// the home screen renders on: a boss that is live or scheduled, or nil.
    func update(for banner: BossHomeBanner?) {
        guard let banner, !banner.isEmpty, let bossID = banner.boss_id else {
            clear()
            return
        }

        guard loadedBossID != bossID, !isLoading else { return }
        isLoading = true

        BossAPI.shared.fetchZones { [weak self] zones in
            guard let self else { return }
            self.isLoading = false
            self.loadedBossID = bossID
            self.zones = zones
        }
    }

    private func clear() {
        loadedBossID = nil
        guard !zones.isEmpty else { return }
        zones = []
    }
}
