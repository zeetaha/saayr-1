//
//  GroupAdminView.swift
//  SAAYR
//
//  What only the admin sees: the three things they can do to the group, the
//  roster with a remove button beside each name, and the one action that ends
//  the group for everybody.
//

import SwiftUI

struct GroupAdminView: View {

    let groupID: Int
    @Binding var path: [GroupsRoute]

    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var store: GroupsStore
    @EnvironmentObject var toasts: GroupsToastCenter

    @State private var showInvite = false
    @State private var showDisband = false

    private var copy: GroupsCopy { GroupsCopy(isEnglish: isEnglish) }
    private var isEnglish: Bool { languageManager.currentLanguage == .english }

    var body: some View {
        Group {
            if let group = store.group(groupID) {
                content(for: group)
            } else {
                GroupsScreen(title: copy.groupAdmin, onBack: { path.removeLast() }) {
                    GroupsLoading(text: copy.loading)
                }
            }
        }
        .onAppear {
            store.loadMembers(groupID)
            store.loadRequests(groupID)
        }
        .sheet(isPresented: $showInvite) {
            GroupInviteSheet(groupID: groupID, copy: copy)
                .environmentObject(store)
                .environmentObject(toasts)
        }
    }

    private func content(for group: SaayrGroup) -> some View {
        GroupsScreen(title: copy.groupAdmin, onBack: { path.removeLast() }) {
            actions(for: group)

            GroupSectionHeader(text: copy.membersSection(group.memberCount))

            let members = store.members[groupID]
            if members == nil {
                GroupsLoading(text: copy.loading)
            } else if members?.isEmpty == true {
                GroupLockBox(emoji: "👤", message: copy.noMembers)
            } else {
                ForEach(members ?? []) { member in
                    memberRow(member, in: group)
                        .padding(.bottom, 8)
                }
            }

            GroupSectionHeader(text: copy.dangerZone)

            GroupWideButton(title: copy.disbandGroup, kind: .danger) { showDisband = true }

            GroupFootnote(text: copy.adminNote)
        }
        .refreshable {
            store.loadMembers(groupID)
            store.loadRequests(groupID)
            store.loadDetail(groupID)
        }
        .confirmationDialog(
            copy.disbandTitle(group.name),
            isPresented: $showDisband,
            titleVisibility: .visible
        ) {
            Button(copy.yesDisband, role: .destructive) {
                store.disband(group.id) { ok in
                    guard ok else { toasts.show(copy.somethingWentWrong); return }
                    toasts.show(copy.toastDisbanded)
                    path.removeAll()
                }
            }
            Button(copy.cancel, role: .cancel) {}
        } message: {
            Text(copy.disbandSub(group.memberCount))
        }
    }

    // MARK: Actions card

    private func actions(for group: SaayrGroup) -> some View {
        VStack(spacing: 0) {
            adminRow(icon: "✏️", title: copy.editGroup, subtitle: copy.editGroupSub) {
                path.append(.edit(group.id))
            }
            Divider().overlay(GroupStyle.divider)

            adminRow(icon: "✉️", title: copy.inviteMembers, subtitle: copy.inviteMembersSub) {
                showInvite = true
            }
            Divider().overlay(GroupStyle.divider)

            adminRow(icon: "📥", title: copy.joinRequests, subtitle: copy.joinRequestsSub,
                     badge: store.requests[groupID]?.count ?? 0) {
                path.append(.requests(group.id))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: GroupStyle.radius))
        .groupCardShadow()
    }

    private func adminRow(
        icon: String,
        title: String,
        subtitle: String,
        badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Text(icon)
                    .font(.system(size: 15))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11).fill(GroupStyle.palmSoft))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(GroupStyle.ink)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(GroupStyle.ink2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(GroupStyle.danger))
                } else {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(GroupStyle.ink3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Member row

    private func memberRow(_ member: GroupMemberDTO, in group: SaayrGroup) -> some View {
        HStack(spacing: 11) {
            GroupPersonAvatar(name: member.name, avatar: member.avatar, userID: member.userId)

            VStack(alignment: .leading, spacing: 1) {
                Text(member.name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(GroupStyle.ink)
                Text(note(for: member))
                    .font(.system(size: 11))
                    .foregroundColor(GroupStyle.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The owner has no remove button beside their own name — leaving
            // is disbanding, and that lives in the danger zone.
            if GroupRole(member.role) != .admin {
                GroupMiniButton(title: copy.remove, kind: .danger) {
                    store.remove(member, from: group.id)
                    toasts.show(copy.toastRemoved(member.name))
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .groupCardShadow()
    }

    /// "Joined 14 May · active today" — assembled here, because the API sends
    /// the instant and the flag, not the sentence.
    private func note(for member: GroupMemberDTO) -> String {
        var parts: [String] = []
        if let day = GroupsFormat.day(member.joinedAt, isEnglish: isEnglish) {
            parts.append(copy.joined(day))
        }
        if member.isActiveToday == true { parts.append(copy.activeToday) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Join requests

struct GroupRequestsView: View {

    let groupID: Int

    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var store: GroupsStore
    @EnvironmentObject var toasts: GroupsToastCenter
    @Environment(\.dismiss) private var dismiss

    private var copy: GroupsCopy { GroupsCopy(isEnglish: isEnglish) }
    private var isEnglish: Bool { languageManager.currentLanguage == .english }

    var body: some View {
        let requests = store.requests[groupID]

        GroupsScreen(title: copy.joinRequests, onBack: { dismiss() }) {
            if requests == nil {
                GroupsLoading(text: copy.loading)
            } else if requests?.isEmpty == true {
                GroupLockBox(emoji: "✅", message: copy.noRequests)
            } else {
                ForEach(requests ?? []) { request in
                    row(request)
                        .padding(.bottom, 8)
                }
            }

            GroupFootnote(text: copy.requestsNote)
        }
        .onAppear { store.loadRequests(groupID) }
        .refreshable { store.loadRequests(groupID) }
    }

    private func row(_ request: JoinRequestDTO) -> some View {
        HStack(spacing: 11) {
            GroupPersonAvatar(name: request.name, avatar: request.avatar, userID: request.userId)

            VStack(alignment: .leading, spacing: 1) {
                Text(request.name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(GroupStyle.ink)
                Text(subtitle(for: request))
                    .font(.system(size: 11))
                    .foregroundColor(GroupStyle.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupMiniButton(title: copy.approve) {
                store.approve(request, in: groupID)
                toasts.show(copy.toastApproved(request.name))
            }
            GroupMiniButton(title: copy.decline, kind: .ghost) {
                store.decline(request, in: groupID)
                toasts.show(copy.toastDeclined(request.name))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .groupCardShadow()
    }

    private func subtitle(for request: JoinRequestDTO) -> String {
        var parts = [copy.level(request.level)]
        if let relative = GroupsFormat.relative(request.requestedAt, isEnglish: isEnglish) {
            parts.append(copy.requested(relative))
        }
        return parts.joined(separator: " · ")
    }
}
