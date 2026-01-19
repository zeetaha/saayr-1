//
//  UserProfileResponse.swift
//  SAAYR
//
//  Created by Awais Raza on 20/01/2026.
//


struct UserProfileResponse: Decodable {
    let id: Int
    let fullName: String
    let falconName: String?
    let email: String
    let avatar: String?
    let city: String
    let currentLevel: Int
    let totalXP: Int
    let petStage: Int
    let referralCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case falconName = "falcon_name"
        case email
        case avatar
        case city
        case currentLevel = "current_level"
        case totalXP = "total_xp"
        case petStage = "pet_stage"
        case referralCode = "referral_code"
    }
}


struct DashboardResponse: Decodable {
    let user_level: Int
    let xp_progress: Int
    let total_xp: Int
    let total_checkins: Int
    let pet_stage: Int
    let xp_to_next_level: Int
}

struct LeaderboardEntry: Decodable, Identifiable {
    let id: Int?
    let rank: Int
    let user_id: Int
    let falcon_name: String?
    let full_name: String?
    let level: Int
    let points: Int
    let avatar: String?
}

struct LeaderboardResponse: Decodable {
    let city: String
    let my_rank: Int
    let my_points: Int
    let leaderboard: [LeaderboardEntry]
}
