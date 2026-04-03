import SwiftUI

// MARK: - Flow State

enum PVPFlowState {
    case findingOpponent
    case countdown(match: FullMatchData, remaining: Int)
    case racing(match: FullMatchData)
    case result(match: FullMatchData)
}

// MARK: - Root Flow View

struct PVPMatchFlowView: View {
    let paymentId: String
    let entryFeeSAR: Int
    @Binding var isPresented: Bool
    @EnvironmentObject var userManager: UserManager

    @State private var flowState: PVPFlowState = .findingOpponent
    @State private var toastMessage: (title: String, subtitle: String)? = nil
    @State private var showToast = false
    @State private var pollTimer: Timer? = nil

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            Color(hex: "#FFF8F5").ignoresSafeArea()

            // State-driven content
            Group {
                switch flowState {
                case .findingOpponent:
                    FindingOpponentView(entryFeeSAR: entryFeeSAR, onCancel: cancelAndDismiss)
                case .countdown(let match, let remaining):
                    CountdownView(match: match, countdown: remaining, entryFeeSAR: entryFeeSAR)
                case .racing(let match):
                    RaceView(match: match, entryFeeSAR: entryFeeSAR, onMatchUpdated: { updated in
                        if updated.status == "completed" {
                            stopPolling()
                            withAnimation { flowState = .result(match: updated) }
                        } else {
                            flowState = .racing(match: updated)
                        }
                    }, onExit: {
                        stopPolling()
                        isPresented = false
                        userManager.fetchMyMatch()
                    })
                case .result(let match):
                    ResultView(match: match, onReturn: {
                        isPresented = false
                        userManager.fetchMyMatch()
                    })
                }
            }

            // Toast overlay
            if showToast, let toast = toastMessage {
                ToastView(title: toast.title, subtitle: toast.subtitle)
                    .padding(.horizontal, 16)
                    .padding(.top, 52)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .onAppear {
            print("paymentId \(paymentId)")
            
            startMatchmaking(paymentId:paymentId) }
        .onDisappear { stopPolling() }
    }

    // MARK: - Matchmaking

    private func startMatchmaking(paymentId : String) {
        ServiceModel.shared.startMatchmaking(paymentId: paymentId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showToastMessage(title: "Payment successful!", subtitle: "\(entryFeeSAR) SAR paid. Finding opponent...")
                    startWaitingPoll()
                case .failure:
                    showToastMessage(title: "Payment Failed!", subtitle: "\(entryFeeSAR) SAR paid. Finding opponent...")
                    startWaitingPoll()
                }
            }
        }
    }

    // MARK: - Polling

    private func startWaitingPoll() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            pollForMatch()
        }
        pollForMatch()
    }

    private func pollForMatch() {
        ServiceModel.shared.fetchMyMatchFull { result in
            DispatchQueue.main.async {
                guard case .success(let response) = result, let data = response.data else { return }
                switch data.status {
                case "matched", "in_progress":
                    stopPolling()
                    if let opponentName = data.opponent?.falcon_name {
                        showToastMessage(title: "Opponent found!", subtitle: "Matched with \(opponentName)")
                    }
                    startCountdown(match: data)
                case "completed":
                    stopPolling()
                    withAnimation { flowState = .result(match: data) }
                case "cancelled", "voided":
                    stopPolling()
                    isPresented = false
                default:
                    break // "waiting" — keep polling
                }
            }
        }
    }

    private func startCountdown(match: FullMatchData) {
        var count = 10
        flowState = .countdown(match: match, remaining: count)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            count -= 1
            if count > 0 {
                flowState = .countdown(match: match, remaining: count)
            } else {
                timer.invalidate()
                withAnimation { flowState = .racing(match: match) }
                startRacePoll(matchId: match.match_id)
            }
        }
    }

    private func startRacePoll(matchId: Int) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            ServiceModel.shared.fetchMatchState(matchId: matchId) { result in
                DispatchQueue.main.async {
                    guard case .success(let response) = result, let data = response.data else { return }
                    if data.status == "completed" {
                        stopPolling()
                        withAnimation { flowState = .result(match: data) }
                    } else {
                        flowState = .racing(match: data)
                    }
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func cancelAndDismiss() {
        ServiceModel.shared.cancelMatch { _ in }
        stopPolling()
        isPresented = false
        userManager.fetchMyMatch()
    }

    // MARK: - Toast

    private func showToastMessage(title: String, subtitle: String) {
        toastMessage = (title, subtitle)
        withAnimation(.spring()) { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showToast = false }
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.black).frame(width: 32, height: 32)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.black)
                Text(subtitle).font(.system(size: 13)).foregroundColor(Color(hex: "#6B7280"))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Finding Opponent View

struct FindingOpponentView: View {
    let entryFeeSAR: Int
    let onCancel: () -> Void

    @State private var dotPhase = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Sword icon
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseScale)
                Image(systemName: "figure.fencing")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundColor(.white)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.06
                }
                startDotAnimation()
            }

            Spacer().frame(height: 32)

            Text("Finding Opponent")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "#111827"))

            Text("Matching you with a player of similar level...")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "#6B7280"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)

            Spacer().frame(height: 32)

            // Animated dots
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color(hex: "#EF4444").opacity(i == dotPhase % 3 ? 1.0 : 0.35))
                        .frame(width: 12, height: 12)
                        .scaleEffect(i == dotPhase % 3 ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: dotPhase)
                }
            }

            Spacer()

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#6B7280"))
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startDotAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            dotPhase += 1
        }
    }
}

