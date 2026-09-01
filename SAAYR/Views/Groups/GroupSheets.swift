//
//  GroupSheets.swift
//  SAAYR
//
//  The two sheets the Groups flow raises: reporting a group, and getting
//  people into one.
//

import SwiftUI
import UIKit

// MARK: - Report

struct GroupReportSheet: View {

    let copy: GroupsCopy
    let onSend: (GroupReportReason) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: GroupReportReason?

    /// The wire value is a slug; only the label is translated.
    private func label(for reason: GroupReportReason) -> String {
        switch reason {
        case .inappropriateName:  return copy.reasonName
        case .inappropriatePhoto: return copy.reasonPhoto
        case .other:              return copy.reasonOther
        }
    }

    var body: some View {
        GroupSheetBody(title: copy.reportTitle, subtitle: copy.reportSub) {
            VStack(spacing: 0) {
                ForEach(GroupReportReason.allCases) { option in
                    Button {
                        reason = option
                    } label: {
                        HStack(spacing: 10) {
                            Text(label(for: option))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(reason == option ? GroupStyle.palmDeep : GroupStyle.ink)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(GroupStyle.palm)
                                .opacity(reason == option ? 1 : 0)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option != GroupReportReason.allCases.last {
                        Divider().overlay(GroupStyle.divider)
                    }
                }
            }

            GroupWideButton(title: copy.sendReport, isEnabled: reason != nil) {
                if let reason { onSend(reason) }
                dismiss()
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - Invite

struct GroupInviteSheet: View {

    let groupID: Int
    let copy: GroupsCopy

    @EnvironmentObject var store: GroupsStore
    @EnvironmentObject var toasts: GroupsToastCenter
    @State private var query = ""
    @State private var searchDebounce: DispatchWorkItem?

    private var link: InviteLinkDTO? { store.inviteLinks[groupID] }

    var body: some View {
        GroupSheetBody(title: copy.inviteMembers, subtitle: copy.inviteSub) {
            GroupSearchField(text: $query, placeholder: copy.searchUsername)
                .padding(.bottom, 8)
                .onChange(of: query) { newValue in scheduleSearch(newValue) }

            results

            Text(copy.orByLink)
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.4)
                .foregroundColor(GroupStyle.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .padding(.horizontal, 2)

            if let link {
                HStack(spacing: 9) {
                    Text(link.url)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(GroupStyle.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // The link is a URL, so it reads left-to-right even
                        // when the sheet around it is mirrored.
                        .environment(\.layoutDirection, .leftToRight)

                    GroupMiniButton(title: copy.copy) {
                        UIPasteboard.general.string = link.url
                        toasts.show(copy.toastLinkCopied)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 11).fill(GroupStyle.sand))

                if let expires = GroupsFormat.relative(link.expiresAt, isEnglish: copy.isEnglish) {
                    Text(copy.expires(expires))
                        .font(.system(size: 11.5))
                        .foregroundColor(GroupStyle.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .padding(.horizontal, 2)
                }
            }

            Text(copy.inviteLinkNote)
                .font(.system(size: 11.5))
                .foregroundColor(GroupStyle.ink3)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.horizontal, 2)

            GroupWideButton(title: copy.generateNewLink, kind: .ghost) {
                store.regenerateInvite(groupID)
                toasts.show(copy.toastNewLink)
            }
            .padding(.top, 12)
        }
        .onAppear {
            // A group that has never issued a link answers 404 here; the
            // sheet simply shows the generate button instead.
            store.loadInviteLink(groupID)
            store.inviteResults = []
        }
    }

    @ViewBuilder
    private var results: some View {
        if store.isSearchingInvites && store.inviteResults.isEmpty {
            GroupsLoading(text: copy.loading)
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty && store.inviteResults.isEmpty {
            Text(copy.noPlayer)
                .font(.system(size: 11.5))
                .foregroundColor(GroupStyle.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
        } else {
            ForEach(store.inviteResults) { person in
                inviteeRow(person)
                    .padding(.bottom, 8)
            }
        }
    }

    private func inviteeRow(_ person: InviteSearchResultDTO) -> some View {
        let done = person.alreadyInvited == true
        return HStack(spacing: 11) {
            GroupPersonAvatar(name: person.name, avatar: nil, userID: person.userId)

            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(GroupStyle.ink)
                Text(subtitle(for: person))
                    .font(.system(size: 11))
                    .foregroundColor(GroupStyle.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupMiniButton(title: done ? copy.sent : copy.invite,
                            kind: done ? .ghost : .palm,
                            isEnabled: !done) {
                store.invite(person, in: groupID)
                toasts.show(copy.toastInvited)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(GroupStyle.line, lineWidth: 1))
        )
    }

    private func subtitle(for person: InviteSearchResultDTO) -> String {
        var parts: [String] = []
        if let username = person.username, !username.isEmpty { parts.append("@\(username)") }
        parts.append(copy.level(person.level))
        return parts.joined(separator: " · ")
    }

    private func scheduleSearch(_ text: String) {
        searchDebounce?.cancel()
        let work = DispatchWorkItem {
            store.searchInvites(groupID, query: text.trimmingCharacters(in: .whitespaces))
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}

// MARK: - Shared sheet shell

/// A title, a line of context, then whatever the sheet is for — sized to its
/// content so a short sheet doesn't stretch to half the screen.
struct GroupSheetBody<Content: View>: View {

    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(GroupStyle.ink)
                    .padding(.bottom, 4)

                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundColor(GroupStyle.ink2)
                    .lineSpacing(4)
                    .padding(.bottom, 14)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(Color.white.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
