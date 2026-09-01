//
//  GroupDetailView.swift
//  SAAYR
//
//  One group, from either side of the door. A player who hasn't joined sees
//  the header, a join button and a locked box; a member sees the feed and the
//  group's private weekly board.
//
//  The screen hydrates over REST and then holds `/live` open for as long as
//  it is showing, so a check-in by someone else lands without a refresh.
//

import SwiftUI

struct GroupDetailView: View {

    let groupID: Int
    @Binding var path: [GroupsRoute]

    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var store: GroupsStore
    @EnvironmentObject var toasts: GroupsToastCenter

    @State private var tab = 0
    @State private var showReport = false
    @State private var showLeaveConfirm = false

    private var copy: GroupsCopy { GroupsCopy(isEnglish: isEnglish) }
    private var isEnglish: Bool { languageManager.currentLanguage == .english }

    var body: some View {
        Group {
            if let group = store.group(groupID) {
                content(for: group)
            } else {
                GroupsScreen(title: copy.title, onBack: { path.removeLast() }) {
                    GroupsLoading(text: copy.loading)
                }
            }
        }
        .onAppear { store.loadDetail(groupID) }
        .onDisappear { store.closeLive() }
        .sheet(isPresented: $showReport) {
            GroupReportSheet(copy: copy) { reason in
                store.report(groupID, reason: reason) { ok in
                    toasts.show(ok ? copy.toastReported : copy.somethingWentWrong)
                }
            }
        }
    }

    /// Only a member has a feed, a board or a stream to open — asking for
    /// them from the preview would just collect 403s.
    private func openJoinedContent() {
        store.loadFeed(groupID)
        store.loadLeaderboard(groupID)
        store.openLive(groupID)
    }

    @ViewBuilder
    private func content(for group: SaayrGroup) -> some View {
        GroupsScreen(
            title: group.isJoined ? group.name : copy.preview,
            onBack: { path.removeLast() },
            trailing: gear(for: group)
        ) {
            header(for: group)

            if group.isJoined {
                joinedBody(for: group)
            } else {
                previewBody(for: group)
            }
        }
        // The feed, the board and the stream are asked for as soon as there
        // is a group and the player is in it — which can be on first draw, or
        // later, when a pending request is approved while the screen is open.
        .onAppear { if group.isJoined { openJoinedContent() } }
        .onChange(of: group.isJoined) { joined in
            if joined { openJoinedContent() }
        }
        .refreshable {
            store.loadDetail(groupID)
            if group.isJoined {
                store.loadFeed(groupID)
                store.loadLeaderboard(groupID)
            }
        }
        .alert(copy.leaveGroup, isPresented: $showLeaveConfirm) {
            Button(copy.leaveGroup, role: .destructive) {
                store.leave(group.id) { ok in
                    guard ok else { toasts.show(copy.somethingWentWrong); return }
                    toasts.show(copy.toastLeft(group.name))
                    path.removeLast()
                }
            }
            Button(copy.cancel, role: .cancel) {}
        }
    }

    @ViewBuilder
    private func gear(for group: SaayrGroup) -> some View {
        if group.isAdmin {
            GroupCircleButton(systemName: "gearshape.fill") {
                path.append(.admin(group.id))
            }
        }
    }

    // MARK: - Header

    private func header(for group: SaayrGroup) -> some View {
        VStack(spacing: 0) {
            SaduCover(cover: group.cover, height: 104)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(GroupStyle.ink)

                Text(metaLine(for: group))
                    .font(.system(size: 12.5))
                    .foregroundColor(GroupStyle.ink2)

                if !group.detail.isEmpty {
                    Text(group.detail)
                        .font(.system(size: 13))
                        .foregroundColor(GroupStyle.ink2)
                        .lineSpacing(4)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.top, 13)
            .padding(.bottom, 15)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: GroupStyle.radiusLarge))
        .groupCardShadow()
        .padding(.bottom, 13)
    }

    private func metaLine(for group: SaayrGroup) -> String {
        var parts = [group.isPublic ? copy.publicBadge : copy.privateBadge,
                     copy.members(group.memberCount)]
        if group.isAdmin {
            parts.append(copy.youAreAdmin)
        } else if group.role == .member,
                  let joined = GroupsFormat.relative(group.joinedAt, isEnglish: isEnglish) {
            parts.append(copy.joined(joined))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Not a member

    @ViewBuilder
    private func previewBody(for group: SaayrGroup) -> some View {
        if group.role == .pending {
            GroupWideButton(title: copy.requestPending, kind: .ghost, isEnabled: false) {}
        } else {
            GroupWideButton(title: copy.requestToJoin) {
                store.requestJoin(group.id, isEnglish: isEnglish) { ok in
                    if ok { toasts.show(copy.toastRequestSent) }
                }
            }
        }

        GroupLockBox(emoji: "🔒", message: copy.previewLocked)
            .padding(.top, 14)

        GroupWideButton(title: copy.reportGroup, kind: .ghost) { showReport = true }
            .padding(.top, 14)
    }

    // MARK: - Member

    @ViewBuilder
    private func joinedBody(for group: SaayrGroup) -> some View {
        GroupTabs(titles: [copy.feed, copy.leaderboard], selection: $tab)
            .padding(.bottom, 13)

        if tab == 0 {
            feed(for: group)
        } else {
            leaderboard(for: group)
        }

        if group.role == .member {
            GroupWideButton(title: copy.reportGroup, kind: .ghost) { showReport = true }
                .padding(.top, 10)
            GroupWideButton(title: copy.leaveGroup, kind: .danger) { showLeaveConfirm = true }
                .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func feed(for group: SaayrGroup) -> some View {
        let events = store.feeds[group.id]

        if events == nil {
            GroupsLoading(text: copy.loading)
        } else if events?.isEmpty == true {
            GroupLockBox(emoji: "🌱", message: copy.emptyFeed)
        } else {
            ForEach(events ?? []) { event in
                GroupFeedRow(event: event, isEnglish: isEnglish) { reaction in
                    store.react(reaction, on: event.id, in: group.id)
                }
                .padding(.bottom, 9)
                .onAppear {
                    // The last row asks for the next page; the store knows
                    // when there isn't one.
                    if event.id == events?.last?.id { store.loadMoreFeed(group.id) }
                }
            }
        }

        GroupFootnote(text: copy.feedNote)
    }

    @ViewBuilder
    private func leaderboard(for group: SaayrGroup) -> some View {
        if let board = store.boards[group.id] {
            HStack(spacing: 8) {
                Text("⏳")
                Text(copy.resetsIn(GroupsFormat.daysLeft(until: board.resetsAt)))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Color(hex: "#8A6114"))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(GroupStyle.falconSoft)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(GroupStyle.falconLine, lineWidth: 1))
            )
            .padding(.bottom, 12)

            // The server sends the top of the board plus the player's own row
            // separately, so a rank in the eighties still fits on one screen.
            let rows = board.rows.filter { $0.isMe != true }
            let me = board.me ?? board.rows.first { $0.isMe == true }
            let needsGap = (me?.rank ?? 0) > (rows.last?.rank ?? 0) + 1

            ForEach(rows) { row in
                GroupLeaderRowView(row: row, copy: copy)
                    .padding(.bottom, 8)
            }

            if let me {
                if needsGap {
                    Text("···")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(3)
                        .foregroundColor(GroupStyle.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                }
                GroupLeaderRowView(row: me, copy: copy, isMe: true)
                    .padding(.bottom, 8)
            }

            GroupFootnote(text: copy.boardNote)
        } else {
            GroupsLoading(text: copy.loading)
        }
    }
}

// MARK: - Tabs

/// The underlined pair inside a group. Distinct from `GroupSegmented` on
/// purpose: that one switches lists, this one switches views of one group.
struct GroupTabs: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 22) {
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = index }
                } label: {
                    Text(titles[index])
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(selection == index ? GroupStyle.palmDeep : GroupStyle.ink3)
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selection == index ? GroupStyle.palm : .clear)
                                .frame(height: 2.5)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(GroupStyle.line).frame(height: 1.5)
        }
    }
}

