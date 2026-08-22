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

    @State private var rewards: BossRewards?
    @State private var isLoading = true
    @State private var celebrate = false

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

    /// Disabled on purpose. The backend has no claim endpoint yet — `claimed`
    /// and `claimed_at` are placeholders that always come back false/null —
    /// and the XP above is already granted regardless. The control is here so
    /// the layout is final and there's an obvious place to wire the action in.
    private func claimButton(_ detail: BossRewardDetail) -> some View {
        let alreadyClaimed = detail.claimed == true

        return VStack(spacing: 6) {
            Text(alreadyClaimed
                 ? (isEnglish ? "🎁 Collected" : "🎁 تم الاستلام")
                 : (isEnglish ? "🎁 Collect rewards" : "🎁 استلم مكافآتك"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(hex: "#1A1206").opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(BossStyle.gold.opacity(0.45)))

            Text(isEnglish ? "Coming soon — your XP is already added" : "قريبًا — نقاطك مضافة بالفعل")
                .font(.system(size: 10))
                .foregroundColor(BossStyle.textDim)
        }
    }

    private var didNotParticipate: some View {
        Text(isEnglish
             ? "You didn't join this one. Next time!"
             : "!لم تشارك هذه المرة. في المرة القادمة")
            .font(.system(size: 13))
            .foregroundColor(BossStyle.textDim)
            .multilineTextAlignment(.center)
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