// MARK: - Countdown View

struct CountdownView: View {
    let match: FullMatchData
    let countdown: Int
    let entryFeeSAR: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                // Countdown circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 120, height: 120)
                    Text("\(countdown)")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .id(countdown) // forces re-render for animation
                .transition(.scale.combined(with: .opacity))

                Text("Get Ready!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: "#111827"))

                Text("Mission race starting soon...")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "#6B7280"))

                // Race missions card
                if !match.missions.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Race Missions")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "#111827"))

                        ForEach(match.missions, id: \.id) { mission in
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(hex: "#7C3AED").opacity(0.15))
                                        .frame(width: 52, height: 52)
                                    Image(systemName: missionSystemIcon(mission.icon))
                                        .font(.system(size: 22))
                                        .foregroundColor(Color(hex: "#7C3AED"))
                                }
                                Text(mission.label)
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(hex: "#374151"))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                            .padding(14)
                            .background(Color(hex: "#F5F3FF"))
                            .cornerRadius(14)
                        }

                        Text("Complete all missions before your opponent to win!")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#9CA3AF"))
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
                    .padding(.horizontal, 16)
                }

                // Player cards
                HStack(spacing: 12) {
                    PlayerCard(name: match.my.falcon_name,
                               subtitle: "You",
                               borderColor: Color(hex: "#3B82F6"),
                               bgColor: Color(hex: "#EFF6FF"))

                    if let opp = match.opponent {
                        PlayerCard(name: opp.falcon_name,
                                   subtitle: opp.full_name ?? "",
                                   borderColor: Color(hex: "#EF4444"),
                                   bgColor: Color(hex: "#FFF1F2"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Race View

struct RaceView: View {
    let match: FullMatchData
    let entryFeeSAR: Int
    let onMatchUpdated: (FullMatchData) -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack {
                Button(action: onExit) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.15)).frame(width: 36, height: 36)
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("PVP Mission Race")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Text("Race in progress")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "figure.fencing")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    Text("\(entryFeeSAR) SAR")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(hex: "#0F1623"))

            ScrollView {
                VStack(spacing: 0) {
                    // Your progress
                    RacePlayerSection(
                        participant: match.my,
                        isMe: true,
                        missions: match.missions,
                        progress: match.my_progress
                    )

                    // VS divider
                    HStack {
                        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                        ZStack {
                            Capsule().fill(Color(hex: "#1E2940")).frame(width: 48, height: 28)
                            Text("VS").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        }
                        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    // Opponent progress
                    if let opp = match.opponent {
                        RacePlayerSection(
                            participant: opp,
                            isMe: false,
                            missions: match.missions,
                            progress: match.opponent_progress
                        )
                    }

                    // Activity log
                    if !match.activity_log.isEmpty {
                        ActivityLogView(logs: match.activity_log)
                            .padding(16)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color(hex: "#0F1623"))
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Race Player Section

struct RacePlayerSection: View {
    let participant: MatchParticipant
    let isMe: Bool
    let missions: [MatchMission]
    let progress: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Player header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: isMe
                                    ? [Color(hex: "#3B82F6"), Color(hex: "#60A5FA")]
                                    : [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 60, height: 60)
                    Image(systemName: "circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.4))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.falcon_name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text(isMe ? "You" : (participant.full_name ?? ""))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
            }

            // Mission rows
            ForEach(missions, id: \.id) { mission in
                MissionProgressRow(
                    mission: mission,
                    current: progress[mission.id] ?? 0,
                    isMe: isMe
                )
            }
        }
        .padding(20)
    }
}

// MARK: - Mission Progress Row

struct MissionProgressRow: View {
    let mission: MatchMission
    let current: Int
    let isMe: Bool

    var fraction: Double {
        guard mission.target > 0 else { return 0 }
        return min(Double(current) / Double(mission.target), 1.0)
    }

    var isComplete: Bool { current >= mission.target }

    var progressColor: Color {
        if isComplete { return Color(hex: "#22C55E") }
        return isMe ? Color(hex: "#3B82F6") : Color(hex: "#EF4444")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: missionSystemIcon(mission.icon))
                        .font(.system(size: 18))
                        .foregroundColor(isMe ? Color(hex: "#60A5FA") : Color(hex: "#F97316"))
                }
                Text(mission.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(hex: "#22C55E"))
                }
            }

            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressColor)
                            .frame(width: geo.size.width * fraction)
                            .animation(.easeOut(duration: 0.5), value: fraction)
                    }
                }
                .frame(height: 8)

                Text("\(current)/\(mission.target)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(minWidth: 60, alignment: .trailing)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }
}

