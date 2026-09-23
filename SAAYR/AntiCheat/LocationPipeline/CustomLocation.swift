//
//  CustomLocation.swift
//  SAAYR
//
//  Lets one tester, picked by phone number, stand anywhere: while it's on,
//  `FilteredLocationManager` ignores the GPS and reports the chosen point
//  instead. Everyone else never sees it and can't switch it on.
//

import Foundation
import CoreLocation
import Combine

final class CustomLocation: ObservableObject {

    static let shared = CustomLocation()

    /// The only phone number allowed a custom location, with its country code
    /// (e.g. "966512345678"). Spaces, "+" and a leading 0 are ignored when
    /// matching. Empty means nobody has it.
    static let allowedPhone = "966522222222"

    @Published private(set) var isAllowed = false
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    @Published var coordinate: CLLocationCoordinate2D? {
        didSet {
            if let coordinate {
                defaults.set([coordinate.latitude, coordinate.longitude], forKey: Keys.coordinate)
            } else {
                defaults.removeObject(forKey: Keys.coordinate)
            }
        }
    }

    /// The point to report in place of the GPS, or nil to use the real one.
    var activeCoordinate: CLLocationCoordinate2D? {
        isAllowed && isEnabled ? coordinate : nil
    }

    /// Fires whenever `activeCoordinate` may have changed.
    var activeCoordinatePublisher: AnyPublisher<CLLocationCoordinate2D?, Never> {
        Publishers.CombineLatest3($isAllowed, $isEnabled, $coordinate)
            .map { allowed, enabled, coordinate in allowed && enabled ? coordinate : nil }
            .eraseToAnyPublisher()
    }

    private enum Keys {
        static let signedInPhone = "customLocation.signedInPhone"
        static let enabled = "customLocation.enabled"
        static let coordinate = "customLocation.coordinate"
        /// Written by `AuthManager.completeAuthentication`. Only read for
        /// installs signed in before this existed, which never recorded
        /// `signedInPhone`.
        static let legacyPhone = "phoneNumber"
    }

    private let defaults = UserDefaults.standard

    private init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        if let pair = defaults.array(forKey: Keys.coordinate) as? [Double], pair.count == 2 {
            coordinate = CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        let phone = defaults.string(forKey: Keys.signedInPhone)
            ?? defaults.string(forKey: Keys.legacyPhone)
        isAllowed = Self.matchesAllowed(phone)
    }

    /// Called once the server has accepted a login for `phone`.
    func signedIn(phone: String) {
        defaults.set(phone, forKey: Keys.signedInPhone)
        isAllowed = Self.matchesAllowed(phone)
        if !isAllowed { isEnabled = false }
    }

    /// Stored as empty, not removed, so the legacy fallback can't bring a
    /// previous account's phone back.
    func signedOut() {
        defaults.set("", forKey: Keys.signedInPhone)
        isAllowed = false
        isEnabled = false
    }

    private static func matchesAllowed(_ phone: String?) -> Bool {
        guard let phone else { return false }
        let allowed = normalized(allowedPhone)
        return !allowed.isEmpty && normalized(phone) == allowed
    }

    /// Digits only, without the Saudi country code or a trunk 0, so
    /// "+966 51 234 5678", "9660512345678" and "0512345678" all agree.
    private static func normalized(_ phone: String) -> String {
        var digits = phone.filter(\.isNumber)
        if digits.hasPrefix("966") { digits.removeFirst(3) }
        while digits.hasPrefix("0") { digits.removeFirst() }
        return digits
    }
}
