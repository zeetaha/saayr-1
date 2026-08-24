//
//  BossRewardsView.swift
//  SAAYR
//
//  The scoreboard after a boss ends. Reached either from the ended card in
//  Challenges, or straight off the battle stream's `ended` event.
//

import SwiftUI

struct BossRewardsView: View {

    let bossID: Int
    let isEnglish: Bool
    let onClose: () -> Void
    /// Collected successfully. Separate from `onClose` because the
    /// confirmation has to outlive this screen — it's shown by the host, after
    /// this one has gone.
    let onCollected: (_ xpEarned: Int?) -> Void

    @EnvironmentObject private var userManager: UserManager

    @State private var rewards: BossRewards?
    @State private var isLoading = true
    @State private var celebrate = false
    @State private var isClaiming = false
    @State private var hasClaimed = false
    @State private var claimError: String?

    var body: some View {
        ZStack {
            Color(hex: "#0B0E14").ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: BossStyle.ember))
                    .scaleEffect(1.4)
            } else if let rewards {
                content(rewards)
            } else {
                unavailable
            }

            closeButton
        }
        .onAppear(perform: load)
    }

    private func load() {
        BossAPI.shared.fetchRewards(bossID: bossID) { result in
            rewards = result
            isLoading = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { celebrate = true }
        }
    }

    // MARK: Content

    private func content(_ rewards: BossRewards) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 40)

                Text(emblem(rewards.outcome))
                    .font(.system(size: 58))
                    .scaleEffect(celebrate ? 1 : 0.6)
                    .opacity(celebrate ? 1 : 0)

                VStack(spacing: 6) {
                    Text(headline(rewards.outcome))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(BossStyle.textPrimary)

                    Text(subhead(rewards))
                        .font(.system(size: 13))
                        .foregroundColor(BossStyle.textDim)
                        .multilineTextAlignment(.center)
                }

                if let stats = rewards.user_stats {
                    HStack(spacing: 10) {
                        BossStatTile(
                            value: stats.damage_dealt.formatted(),
                            label: isEnglish ? "Damage" : "الضرر"
                        )
                        BossStatTile(
                            value: String(format: "%.1f%%", stats.contribution_percent),
                            label: isEnglish ? "Contribution" : "المساهمة"
                        )
                        BossStatTile(
                            value: "#\(stats.rank)",
                            label: isEnglish ? "Rank" : "الترتيب",
                            highlighted: true
                        )
                    }
                }

                if let detail = rewards.rewards {
                    xpCard(detail)
                    claimButton(detail)
                } else if !rewards.participated {
                    didNotParticipate
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
    }

    private func xpCard(_ detail: BossRewardDetail) -> some View {
        VStack(spacing: 4) {
            Text("+\(detail.xp_earned.formatted()) XP")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(BossStyle.gold)
            Text(isEnglish ? "Earned this event" : "مكتسبة من هذه المعركة")
                .font(.system(size: 12))
                .foregroundColor(BossStyle.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(BossStyle.gold.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(BossStyle.gold.opacity(0.45), lineWidth: 1)
        )
    }

    /// Collecting is what retires the event: the server marks the reward
    /// acknowledged and stops sending the ended boss in the challenges
    /// payload, so the card clears itself once this screen closes. The XP is
    /// settled server-side, so a zero-XP reward still collects normally.
    private func claimButton(_ detail: BossRewardDetail) -> some View {
        let isCollected = detail.claimed == true || hasClaimed

        return VStack(spacing: 6) {
            Button(action: claim) {
                HStack(spacing: 6) {
                    if isClaiming {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#1A1206")))
                    } else {
                        Text(isCollected
                             ? (isEnglish ? "🎁 Collected" : "🎁 تم الاستلام")
                             : (isEnglish ? "🎁 Collect rewards" : "🎁 استلم مكافآتك"))
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundColor(Color(hex: "#1A1206"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(BossStyle.gold.opacity(isCollected ? 0.45 : 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isClaiming || isCollected)

            if let claimError {
                errorBanner(claimError)
            }
        }
    }

    /// The app's error idiom — warning glyph, red text, red-tinted panel —
    /// in the boss palette. Carries the server's wording verbatim, so it has
    /// to wrap rather than truncate.
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundColor(BossStyle.live)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(BossStyle.live.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BossStyle.live.opacity(0.35), lineWidth: 1)
        )
    }

    /// Closes on success rather than sitting on a collected screen — the host
    /// refetches challenges when this dismisses, which is what makes the ended
    /// card disappear.
    private func claim() {
        guard !isClaiming else { return }
        isClaiming = true
        claimError = nil

        BossAPI.shared.claimRewards(bossID: bossID) { result in
            isClaiming = false

            switch result {
            case .success(let detail):
                // Prefer what the claim returned; fall back to the figure
                // already on screen, which is the same number.
                collected(xp: detail?.xp_earned ?? rewards?.rewards?.xp_earned)
            // Already collected — the endpoint is idempotent and says so with
            // a 409. Treating it as a failure would show an error for a retry
            // that actually worked.
            case .failure(let error) where error.isAlreadyClaimed:
                collected(xp: rewards?.rewards?.xp_earned)
            case .failure(let error):
                // The server's own wording, not a generic retry line — it's
                // the only thing that tells the player what actually stopped
                // them.
                claimError = error.displayMessage(isEnglish: isEnglish)
            }
        }
    }

    /// Claiming credits XP to the real balance, so the cached profile is stale
    /// the moment it succeeds — refreshed here rather than left for the next
    /// screen to notice.
    private func collected(xp: Int?) {
        hasClaimed = true
        userManager.fetchAllUserData()
        onCollected(xp)
    }

    /// A player who never landed a hit has no reward to collect, but their
    /// ended card needs the same way out — without this it has no button at
    /// all and sits in Challenges forever.
    private var didNotParticipate: some View {
        VStack(spacing: 14) {
            Text(isEnglish
                 ? "You didn't join this one. Next time!"
                 : "!لم تشارك هذه المرة. في المرة القادمة")
                .font(.system(size: 13))
                .foregroundColor(BossStyle.textDim)
                .multilineTextAlignment(.center)

            Button(action: claim) {
                HStack(spacing: 6) {
                    if isClaiming {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: BossStyle.textPrimary))
                    } else {
                        Text(isEnglish ? "Dismiss" : "إخفاء")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .foregroundColor(BossStyle.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .disabled(isClaiming)

            if let claimError {
                errorBanner(claimError)
            }
        }
        .padding(.vertical, 18)
    }

    // MARK: Chrome

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(BossStyle.textDim)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .accessibilityLabel(isEnglish ? "Close" : "إغلاق")
            }
            Spacer()
        }
        .padding(16)
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Text("🎁").font(.system(size: 42))
            Text(isEnglish ? "Rewards aren't ready yet" : "المكافآت ليست جاهزة بعد")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BossStyle.textPrimary)
            Text(isEnglish
                 ? "They appear once the event has finished settling."
                 : "تظهر بعد انتهاء احتساب المعركة")
                .font(.system(size: 12))
                .foregroundColor(BossStyle.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: Copy

    private func emblem(_ outcome: BossOutcome) -> String {
        switch outcome {
        case .victory:   return "🏆"
        case .defeat:    return "💀"
        case .cancelled: return "🚫"
        case .unknown:   return "🎁"
        }
    }

    private func headline(_ outcome: BossOutcome) -> String {
        switch outcome {
        case .victory:   return isEnglish ? "Victory!" : "!انتصار"
        case .defeat:    return isEnglish ? "Boss survived" : "نجا الزعيم"
        case .cancelled: return isEnglish ? "Event cancelled" : "أُلغيت المعركة"
        case .unknown:   return isEnglish ? "Event over" : "انتهت المعركة"
        }
    }

    private func subhead(_ rewards: BossRewards) -> String {
        switch rewards.outcome {
        case .victory:
            return isEnglish
                ? "\(rewards.boss_name) defeated · community wins"
                : "هُزم \(rewards.boss_name) · فوز جماعي"
        case .defeat:
            return isEnglish
                ? "\(rewards.boss_name) held out this time"
                : "صمد \(rewards.boss_name) هذه المرة"
        case .cancelled:
            return isEnglish
                ? "This event was called off"
                : "تم إلغاء هذه المعركة"
        case .unknown:
            return rewards.boss_name
        }
    }
}
