import SwiftUI

struct LeaderboardFullView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) var dismiss
    
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var allLeaderboardUsers: [LeaderboardUser] = []
    @State private var totalPages = 1
    @State private var myRank: MyRank? = nil
    
    let itemsPerPage = 20
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "#F0F9FF"), Color(hex: "#FFFFFF"), Color(hex: "#FFF7ED")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text(languageManager.currentLanguage == .english ? "Back" : "رجوع")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Text(languageManager.currentLanguage == .english ? "Leaderboard" : "قائمة المتصدرين")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    // Placeholder for alignment
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(languageManager.currentLanguage == .english ? "Back" : "رجوع")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.clear)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Location filter
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                    
                    Text("Riyadh")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                
                // Leaderboard list with pagination
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(allLeaderboardUsers) { user in
                            LeaderboardCard(user: .constant(user), rank: user.rank)
                        }
                        
                        // Load More Button
                        if currentPage < totalPages && !isLoading {
                            Button(action: { loadNextPage() }) {
                                Text(languageManager.currentLanguage == .english ? "Load More" : "تحميل المزيد")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }

                        // Loading indicator
                        if isLoading {
                            ProgressView()
                                .padding()
                        }

                        // Your Position
                        if let rank = myRank {
                            yourPositionCard(rank: rank)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            fetchLeaderboardPage(page: 1)
        }
    }
    
    private func fetchLeaderboardPage(page: Int) {
        isLoading = true
        
        let params: [String: Any] = [
            "city": "Riyadh",
            "page": page,
            "limit": itemsPerPage
        ]
        
        ServiceModel.shared.getRequest(endpoint: WebService.leaderboard, parameters: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let data):
                    do {
                        let decoded = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
                        
                        let newUsers = decoded.leaderboard.map { entry in
                            LeaderboardUser(
                                id: entry.user_id,
                                rank: entry.rank,
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
                        
                        if page == 1 {
                            allLeaderboardUsers = newUsers
                        } else {
                            allLeaderboardUsers.append(contentsOf: newUsers)
                        }
                        
                        currentPage = page
                        totalPages = ((decoded.total_entries ?? 1) + itemsPerPage - 1) / itemsPerPage
                        if page == 1 { myRank = decoded.my_rank }
                        
                    } catch {
                        print("❌ Decoding error (leaderboard):", error)
                    }
                case .failure(let error):
                    print("❌ API error (leaderboard):", error.localizedDescription)
                }
            }
        }
    }
    
    private func loadNextPage() {
        fetchLeaderboardPage(page: currentPage + 1)
    }

    // MARK: - Your Position Card

    private func yourPositionCard(rank: MyRank) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Position")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            HStack(spacing: 14) {
                // Rank badge
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Text("#\(rank.rank)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }

                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 44, height: 44)
                    if let urlStr = rank.avatar, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(rank.full_name ?? rank.falcon_name ?? "You")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Level \(rank.level)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                Text("\(rank.points) pts")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .shadow(color: Color(hex: "#6366F1").opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    LeaderboardFullView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
