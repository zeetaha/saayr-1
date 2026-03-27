import Foundation

struct UserData: Codable {
    var fullName: String?
    var email: String?
    var phoneNumber: String?
    var petName: String?
    var petType: String?
    var totalXP: Int
    var checkInStreak: Int
    var pvpWins: Int
    var checkInLogs: [CheckInLog]
    var city: String?       // <-- add this
    var transactions: [Transaction]
    var achievements: [Achievement]
    var groups: [String] // Group IDs
    
    var pvp_enabled : Bool = false
    var pvp_message : String = ""
    
    var level: Int {
        LevelSystem.getLevelFromXP(totalXP)
    }
    
    var points: Int {
        LevelSystem.calculatePointsFromXP(totalXP)
    }
    
    var petStage: PetStage {
        LevelSystem.getPetStage(level)
    }
    
    var xpProgress: XPProgress {
        LevelSystem.getXPProgressToNextLevel(totalXP)
    }
    
    var totalSpent: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }
}

struct CheckInLog: Codable, Identifiable {
    let id: String
    let location: String
    let timestamp: Date
    let xpAwarded: Int
}

struct Transaction: Codable, Identifiable {
    let id: String
    let merchantName: String
    let amount: Double
    let currency: String
    let category: String
    let timestamp: Date
    let xpAwarded: Int
    var pointsAwarded: Int
    let isPartner: Bool
    let multiplier: Int
}

struct Achievement: Codable, Identifiable {
    let id: String
    let category: AchievementCategory
    let title: String
    let titleAr: String
    let description: String
    let descriptionAr: String
    let pointsReward: Int
    let requirement: Int
    var currentProgress: Int
    var isUnlocked: Bool
    let icon: String
}

enum AchievementCategory: String, Codable {
    case checkIn = "check-in"
    case spending = "spending"
    case level = "level"
    case social = "social"
    case pvp = "pvp"
    case streak = "streak"
    case challenges = "challenges"
    case rewards = "rewards"
}

struct XPProgress {
    let currentLevelXP: Int
    let nextLevelXP: Int
    let progressPercentage: Double
}

enum PetStage: String, Codable {
    case egg = "egg"
    case hatchling = "hatchling"
    case juvenile = "juvenile"
    case adult = "adult"
    case legendary = "legendary"
    
    var stageNumber: Int {
        switch self {
        case .egg: return 1
        case .hatchling: return 2
        case .juvenile: return 3
        case .adult: return 4
        case .legendary: return 5
        }
    }
    
    var emoji: String {
        switch self {
        case .egg: return "🥚"
        case .hatchling: return "🐣"
        case .juvenile: return "🦅"
        case .adult: return "🦅"
        case .legendary: return "👑"
        }
    }
    
    var gradientColors: [String] {
        switch self {
        case .egg:
            return ["#7BFCF3", "#276FCE"]
        case .hatchling:
            return ["#FFF9C4", "#FFF59D"]
        case .juvenile:
            return ["#B2DFDB", "#80CBC4"]
        case .adult:
            return ["#C5CAE9", "#9FA8DA"]
        case .legendary:
            return ["#FFCCBC", "#FFAB91"]
        }
    }
}

extension UserData {
    static func fromProfile(_ profile: UserProfileResponse) -> UserData {
        return UserData(
            fullName: profile.fullName,
            email: profile.email,
            phoneNumber: "", // API doesn't provide phone, default to empty
            petName: profile.falconName ?? "Falcon",
            petType: "Unknown", // Or map if API provides
            totalXP: profile.totalXP,
            checkInStreak: 0,
            pvpWins:0, // Default or map if API provides
            checkInLogs: [],
            city: profile.city,
            transactions: [],
            achievements: [],
            groups: []
        )
    }

    static func fromProfileAndDashboard(profile: UserProfileResponse, dashboard: DashboardResponse) -> UserData {
        return UserData(
            fullName: profile.fullName,
            email: profile.email,
            phoneNumber: "", // API doesn't provide phone, default to empty
            petName: profile.falconName ?? "Falcon",
            petType: "\(dashboard.total_points)",
            totalXP: dashboard.total_xp,
            checkInStreak: dashboard.total_checkins,
            pvpWins:dashboard.pvp_wins,
            checkInLogs: [],
            city: profile.city,
            transactions: [],
            achievements: [],
            groups: [],
            pvp_enabled: dashboard.pvp_enabled,
            pvp_message: dashboard.pvp_message
        )
    }
}

