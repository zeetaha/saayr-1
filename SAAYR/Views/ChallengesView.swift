import SwiftUI

struct ChallengesView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager
    
    @State private var challenges: [Challenge] = getDemoChallenges()
    @State private var showClaimDialog = false
    @State private var selectedChallenge: Challenge?
    
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(languageManager.text("challenges.title")) // "Challenges"
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.black)
                        Text(languageManager.text("challenges.subtite")) // "Complete challenges..."
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                    .padding(.top, 24)
                    
                    Text(languageManager.text("No Records Available"))
                        .foregroundColor(.black.opacity(0.8))
                        .font(.system(size: 14))
                    
//                    // Daily Challenges
//                    ChallengeSection(
//                        title: languageManager.text("challenges.daily"),
//                        resetInfo: "Resets in 18 hours",
//                        challenges: challenges.filter { $0.type == .daily },
//                        onClaim: { challenge in
//                            selectedChallenge = challenge
//                            showClaimDialog = true
//                        }
//                    )
//                    
//                    // Weekly Challenges
//                    ChallengeSection(
//                        title: languageManager.text("challenges.weekly"),
//                        resetInfo: "Resets in 5 days",
//                        challenges: challenges.filter { $0.type == .weekly },
//                        onClaim: { challenge in
//                            selectedChallenge = challenge
//                            showClaimDialog = true
//                        }
//                    )
//                    
                    Spacer(minLength: 100)
                }
            }
        }
        .alert(isPresented: $showClaimDialog) {
            guard let challenge = selectedChallenge else {
                return Alert(title: Text("Error"))
            }
            
            return Alert(
                title: Text(languageManager.text("challenges.claimReward")),
                message: Text("\(languageManager.text("challenges.completed")): \(challenge.title)"),
                primaryButton: .default(Text(languageManager.text("challenges.claim"))) {
                    // Mark challenge as claimed
                    challenges = challenges.map {
                        $0.id == challenge.id ? $0.copy(isClaimed: true) : $0
                    }
                    // Add XP to user
                    userManager.addXP(challenge.xpReward, reason: "Challenge completed")
                },
                secondaryButton: .cancel()
            )
        }
    }
}

// MARK: Challenge Section
struct ChallengeSection: View {
    let title: String
    let resetInfo: String
    let challenges: [Challenge]
    let onClaim: (Challenge) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
            Text(resetInfo)
                .font(.system(size: 14))
                .foregroundColor(.gray)
            
