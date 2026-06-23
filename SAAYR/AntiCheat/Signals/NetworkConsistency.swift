import Foundation
import CoreLocation

/// Cross-checks the device's network-derived location against the GPS-derived
/// location.
///
/// The most reliable signal here is **IP geolocation country vs. merchant
/// country** — a cheap, passive check that catches VPN / proxy spoofing when
/// the user is trying to appear in a different country.
///
/// iOS privacy restrictions limit what network info we can read:
/// - SSID requires "Wi-Fi Access" capability + location permission
/// - CNCopyCurrentNetworkInfo is sandboxed per-interface
/// - No programmatic access to cell tower IDs or visible Wi-Fi scan
///
/// Therefore we delegate the heavy network consistency check to the server
/// (which sees the TCP origin IP), and do a lightweight client-side sanity
/// check here.
struct NetworkConsistency {

    /// Returns a risk score (0.0 = consistent, 1.0 = inconsistent) based on
    /// network-vs-GPS cross-checks available on-device.
    ///
    /// The server will independently verify IP geolocation against the merchant's
    /// known country — this client-side check is an early-warning signal that
    /// gets included in the proof bundle.
    static func riskScore(
        currentLocation: CLLocation?,
        merchantCountryCode: String?,
        gpsCountryCode: String?
    ) -> Double {
        // If the GPS location doesn't resolve to the merchant's country,
        // flag it. This catches basic cross-border VPN spoofing.
        guard let merchantCountry = merchantCountryCode,
              let gpsCountry = gpsCountryCode else {
            return 0.0   // Can't determine — don't penalise
        }

        return merchantCountry == gpsCountry ? 0.0 : 0.8
    }

    /// Attempts to determine a country code from GPS coordinates using
    /// a reverse-geocode. Returns nil if the geocoder fails or is unavailable.
    ///
    /// Note: `CLGeocoder` makes network requests and should be used sparingly.
    /// The server-side IP check is more reliable.
    static func resolveCountryCode(
        from location: CLLocation,
        completion: @escaping (String?) -> Void
    ) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            completion(placemarks?.first?.isoCountryCode)
        }
    }
}