// MARK: - Feed

struct GroupFeedRow: View {
    let event: FeedEventDTO
    let isEnglish: Bool
    let onReact: (GroupReaction) -> Void

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                GroupPersonAvatar(name: event.actorName ?? "?",
                                  avatar: nil,
                                  userID: event.actorUserId ?? event.id)

                VStack(alignment: .leading, spacing: 2) {
                    // The server composes this sentence, in English. Rendered
                    // as markdown so the emphasis it sends survives.
                    Text(.init(event.text))
                        .font(.system(size: 13.5))
                        .foregroundColor(GroupStyle.ink)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        // Left-to-right regardless of the surrounding layout:
                        // the sentence is English even in the Arabic UI.
                        .environment(\.layoutDirection, .leftToRight)

                    if let time = GroupsFormat.relative(event.createdAt, isEnglish: isEnglish) {
                        Text(time)
                            .font(.system(size: 11))
                            .foregroundColor(GroupStyle.ink3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(event.icon)
                    .font(.system(size: 17))
                    .padding(.top, 2)
            }

            HStack(spacing: 6) {
                ForEach(GroupReaction.allCases) { reaction in
                    ReactionChip(reaction: reaction,
                                 count: event.reactions.count(reaction),
                                 isMine: event.reactions.mine == reaction) {
                        onReact(reaction)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: GroupStyle.radius))
        .groupCardShadow()
    }
}

struct ReactionChip: View {
    let reaction: GroupReaction
    let count: Int
    let isMine: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(reaction.emoji).font(.system(size: 12.5))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(isMine ? GroupStyle.palmDeep : GroupStyle.ink2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isMine ? GroupStyle.palmSoft : GroupStyle.sand)
                    .overlay(Capsule().stroke(isMine ? GroupStyle.palm : .clear, lineWidth: 1.5))
            )
        }
        .buttonStyle(GroupPressStyle())
    }
}

// MARK: - Leaderboard row

struct GroupLeaderRowView: View {
    let row: LeaderboardRowDTO
    let copy: GroupsCopy
    var isMe: Bool = false

    private var mine: Bool { isMe || row.isMe == true }

    private var rankColor: Color {
        switch row.rank {
        case 1:  return GroupStyle.gold
        case 2:  return GroupStyle.silver
        case 3:  return GroupStyle.bronze
        default: return GroupStyle.ink3
        }
    }

    private var border: Color {
        if mine { return GroupStyle.palm }
        switch row.rank {
        case 1:  return Color(hex: "#EBCB77")
        case 2:  return Color(hex: "#D6DDE2")
        case 3:  return Color(hex: "#E2C4A2")
        default: return .clear
        }
    }

    private var fill: Color {
        if mine { return GroupStyle.palmSoft }
        return row.rank == 1 ? Color(hex: "#FFFDF4") : .white
    }

    var body: some View {
        HStack(spacing: 11) {
            Text("\(row.rank)")
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(rankColor)
                .frame(width: 26)

            GroupPersonAvatar(name: row.name, avatar: row.avatar, userID: row.userId)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(GroupStyle.ink)
                Text(copy.level(row.level))
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.3)
                    .foregroundColor(GroupStyle.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                Text("\(row.points)")
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundColor(GroupStyle.palmDeep)
                Text(copy.points)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(GroupStyle.ink3)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 1.5))
        )
        .groupCardShadow()
    }
}