// MARK: - Activity Log View

struct ActivityLogView: View {
    let logs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(hex: "#F59E0B")).frame(width: 36, height: 36)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
                Text("Activity Log")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
            }

            ForEach(Array(logs.reversed().enumerated()), id: \.offset) { _, log in
                Text(log)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#374151"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#F9FAFB"))
                    .cornerRadius(10)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
    }
}

// MARK: - Result View

struct ResultView: View {
    let match: FullMatchData
    let onReturn: () -> Void

    var isVictory: Bool { match.i_won }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Activity log
                if !match.activity_log.isEmpty {
                    ActivityLogView(logs: match.activity_log)
                        .padding(16)
                }

                // Result card
                VStack(spacing: 20) {
                    Image(systemName: isVictory ? "crown.fill" : "flag.fill")
                        .font(.system(size: 52, weight: .light))
                        .foregroundColor(.white)

                    Text(isVictory ? "Victory!" : "Defeat!")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    Text(isVictory
                         ? "You completed all missions first and won \(match.winner_xp) XP!"
                         : "Your opponent completed all missions first.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Button(action: onReturn) {
                        Text("Return to Home")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(isVictory ? Color(hex: "#166534") : Color(hex: "#7F1D1D"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
                .padding(28)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: isVictory
                                    ? [Color(hex: "#16A34A"), Color(hex: "#15803D")]
                                    : [Color(hex: "#EF4444"), Color(hex: "#DC2626")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .padding(16)
            }
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Shared Player Card (for countdown screen)

struct PlayerCard: View {
    let name: String
    let subtitle: String
    let borderColor: Color
    let bgColor: Color

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(bgColor)
                    .frame(width: 70, height: 70)
                Image(systemName: "circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(subtitle.isEmpty ? " " : subtitle)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#6B7280"))
            Text(name)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(hex: "#111827"))
            Text("Level 1")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#6B7280"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 1.5)
        )
    }
}

// MARK: - Active Match View (re-join in-progress match)

struct ActiveMatchView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var userManager: UserManager

    @State private var match: FullMatchData? = nil
    @State private var pollTimer: Timer? = nil

    var body: some View {
        ZStack {
            Color(hex: "#0F1623").ignoresSafeArea()

            if let match = match {
                RaceView(
                    match: match,
                    entryFeeSAR: 0,
                    onMatchUpdated: { updated in
                        if updated.status == "completed" {
                            stopPolling()
                            self.match = updated
                        } else {
                            self.match = updated
                        }
                    },
                    onExit: {
                        stopPolling()
                        isPresented = false
                        userManager.fetchMyMatch()
                    }
                )
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
        .onAppear {
            match = userManager.activeMatchData
            startPoll()
        }
        .onDisappear { stopPolling() }
    }

    private func startPoll() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            guard let matchId = match?.match_id else { return }
            ServiceModel.shared.fetchMatchState(matchId: matchId) { result in
                DispatchQueue.main.async {
                    guard case .success(let response) = result, let data = response.data else { return }
                    match = data
                    if data.status == "completed" {
                        stopPolling()
                        userManager.activeMatchStatus = false
                        userManager.activeMatchData = nil
                    }
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

// MARK: - Helper

func missionSystemIcon(_ icon: String) -> String {
    switch icon {
    case "location": return "mappin.and.ellipse"
    case "steps":    return "figure.walk"
    case "target":   return "target"
    case "spend":    return "creditcard"
    case "redeem":   return "gift"
    default:         return "star"
    }
}
