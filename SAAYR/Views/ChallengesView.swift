import SwiftUI

// MARK: - Models

struct ChallengesResponse: Decodable {
    let daily: ChallengeGroup
    let weekly: ChallengeGroup
}

struct ChallengeGroup: Decodable {
    let completed: Int
    let total: Int
    let expires : String?
    let challenges: [APIChallenge]
}

struct APIChallenge: Decodable, Identifiable {
    var id: Int { mission_id }
    let mission_id: Int
    let title: String
    let description: String
    let xp_reward: Int
    let target_count: Int
    let current_count: Int
    let status: String          // "not_started" | "in_progress" | "completed"
    let progress_percentage: Double
    let completed_at: String?

    var isCompleted: Bool { status == "completed" }
    var progressFraction: Double {
        min(1.0, Double(current_count) / Double(max(target_count, 1)))
    }
}

// MARK: - ChallengesView

struct ChallengesView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager

    var previewData: ChallengesResponse? = nil   // inject mock data in previews

    @State private var response: ChallengesResponse? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var dailyExpanded = false
    @State private var weeklyExpanded = false

    private let dailyColor  = Color(hex: "#7C3AED")
    private let weeklyColor = Color(hex: "#F97316")

    var body: some View {
        ZStack {
            Color(hex: "#F3F0FF").ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .scaleEffect(1.4)
            } else if let err = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button("Retry") { loadChallenges() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(dailyColor)
                }
                .padding(32)
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        if let data = response {
                            summaryCards(data: data)
                            challengeSection(
                                title: "Daily Challenges",
                                group: data.daily,
                                accentColor: dailyColor,
                                isExpanded: $dailyExpanded
                            )
                            challengeSection(
                                title: "Weekly Challenges",
                                group: data.weekly,
                                accentColor: weeklyColor,
                                isExpanded: $weeklyExpanded
                            )
                        }
                        Spacer(minLength: 100)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear { loadChallenges() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Challenges")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.black)
            Text("Complete challenges to earn bonus XP")
                .font(.system(size: 15))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    // MARK: - Summary Cards

    private func summaryCards(data: ChallengesResponse) -> some View {
        HStack(spacing: 14) {
            summaryCard(
                icon: "clock",
                label: "Daily Challenges",
                completed: data.daily.completed,
                total: data.daily.total,
                color: dailyColor
            )
            summaryCard(
                icon: "trophy",
                label: "Weekly Challenges",
                completed: data.weekly.completed,
                total: data.weekly.total,
                color: weeklyColor
            )
        }
        .padding(.horizontal, 20)
    }

    private func summaryCard(icon: String, label: String,
                             completed: Int, total: Int,
                             color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            Text("\(completed)/\(total)")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text("Complete")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(
                    colors: [color, color.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 4)
    }

    // MARK: - Challenge Section

    @ViewBuilder
    private func challengeSection(title: String,
                                  group: ChallengeGroup, accentColor: Color,
                                  isExpanded: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accentColor)
                    .frame(width: 4, height: 22)
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
                if let expires = group.expires {
                    Text(expires)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(accentColor.opacity(0.4), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 20)

            if group.challenges.isEmpty {
                Text("No challenges available")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
            } else {
                let visible = isExpanded.wrappedValue
                    ? group.challenges
                    : Array(group.challenges.prefix(1))
                let hiddenCount = group.challenges.count - 1

                VStack(spacing: 12) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, challenge in
                        ChallengeCard(challenge: challenge,
                                      accentColor: accentColor,
                                      iconIndex: index)
                    }
                }
                .padding(.horizontal, 20)

                if hiddenCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isExpanded.wrappedValue.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(isExpanded.wrappedValue
                                 ? "View Less"
                                 : "View \(hiddenCount) More")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(accentColor)
                            Image(systemName: isExpanded.wrappedValue
                                  ? "chevron.up" : "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(accentColor)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor.opacity(0.08))
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - API

    private func loadChallenges() {
        if let mock = previewData {
            response = mock
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        ServiceModel.shared.fetchChallenges { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    response = data
                case .failure:
                    errorMessage = "Failed to load challenges.\nPlease try again."
                }
            }
        }
    }

}

// MARK: - ChallengeCard

private struct ChallengeCard: View {
    let challenge: APIChallenge
    let accentColor: Color
    let iconIndex: Int

    private var iconName: String {
        let icons = ["scope", "flame.fill", "star.fill", "bolt.fill",
                     "checkmark.seal.fill", "map.fill", "heart.fill"]
        return icons[iconIndex % icons.count]
    }

    private var statusText: String {
        switch challenge.status {
        case "completed":   return "Completed"
        case "in_progress": return "In Progress"
        default:            return "Not Started"
        }
    }

    private var statusColor: Color {
        switch challenge.status {
        case "completed":   return Color(hex: "#16A34A")
        case "in_progress": return Color(hex: "#2563EB")
        default:            return Color(hex: "#9CA3AF")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 52, height: 52)
                    Image(systemName: iconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                    Text(challenge.description)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(statusColor)
                    Spacer()
                    Text("\(challenge.current_count)/\(challenge.target_count)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * challenge.progressFraction, height: 8)
                    }
                }
                .frame(height: 8)
            }

            // XP reward
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#D97706"))
                Text("+\(challenge.xp_reward) XP")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#D97706"))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }
}

#Preview {
    let mockDaily = ChallengeGroup(completed: 1, total: 3, expires: "Reset in 8h", challenges: [
        APIChallenge(mission_id: 1, title: "Check in 3 locations",
                     description: "Visit and check in at 3 different spots",
                     xp_reward: 100, target_count: 3, current_count: 2,
                     status: "in_progress", progress_percentage: 66, completed_at: nil),
        APIChallenge(mission_id: 2, title: "Spend at a partner store",
                     description: "Make any purchase at a SAAYR partner",
                     xp_reward: 150, target_count: 1, current_count: 1,
                     status: "completed", progress_percentage: 100, completed_at: "2025-01-01"),
        APIChallenge(mission_id: 3, title: "Morning check-in",
                     description: "Check in before 10 AM today",
                     xp_reward: 75, target_count: 1, current_count: 0,
                     status: "not_started", progress_percentage: 0, completed_at: nil),
    ])
    let mockWeekly = ChallengeGroup(completed: 0, total: 3, expires: "Reset in 3d ", challenges: [
        APIChallenge(mission_id: 4, title: "Reach Level 5",
                     description: "Level up your pet to level 5",
                     xp_reward: 500, target_count: 5, current_count: 2,
                     status: "in_progress", progress_percentage: 40, completed_at: nil),
        APIChallenge(mission_id: 5, title: "Win a PVP battle",
                     description: "Beat another player in a PVP match",
                     xp_reward: 300, target_count: 1, current_count: 0,
                     status: "not_started", progress_percentage: 0, completed_at: nil),
        APIChallenge(mission_id: 6, title: "Spend 500 SAR",
                     description: "Spend 500 SAR total at partner locations",
                     xp_reward: 800, target_count: 500, current_count: 210,
                     status: "in_progress", progress_percentage: 42, completed_at: nil),
    ])
    ChallengesView(previewData: ChallengesResponse(daily: mockDaily, weekly: mockWeekly))
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
