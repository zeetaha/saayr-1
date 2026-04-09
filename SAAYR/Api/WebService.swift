//
//  WebService.swift
//  lechef
//
//  Created by Awais Raza on 29/09/2024.
//

import Foundation

class WebService {
    
//    static var baseUrl = "http://100.27.214.146:8001/"
    

    static var baseUrl = "https://api.saayr.sa/api/v1/"

    static var sendOtp = baseUrl + "auth/send-otp"
    static var verifyOtp = baseUrl + "auth/verify-otp"
    static var completeSignup = baseUrl + "auth/complete-signup"
    static var addFalconName = baseUrl + "auth/add-falcon-name"
    static var login = baseUrl + "auth/login"
    static var forgotPasscode = baseUrl + "auth/forgot-passcode"
    static var resetPasscode = baseUrl + "auth/reset-passcode"
    static var nearBy = baseUrl + "locations/nearby"
    static var checkIn = baseUrl + "locations/check-in"
    static var profile = baseUrl + "user/profile"
    static var dashboard  = baseUrl + "user/dashboard"
    static var leaderboard = baseUrl + "user/leaderboard"
    static var updateProfile = baseUrl + "user/profile"
    static var deleteAccount = baseUrl + "user/account"
    static var createTicket = baseUrl + "tickets/create"
    static var uploadImage = baseUrl + "tickets/upload-image"
    static var myTickets = baseUrl + "tickets/my-tickets"
    static var pvpPaymentWebview = baseUrl + "user/pvp/payment-webview"
    static var rewardsCatalog = baseUrl + "rewards/catalog"
    static var redeemReward = baseUrl + "rewards/redeem"
    static var myMatch = baseUrl + "user/pvp/my-match"
    static var pvpInfo = baseUrl + "user/pvp/info"
    static var pvpMatchmake = baseUrl + "user/pvp/payment/" // append: {paymentId}/matchmake
    static var pvpMatchState = baseUrl + "user/pvp/match/" // append: {matchId}/state
    static var pvpCancelMatch = baseUrl + "user/pvp/match/cancel"
    static var challenges = baseUrl + "missions/challenges"
   
    
//#if DEBUG
//    static var cardKey = "pk_sbox_nzv4ul6fifmkfwnx62gxrydiaqe"
//    static var baseUrl = "http://100.27.214.146:8003/"
//#else
//    static var cardKey = "pk_sbox_nzv4ul6fifmkfwnx62gxrydiaqe"
//    static var baseUrl = "https://lechefapi.orderupp.io/"
//#endif
    
    
    static var cvvToken = ""
    static var moyasarPublishableKey = "pk_test_zh19C8QcQyT2n4mu9kVHtzR9aFhotACBbs7XJcN2"
    //MOYASAR_SECRET_KEY=sk_test_XPLmF2jZDZogqnTePhXpzbZPLB9PNUYDroD67nW4"
    static var applePayMerchantId = "merchant.com.saayr.app"

}
