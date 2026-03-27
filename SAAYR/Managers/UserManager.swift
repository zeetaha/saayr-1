import Foundation
import SwiftUI
import Combine

class UserManager: ObservableObject {
    @Published var activePVPSession = false
    @Published var activeMatchStatus: Bool = false
    
    // MARK: - Published properties
    @Published var leaderboardUsers: [LeaderboardUser] = []
        
        
    @Published var userData: UserData = UserData(
        fullName: "",
        email: "",
        phoneNumber: "",
        petName: "",
        petType: "",
        totalXP: 0,
        checkInStreak: 0, pvpWins: 0,
        checkInLogs: [],
        city: "",
        transactions: [],
        achievements: [],
        groups: []
    )

        private var cancellables = Set<AnyCancellable>()
        
//        // MARK: - Init
        init() {
          //  fetchAllUserData()
        }
        
    
    func updateLeaderboard(from entries: [LeaderboardEntry]) {
        let users: [LeaderboardUser] = entries.map { entry in
            LeaderboardUser(
                id: entry.user_id,          // stable ID
                name: entry.full_name ?? "Unknown",
                level: entry.level,
                points: entry.points,
                avatar: entry.avatar,
                bgColor: {
                    switch entry.rank {
                    case 1: return .yellow.opacity(0.5)
                    case 2: return .gray.opacity(0.5)
                    case 3: return .orange.opacity(0.5)
                    default: return .blue.opacity(0.3)
                    }
                }()
            )
        }
        DispatchQueue.main.async {
            self.leaderboardUsers = users
        }
    }

        // MARK: - API Fetching
    // MARK: - Fetch All User Data
    func fetchAllUserData() {
        // First, fetch profile
        fetchProfile { [weak self] profile in
            guard let self = self, let profile = profile else { return }

            // Update userData with profile info
            self.userData = UserData.fromProfile(profile)

            // Then fetch dashboard
            self.fetchDashboard { dashboard in
                guard let dashboard = dashboard else { return }

                // Merge dashboard info into userData
                self.userData = UserData.fromProfileAndDashboard(profile: profile, dashboard: dashboard)

            }
            
            self.fetchLeaderboard { leaderboardResponse in
                guard let leaderboardResponse = leaderboardResponse else { return }

                self.updateLeaderboard(from: leaderboardResponse.leaderboard)
            }

            self.fetchMyMatch()
        }
    }

    // MARK: - Fetch Profile
    func fetchProfile(completion: @escaping (UserProfileResponse?) -> Void) {
        ServiceModel.shared.getRequest(endpoint: WebService.profile) { result in
            switch result {
            case .success(let data):
                do {
                    let decoded = try JSONDecoder().decode(UserProfileResponse.self, from: data)
                    completion(decoded)
                } catch {
                    print("❌ Decoding error (profile):", error)
                    completion(nil)
                }
            case .failure(let error):
                print("❌ API error (profile):", error.localizedDescription)
                completion(nil)
            }
        }
    }

    // MARK: - Fetch Dashboard
    func fetchDashboard(completion: @escaping (DashboardResponse?) -> Void) {
        ServiceModel.shared.getRequest(endpoint: WebService.dashboard) { result in
            switch result {
            case .success(let data):
                do {
                    let decoded = try JSONDecoder().decode(DashboardResponse.self, from: data)
                    completion(decoded)
                } catch {
                    print("❌ Decoding error (dashboard):", error)
                    completion(nil)
                }
            case .failure(let error):
                print("❌ API error (dashboard):", error.localizedDescription)
                completion(nil)
            }
        }
    }

    // MARK: - Fetch My PVP Match
    func fetchMyMatch() {
        ServiceModel.shared.getRequest(endpoint: WebService.myMatch) { [weak self] result in
            switch result {
            case .success(let data):
                do {
                    let decoded = try JSONDecoder().decode(MyMatchResponse.self, from: data)
                    DispatchQueue.main.async {
                        if decoded.success && decoded.data?.status == "in_progress" {
                            self?.activeMatchStatus = true
                        } else {
                            self?.activeMatchStatus = false
                        }
                    }
                } catch {
                    print("❌ Decoding error (my-match):", error)
                }
            case .failure(let error):
                print("❌ API error (my-match):", error.localizedDescription)
            }
        }
    }

