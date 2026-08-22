//
//  AppRouter.swift
//  SAAYR
//
//  Which tab is showing, held above the tab bar so a screen presented over it
//  can send the player somewhere else.
//
//  Only one thing needs this today: checking in has to happen on the map,
//  where the dwell verification and anti-cheat pipeline live. Anywhere else
//  that offers a check-in is offering a shortcut past them, so it routes here
//  instead of calling the endpoint itself.
//

import SwiftUI
import Combine

final class AppRouter: ObservableObject {

    /// Matches the `.tag` values in `ContentView`.
    enum Tab: Int {
        case home = 0
        case challenges = 1
        case map = 2
        case rewards = 3
        case profile = 4
    }

    @Published var selectedTab: Int = Tab.home.rawValue

    func show(_ tab: Tab) {
        selectedTab = tab.rawValue
    }

    /// Sends the player to the map to check in. Named for the intent rather
    /// than the tab, so call sites read as what they mean.
    func goToMapForCheckIn() {
        show(.map)
    }
}
