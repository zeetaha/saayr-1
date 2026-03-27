import SwiftUI

struct RewardsView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager
    
    @State private var rewards: [APIReward] = []
    @State private var showRedeemDialog = false
    @State private var selectedReward: APIReward?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var redemptionData: RedemptionData?
    @State private var showSuccess = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "#F0F9FF"), Color.white, Color(hex: "#FFF7ED")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Text(languageManager.text("rewards.title"))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Color(hex: "#FF8C00"))
                        
                        // XP Balance Card
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color(hex: "#FFA500"), Color(hex: "#FF8C00")]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 140)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(languageManager.text("rewards.yourXP"))
                                        .foregroundColor(.white.opacity(0.9))
                                        .font(.system(size: 16))
                                    
                                    Text("\(userManager.userData.totalXP)")
                                        .font(.system(size: 48, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                Text("💎")
                                    .font(.system(size: 64))
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 24)
                    
                    HStack(alignment: .center, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#FF8C00"))
                            .frame(width: 4, height: 24)

                        Text(languageManager.text("Available Rewards"))
                            .foregroundColor(.black.opacity(0.8))
                            .font(.system(size: 20, weight: .bold))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    
                    // Loading or Rewards List
                    if isLoading {
                        ProgressView()
                            .frame(height: 100)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(rewards) { reward in
                                RewardCard(reward: reward, userXP: userManager.userData.totalXP) { selected in
                                    selectedReward = selected
                                    showRedeemDialog = true
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .alert(
            "Redeem Reward",
            isPresented: .constant(selectedReward != nil),
            presenting: selectedReward
        ) { reward in
            Button("Redeem") {
                redeemReward(rewardId: reward.id)
            }
            Button("Cancel", role: .cancel) {
                selectedReward = nil
            }
        } message: { reward in
            Text("Are you sure you want to redeem \(reward.title) for \(reward.xp_cost) XP?")
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage ?? "An error occurred"),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $showSuccess) {
            Alert(
                title: Text("Success"),
                message: Text("Redemption Code: \(redemptionData?.code ?? "")\n\nKeep this code for your records."),
                dismissButton: .default(Text("OK")) {
                    redemptionData = nil
                    selectedReward = nil
                }
            )
        }
        .onAppear() {
            userManager.fetchAllUserData()
            fetchRewards()
        }
    }
    
    private func fetchRewards() {
        isLoading = true
        ServiceModel.shared.fetchRewards(page: 1, pageSize: 20) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let fetchedRewards):
                    self.rewards = fetchedRewards
                case .failure(let error):
                    self.errorMessage = "Failed to load rewards: \(error.localizedDescription)"
                    self.showError = true
                }
            }
        }
    }
    
    private func redeemReward(rewardId: Int) {
        ServiceModel.shared.redeemReward(rewardId: rewardId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    // Show redemption code to user
                    self.redemptionData = response.data
                    self.showSuccess = true
                    // Refresh user data and rewards in background
                    userManager.fetchAllUserData()
                    fetchRewards()
                    selectedReward = nil
                case .failure(let error):
                    if let reward = selectedReward {
                        let userXP = userManager.userData.totalXP
                        let neededXP = reward.xp_cost
                        
                        self.errorMessage = "Not enough XP. You have \(userXP) XP, need \(neededXP)."
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    
                    self.showError = true
                    selectedReward = nil
                }
            }
        }
    }
}

// MARK: Reward Card
struct RewardCard: View {
    var reward: APIReward
    var userXP: Int
    var onRedeem: (APIReward) -> Void

    @EnvironmentObject var languageManager: LanguageManager

    var canAfford: Bool {
        userXP >= reward.xp_cost
    }

    var body: some View {
        HStack(spacing: 16) {
            // image
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)

                if let imageUrl = reward.image_url, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(12)
                    } placeholder: {
                        ProgressView()
                            .frame(width: 80, height: 80)
                    }
                } else {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(reward.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)

                if let merchant = reward.merchant_name, !merchant.isEmpty {
                    Text(merchant)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 14))
                    Text("\(reward.xp_cost) XP")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(canAfford ? .blue : .gray)
                }
            }

            Spacer()

            Button(action: {
                onRedeem(reward)
            }) {
                HStack(spacing: 4) {
                    if !canAfford {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(canAfford ? "Redeem" : "Locked")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    ZStack {
                        if canAfford {
                            LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.gray
                        }
                    }
                )
                .cornerRadius(12)
            }
            .disabled(!canAfford)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: API Response Model
struct RewardsCatalogResponse: Codable {
    let rewards: [APIReward]
    let total: Int
    let page: Int
    let page_size: Int
    let total_pages: Int
}

// MARK: API Reward Model
struct APIReward: Identifiable, Codable {
    let id: Int
    let title: String
    let description: String?
    let reward_type: String
    let merchant_name: String?
    let xp_cost: Int
    let required_level: Int?
    let availability_type: String
    let starts_at: String?
    let expires_at: String?
    let stock_type: String
    let quantity_total: Int?
    let quantity_remaining: Int?
    let per_user_limit: Int?
    let redemption_instructions: String?
    let image_url: String?
    let status: String
    let is_active: Bool
    let created_at: String
    let updated_at: String
}

// MARK: Redeem Response Model
struct RedeemResponse: Codable {
    let success: Bool
    let message: String
    let data: RedemptionData
}

// MARK: Redemption Data Model
struct RedemptionData: Codable {
    let redemption_id: Int
    let code: String
    let instructions: String
}

// MARK: Dummy Data
func getDemoRewards() -> [APIReward] {
    return []
}


#Preview {
    RewardsView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