    // MARK: - Fetch Leaderboard
    func fetchLeaderboard(completion: @escaping (LeaderboardResponse?) -> Void) {
        // Make sure city exists
        

        let params: [String: Any] = [
            "city": "Riyadh",
            "page": 1,
            "limit": 5
        ]

        ServiceModel.shared.getRequest(endpoint: WebService.leaderboard, parameters: params) { result in
            switch result {
            case .success(let data):
                do {
                    let decoded = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
                    completion(decoded)
                } catch {
                    print("❌ Decoding error (leaderboard):", error)
                    completion(nil)
                }
            case .failure(let error):
                print("❌ API error (leaderboard):", error.localizedDescription)
                completion(nil)
            }
        }
    }

        
        // MARK: - XP & Level Logic
        func addXP(_ amount: Int, reason: String) {
            let oldLevel = userData.level
            userData.totalXP += amount
            let newLevel = userData.level
            
            if newLevel > oldLevel {
                // Level up & evolution check
                let oldStage = LevelSystem.getPetStage(oldLevel)
                let newStage = userData.petStage
                
                if oldStage != newStage {
                    let rewardPoints = LevelSystem.getEvolutionRewardPoints(newStage)
                    userData.totalXP += rewardPoints * 100
                }
            }
        }
        
        // MARK: - Transactions
        func addTransaction(merchantName: String, amount: Double, category: String, isPartner: Bool, multiplier: Int = 1) {
            let xpAwarded = LevelSystem.calculateXPFromSpending(amount, multiplier: multiplier)
            let oldPoints = userData.points
            
            let transaction = Transaction(
                id: UUID().uuidString,
                merchantName: merchantName,
                amount: amount,
                currency: "SAR",
                category: category,
                timestamp: Date(),
                xpAwarded: xpAwarded,
                pointsAwarded: 0,
                isPartner: isPartner,
                multiplier: multiplier
            )
            
            userData.transactions.insert(transaction, at: 0)
            addXP(xpAwarded, reason: "Transaction at \(merchantName)")
            
            let pointsAwarded = userData.points - oldPoints
            if pointsAwarded > 0, let index = userData.transactions.firstIndex(where: { $0.id == transaction.id }) {
                var updated = userData.transactions[index]
                updated.pointsAwarded = pointsAwarded
                userData.transactions[index] = updated
            }
        }
        
        // MARK: - Check-in
        func checkIn(at location: String) {
            let xpAwarded = LevelSystem.checkInRegular
            let checkIn = CheckInLog(
                id: UUID().uuidString,
                location: location,
                timestamp: Date(),
                xpAwarded: xpAwarded
            )
            userData.checkInLogs.insert(checkIn, at: 0)
            userData.checkInStreak += 1
            addXP(xpAwarded, reason: "Check-in at \(location)")
        }
        
        // MARK: - PVP
        func startPVPSession() { activePVPSession = true }
        func completePVPSession(won: Bool) {
            activePVPSession = false
            if won { addXP(LevelSystem.pvpWin, reason: "PVP Victory") }
        }
        
        // MARK: - UI Helpers
        var stageColor: Color {
            let stage = LevelSystem.getPetStage(userData.level)
            let colors = LevelSystem.getStageGradientColors(stage)
            return colors.start
        }

}


extension UserData {
    static func fromAPI(profile: UserProfileResponse, dashboard: DashboardResponse) -> UserData {
        UserData(
            fullName: profile.fullName,
            email: profile.email,
            phoneNumber: "", // API doesn't provide
            petName: profile.falconName ?? "🐦",
            petType: "Bird",
            totalXP: dashboard.total_xp,
            checkInStreak: 0,
            pvpWins: 0,
            checkInLogs: [],
            city: "",
            transactions: [],
            achievements: [],
            groups: []
        )
    }
    
    var checkInCount: Int { checkInLogs.count }
}

