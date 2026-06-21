import SwiftUI

struct RewardsView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager

    @State private var rewards: [APIReward] = []
    @State private var selectedReward: APIReward?
    @State private var isLoadingRewards = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var redemptionData: RedemptionData?
    @State private var showSuccess = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#F0F9FF"), Color.white, Color(hex: "#FFF7ED")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // MARK: - Header row: title + XP pill
                    HStack(alignment: .center) {
                        Text(languageManager.text("rewards.title"))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color(hex: "#FF8C00"))

                        Spacer()

                        // Compact XP pill
                        HStack(spacing: 5) {
                            Text("💎")
                                .font(.system(size: 14))
                            Text("\(userManager.userData.totalXP) XP")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color(hex: "#FFA500"), Color(hex: "#FF6B00")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                        )
                    }
                    .padding(.horizontal)
                    .padding(.top, 24)

                    // MARK: - Available Rewards
                    HStack(alignment: .center, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#FF8C00"))
                            .frame(width: 4, height: 24)
                        Text("Available Rewards")
                            .foregroundColor(.black.opacity(0.8))
                            .font(.system(size: 20, weight: .bold))
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    if isLoadingRewards {
                        ProgressView().frame(height: 100)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(rewards) { reward in
                                RewardCard(reward: reward, userXP: userManager.userData.totalXP) { selected in
                                    selectedReward = selected
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        // Redeem confirmation
        .alert(
            "Redeem Reward",
            isPresented: .constant(selectedReward != nil),
            presenting: selectedReward
        ) { reward in
            Button("Redeem") { redeemReward(rewardId: reward.id) }
            Button("Cancel", role: .cancel) { selectedReward = nil }
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
        .onAppear {
            userManager.fetchAllUserData()
            fetchRewards()
        }
    }

    // MARK: - API

    private func fetchRewards() {
        isLoadingRewards = true
        ServiceModel.shared.fetchRewards(page: 1, pageSize: 20) { result in
            DispatchQueue.main.async {
                isLoadingRewards = false
                if case .success(let fetched) = result { rewards = fetched }
            }
        }
    }

    private func redeemReward(rewardId: Int) {
        ServiceModel.shared.redeemReward(rewardId: rewardId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    redemptionData = response.data
                    showSuccess = true
                    userManager.fetchAllUserData()
                    fetchRewards()
                    selectedReward = nil
                case .failure:
                    if let reward = selectedReward {
                        errorMessage = "Not enough XP. You have \(userManager.userData.totalXP) XP, need \(reward.xp_cost)."
                    } else {
                        errorMessage = "Redemption failed. Please try again."
                    }
                    showError = true
                    selectedReward = nil
                }
            }
        }
    }
}

// MARK: - Reward Card

struct RewardCard: View {
    var reward: APIReward
    var userXP: Int
    var onRedeem: (APIReward) -> Void

    @EnvironmentObject var languageManager: LanguageManager

    var canAfford: Bool { userXP >= reward.xp_cost }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                if let imageUrl = reward.image_url, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(12)
                    } placeholder: {
                        ProgressView().frame(width: 80, height: 80)
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

            Button { onRedeem(reward) } label: {
                HStack(spacing: 4) {
                    if !canAfford {
                        Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold))
                    }
                    Text(canAfford ? "Redeem" : "Locked")
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    canAfford
                        ? AnyView(LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing))
                        : AnyView(Color.gray)
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

// MARK: - API Models

struct WeeklyTop3Response: Decodable {
    let pool_id: Int?
    let pool_name: String?
    let period_start: String?
    let period_end: String?
    let top3: [WeeklyTop3Entry]
    let my_rank: Int?
    let my_points: Int?
}

struct WeeklyTop3Entry: Decodable {
    let rank: Int
    let user_id: Int
    let falcon_name: String?
    let full_name: String?
    let level: Int
    let points: Int
    let avatar: String?
    let prize_name: String?
    let prize_type: String?
    let prize_image_url: String?

    var displayName: String {
        full_name?.isEmpty == false ? full_name! : (falcon_name ?? "Unknown")
    }
}

struct RewardsCatalogResponse: Codable {
    let rewards: [APIReward]
    let total: Int
    let page: Int
    let page_size: Int
    let total_pages: Int
}

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

struct RedeemResponse: Codable {
    let success: Bool
    let message: String
    let data: RedemptionData
}

struct RedemptionData: Codable {
    let redemption_id: Int
    let code: String
    let instructions: String
}

#Preview {
    RewardsView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
