import SwiftUI

struct LeaderboardFullView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) var dismiss
    
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var allLeaderboardUsers: [LeaderboardUser] = []
    @State private var totalPages = 1
    
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
                            LeaderboardCard(user: .constant(user))
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
                        totalPages = ((decoded.total ?? 1)   + itemsPerPage - 1) / itemsPerPage
                        
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
}

#Preview {
    LeaderboardFullView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
