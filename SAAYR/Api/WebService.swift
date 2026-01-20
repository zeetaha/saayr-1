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
   
    
//#if DEBUG
//    static var cardKey = "pk_sbox_nzv4ul6fifmkfwnx62gxrydiaqe"
//    static var baseUrl = "http://100.27.214.146:8003/"
//#else
//    static var cardKey = "pk_sbox_nzv4ul6fifmkfwnx62gxrydiaqe"
//    static var baseUrl = "https://lechefapi.orderupp.io/"
//#endif
    
    
    static var cvvToken = ""
    
}
