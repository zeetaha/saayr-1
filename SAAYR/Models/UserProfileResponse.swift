//
//  UserProfileResponse.swift
//  SAAYR
//
//  Created by Awais Raza on 20/01/2026.
//


struct UserProfileResponse: Decodable {
    let id: Int
    let fullName: String?
    let falconName: String?
    let email: String?
    let avatar: String?
    let city: String?
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
    let total_points: Int
    let total_checkins: Int
    let pet_stage: Int
    let xp_to_next_level: Int
    let pvp_wins: Int
    let pvp_enabled: Bool
    let pvp_message: String
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
    let total: Int?
}

struct MyMatchResponse: Decodable {
    let success: Bool
    let message: String?
    let data: MyMatchData?
}

struct MyMatchData: Decodable {
    let match_id: Int
    let status: String
    let result: String
}

// MARK: - PVP Info

struct PVPInfoResponse: Decodable {
    let entry_fee: PVPEntryFee
    let rewards: [PVPReward]
}

struct PVPEntryFee: Decodable {
    let amount_sar: Int
    let first_match_free: Bool
    let free_matches_per_day: Int
}

struct PVPReward: Decodable {
    let type: String
    let xp: Int?
    let message: String
}

// MARK: - PVP Match Flow

struct MatchmakeAPIResponse: Decodable {
    let success: Bool?
    let message: String?
    let data: MatchmakeData?
}

struct MatchmakeData: Decodable {
    let payment_id: String
}

struct FullMatchResponse: Decodable {
    let success: Bool
    let message: String?
    let data: FullMatchData?
}

struct FullMatchData: Decodable {
    let match_id: Int
    let status: String         // "waiting", "matched", "in_progress", "completed", "cancelled", "voided"
    let result: String
    let i_won: Bool
    let winner_xp: Int
    let my: MatchParticipant
    let opponent: MatchParticipant?
    let missions: [MatchMission]
    let my_progress: [String: Int]
    let opponent_progress: [String: Int]
    let activity_log: [String]
    let entry_fee: Int?
    let started_at: String?
    let completed_at: String?
}

struct MatchParticipant: Decodable {
    let user_id: Int
    let falcon_name: String
    let full_name: String?
}

struct MatchMission: Decodable {
    let id: String
    let icon: String
    let label: String
    let target: Int
}