            VStack(spacing: 12) {
                ForEach(challenges) { challenge in
                    ChallengeCard(challenge: challenge, onClaim: onClaim)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: Challenge Card
import SwiftUI

struct ChallengeCard: View {
    let challenge: Challenge
    let onClaim: (Challenge) -> Void
    
    @EnvironmentObject var languageManager: LanguageManager
    
    var isCompleted: Bool {
        challenge.progress >= challenge.goal
    }
    
    var progressPercentage: Double {
        min(1.0, Double(challenge.progress) / Double(max(challenge.goal, 1)))
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.currentLanguage == .english ? challenge.title : challenge.titleAr)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(challenge.isClaimed ? .gray : .black)
                    
                    Text(languageManager.currentLanguage == .english ? challenge.description : challenge.descriptionAr)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if challenge.isClaimed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .foregroundColor(Color.green)
                            .font(.system(size: 16))
                        Text("Claimed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            
            // Progress Bar
            VStack(spacing: 4) {
                HStack {
                    Text("Progress")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(challenge.progress)/\(challenge.goal)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }
                
                ProgressView(value: progressPercentage)
                    .accentColor(isCompleted ? Color.green : Color.blue)
                    .frame(height: 8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            
            // Rewards & Claim Button
            HStack {
                HStack(spacing: 12) {
                    // XP Reward
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(Color.blue)
                            .font(.system(size: 18))
                        Text("\(challenge.xpReward)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.blue)
                    }
                    
                    // Points Reward
                    if challenge.xpReward > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(Color.red)
                                .font(.system(size: 18))
                            Text("\(challenge.xpReward)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color.red)
                        }
                    }
                }
                
                Spacer()
                
                if isCompleted && !challenge.isClaimed {
                    Button(action: { onClaim(challenge) }) {
                        Text("Claim")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(challenge.isClaimed ? Color(.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}


// MARK: Dummy Data
func getDemoChallenges() -> [Challenge] {
    [
        // MARK: Daily Challenges
        Challenge(
            id: "1",
            title: "Daily Check-In Streak",
            titleAr: "سلسلة تسجيل الحضور اليومية",
            description: "Check in at 3 different locations today",
            descriptionAr: "سجل حضورك في 3 مواقع مختلفة اليوم",
            xpReward: 150,
            progress: 2,
            goal: 3,
            type: .daily,
            isCompleted: false,
            isClaimed: false
        ),
        Challenge(
            id: "2",
            title: "Spend at Partner Locations",
            titleAr: "الإنفاق عند الشركاء",
            description: "Make a purchase at any partner location",
            descriptionAr: "قم بعملية شراء عند أي موقع شريك",
            xpReward: 100,
            progress: 1,
            goal: 1,
            type: .daily,
            isCompleted: true,
            isClaimed: false
        ),
        Challenge(
            id: "3",
            title: "Pet Care",
            titleAr: "العناية بالحيوان الأليف",
            description: "Earn 200 XP from transactions",
            descriptionAr: "احصل على 200 نقطة خبرة من المعاملات",
            xpReward: 50,
            progress: 150,
            goal: 200,
            type: .daily,
            isCompleted: false,
            isClaimed: false
        ),
        Challenge(
            id: "4",
            title: "Morning Bird",
            titleAr: "الطائر المبكر",
            description: "Check in before 10 AM",
            descriptionAr: "سجل حضورك قبل الساعة 10 صباحًا",
            xpReward: 75,
            progress: 0,
            goal: 1,
            type: .daily,
            isCompleted: false,
            isClaimed: false
        ),

        // MARK: Weekly Challenges
        Challenge(
            id: "5",
            title: "Weekly Warrior",
            titleAr: "محارب الأسبوع",
            description: "Complete 15 check-ins this week",
            descriptionAr: "أكمل 15 تسجيل حضور هذا الأسبوع",
            xpReward: 500,
            progress: 8,
            goal: 15,
            type: .weekly,
            isCompleted: false,
            isClaimed: false
        ),
        Challenge(
            id: "6",
            title: "Big Spender",
            titleAr: "المنفق الكبير",
            description: "Spend 500 SAR at partner locations",
            descriptionAr: "أنفق 500 ريال عند مواقع الشركاء",
            xpReward: 1000,
            progress: 320,
            goal: 500,
            type: .weekly,
            isCompleted: false,
            isClaimed: false
        ),
        Challenge(
            id: "7",
            title: "Level Up!",
            titleAr: "ارتقِ بالمستوى!",
            description: "Reach level 10",
            descriptionAr: "الوصول إلى المستوى 10",
            xpReward: 750,
            progress: 7,
            goal: 10,
            type: .weekly,
            isCompleted: false,
            isClaimed: false
        ),
        Challenge(
            id: "8",
            title: "PVP Champion",
            titleAr: "بطل المواجهات",
            description: "Win 3 PVP battles",
            descriptionAr: "الفوز في 3 معارك PVP",
            xpReward: 600,
            progress: 1,
            goal: 3,
            type: .weekly,
            isCompleted: false,
            isClaimed: false
        )
    ]
}


struct Challenge: Identifiable {
    let id: String
    let title: String
    let titleAr: String
    let description: String
    let descriptionAr: String
    let xpReward: Int
    let progress: Int
    let goal: Int
    let type: ChallengeType
    let isCompleted: Bool
    let isClaimed: Bool   // <-- Add this

    // Copy method to update claimed status
    func copy(isClaimed: Bool) -> Challenge {
        Challenge(
            id: id,
            title: title,
            titleAr: titleAr,
            description: description,
            descriptionAr: descriptionAr,
            xpReward: xpReward,
            progress: progress,
            goal: goal,
            type: type,
            isCompleted: isCompleted,
            isClaimed: isClaimed
        )
    }
}


enum ChallengeType {
    case daily, weekly, special
}


#Preview {
    ChallengesView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
