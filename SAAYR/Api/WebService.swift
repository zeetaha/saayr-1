//
//  WebService.swift
//  lechef
//
//  Created by Awais Raza on 29/09/2024.
//

import Foundation

class WebService {

    // MARK: - Base URLs
    // To switch environments, select the "Staging" scheme in Xcode.
    // That scheme uses the "Staging" build configuration which defines
    // the STAGING Swift Active Compilation Condition.

    #if STAGING
    static let baseUrl   = "https://api-staging.saayr.sa/api/v1/"
    static let portalUrl = "https://portal-staging.saayr.sa/"
    static let domainUrl = "https://api-staging.saayr.sa"
    #else
    static let baseUrl   = "https://api.saayr.sa/api/v1/"
    static let portalUrl = "https://portal.saayr.sa/"
    static let domainUrl = "https://api.saayr.sa"
    #endif

    /// Resolves a relative image path (e.g. "/api/v1/locations/images/x.png")
    /// to a full URL. Absolute URLs are returned unchanged.
    static func resolvedImageUrl(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return path }
        return domainUrl + path
    }

    // MARK: - Auth
    static var sendOtp         = baseUrl + "auth/send-otp"
    static var verifyOtp       = baseUrl + "auth/verify-otp"
    static var completeSignup  = baseUrl + "auth/complete-signup"
    static var addFalconName   = baseUrl + "auth/add-falcon-name"
    static var login           = baseUrl + "auth/login"
    static var forgotPasscode  = baseUrl + "auth/forgot-passcode"
    static var resetPasscode   = baseUrl + "auth/reset-passcode"
    static var authRefresh     = baseUrl + "auth/refresh"
    static var authLogout      = baseUrl + "auth/logout"

    // MARK: - Locations
    static var nearBy  = baseUrl + "locations/nearby"
    static var checkIn = baseUrl + "locations/check-in"

    // MARK: - Zones (Fog of War)
    static var zones           = baseUrl + "zones/"
    static var zonesMyExplored = baseUrl + "zones/my-explored"

    // MARK: - Landmark discovery
    /// Records that the player physically reached a landmark. Not live yet —
    /// `LandmarkDiscoveryService` treats a failure here as "sync later", so
    /// discoveries survive locally until the endpoint answers.
    static var landmarkDiscover    = baseUrl + "landmarks/discover"
    /// Everything this player has already revealed, for a fresh install or a
    /// second device.
    static var landmarkDiscoveries = baseUrl + "landmarks/my-discoveries"

    // MARK: - Boss event
    /// Poster state for the home screen.
    static var bossHomeBanner = baseUrl + "boss/home-banner"
    /// Areas the current boss is fought in. Not per-boss: the server answers
    /// for whichever boss is live or scheduled, so it's only worth calling
    /// while the home banner is showing one.
    static var bossZones = baseUrl + "boss/zones"
    /// Everything below is per-boss. The battle and waitlist screens each pair
    /// one REST call with an SSE stream; the REST call hydrates, the stream
    /// keeps it current. Do not poll the REST endpoints.
    static func bossBattleState(_ bossID: Int) -> String { baseUrl + "boss/\(bossID)/battle-state" }
    static func bossLiveFeed(_ bossID: Int) -> String { baseUrl + "boss/\(bossID)/live-feed" }
    static func bossWaitlist(_ bossID: Int) -> String { baseUrl + "boss/\(bossID)/waitlist" }
    static func bossWaitlistStream(_ bossID: Int) -> String { baseUrl + "boss/\(bossID)/waitlist/stream" }
    static func bossRewards(_ bossID: Int) -> String { baseUrl + "boss/\(bossID)/rewards" }
    /// Acknowledges the reward and drops the ended boss out of the challenges
    /// payload. Idempotent — claiming twice is not an error.
    static func bossClaimRewards(_ bossID: Int) -> String { baseUrl + "boss/\(bossID)/rewards/claim" }

    // MARK: - User
    static var profile       = baseUrl + "user/profile"
    static var dashboard     = baseUrl + "user/dashboard"
    static var leaderboard   = baseUrl + "user/leaderboard"
    static var updateProfile = baseUrl + "user/profile"
    static var deleteAccount = baseUrl + "user/account"
    static var updateFcmToken = baseUrl + "user/fcm-token"

    // MARK: - Support Tickets
    static var supportUnreadCount = baseUrl + "tickets/my-tickets/unread-count"
    static var createTicket       = baseUrl + "tickets/create"
    static var uploadImage        = baseUrl + "tickets/upload-image"
    static var myTickets          = baseUrl + "tickets/my-tickets"

    // MARK: - PVP
    static var pvpPaymentWebview = baseUrl + "user/pvp/payment-webview"
    static var myMatch           = baseUrl + "user/pvp/my-match"
    static var pvpInfo           = baseUrl + "user/pvp/info"
    static var pvpMatchmake      = baseUrl + "user/pvp/payment/"   // append: {paymentId}/matchmake
    static var pvpMatchState     = baseUrl + "user/pvp/match/"     // append: {matchId}/state
    static var pvpCancelMatch    = baseUrl + "user/pvp/match/cancel"

    // MARK: - Rewards
    static var rewardsCatalog = baseUrl + "rewards/catalog"
    static var redeemReward   = baseUrl + "rewards/redeem"
    static var myRedemptions  = baseUrl + "rewards/my-redemptions"
    static var weeklyTop3     = baseUrl + "user/weekly-top3"

    // MARK: - Anti-Cheat
//    static var verifyCheckin = baseUrl + "locations/verify-checkin"
//    static var fraudReport   = baseUrl + "anticheat/fraud-report"
//    static var thresholds    = baseUrl + "anticheat/thresholds"

    // MARK: - Challenges & Health
    static var challenges   = baseUrl + "missions/challenges"
    static var recordSteps  = baseUrl + "record-steps"

    // MARK: - Payment keys
    static var cvvToken = ""
    static var moyasarPublishableKey = "pk_test_zh19C8QcQyT2n4mu9kVHtzR9aFhotACBbs7XJcN2"
    static var applePayMerchantId    = "merchant.com.saayr.app"

    // MARK: - Weather
    // Get a free key at https://openweathermap.org/api → Current Weather Data
    static let openWeatherApiKey = "069f0cb00b2de3bc3beecd5deba612e0"

    // MARK: - Mapbox
    /// The published Saayr style from Mapbox Studio, as `mapbox://styles/saayr/<style-id>`.
    /// Copy it from Studio → the style's ••• menu → Share → Style URL.
    /// Leave empty to fall back to Mapbox's built-in Standard style.
    static let mapboxStyleURL = "mapbox://styles/saayr/cmqmxez25000h01r25rvpdslf"

    // MARK: - Convenience
    /// Which environment is active — useful for debug banners or logging.
    static var environmentName: String {
        #if STAGING
        return "Staging"
        #else
        return "Production"
        #endif
    }
}
