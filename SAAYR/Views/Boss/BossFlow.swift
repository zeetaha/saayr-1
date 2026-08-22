//
//  BossFlow.swift
//  SAAYR
//
//  Both entry points — the home banner and the Challenges card — lead into the
//  same three screens, and the screens hand off to each other (waitlist → battle
//  when it starts, battle → rewards when it ends). This holds that routing in
//  one place so neither host has to know the rules.
//

import SwiftUI

/// Which boss screen is open, if any.
enum BossDestination: Identifiable, Equatable {
    case waitlist(bossID: Int, name: String, startsAt: Date?, imageURL: String?, joined: Bool, interested: Int?)
    case battle(bossID: Int)
    case rewards(bossID: Int)

    var id: String {
        switch self {
        case .waitlist(let id, _, _, _, _, _): return "waitlist-\(id)"
        case .battle(let id):                  return "battle-\(id)"
        case .rewards(let id):                 return "rewards-\(id)"
        }
    }

    var bossID: Int {
        switch self {
        case .waitlist(let id, _, _, _, _, _): return id
        case .battle(let id):                  return id
        case .rewards(let id):                 return id
        }
    }
}

extension BossDestination {

    /// Where tapping the home banner should go.
    static func from(banner: BossHomeBanner) -> BossDestination? {
        guard let bossID = banner.boss_id else { return nil }
        switch banner.state {
        case .live:
            return .battle(bossID: bossID)
        case .scheduled:
            return .waitlist(
                bossID: bossID,
                name: banner.boss_name ?? "",
                startsAt: banner.startsAtDate,
                imageURL: banner.image_url,
                // The banner doesn't say whether the player already signed up;
                // the waitlist stream's snapshot settles it a moment later.
                joined: false,
                interested: nil
            )
        default:
            return nil
        }
    }

    /// Where tapping the Challenges card should go. This one knows more than
    /// the banner does — the challenges payload carries the player's waitlist
    /// state and the interest count, so the screen opens already correct.
    static func from(challenge boss: BossChallengeSummary) -> BossDestination? {
        switch boss.state {
        case .scheduled:
            return .waitlist(
                bossID: boss.boss_id,
                name: boss.boss_name,
                startsAt: boss.startsAtDate,
                imageURL: boss.image_url,
                joined: boss.user_on_waitlist ?? false,
                interested: boss.interested_count
            )
        case .live:
            return .battle(bossID: boss.boss_id)
        case .ended:
            return .rewards(bossID: boss.boss_id)
        default:
            return nil
        }
    }
}

// MARK: - Presenter

/// Presents whichever boss screen `destination` names, and handles the
/// hand-offs between them.
struct BossFlowPresenter: ViewModifier {

    @Binding var destination: BossDestination?
    let isEnglish: Bool

    @EnvironmentObject private var router: AppRouter

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $destination) { destination in
            switch destination {
            case let .waitlist(bossID, name, startsAt, imageURL, joined, interested):
                BossWaitlistView(
                    bossID: bossID,
                    bossName: name,
                    startsAt: startsAt,
                    imageURL: imageURL,
                    initiallyJoined: joined,
                    interestedCount: interested,
                    isEnglish: isEnglish,
                    onClose: { self.destination = nil },
                    // The stream said the fight just started — move the player
                    // straight in rather than making them find it again.
                    onGoLive: { self.destination = .battle(bossID: bossID) }
                )

            case .battle(let bossID):
                BossBattleView(
                    bossID: bossID,
                    isEnglish: isEnglish,
                    onClose: { self.destination = nil },
                    onEnded: { _ in self.destination = .rewards(bossID: bossID) },
                    // Close the battle first, then switch tabs — the map has to
                    // be what's on screen when the player lands, not something
                    // behind a full-screen cover.
                    onCheckInRequested: {
                        self.destination = nil
                        router.goToMapForCheckIn()
                    }
                )

            case .rewards(let bossID):
                BossRewardsView(
                    bossID: bossID,
                    isEnglish: isEnglish,
                    onClose: { self.destination = nil }
                )
            }
        }
    }
}

extension View {
    /// Attach once per host screen that can open the boss.
    func bossFlow(destination: Binding<BossDestination?>, isEnglish: Bool) -> some View {
        modifier(BossFlowPresenter(destination: destination, isEnglish: isEnglish))
    }
}
