//
//  GroupFormView.swift
//  SAAYR
//
//  Making a group and editing one are the same form: a name, an optional line
//  about it, one of four woven covers, and the one decision that matters —
//  whether strangers can find it. The admin screen's "Edit group" row opens
//  this pre-filled, which is what the design asked for.
//

import SwiftUI

struct GroupFormView: View {

    enum Mode: Equatable {
        case create
        case edit(Int)

        var groupID: Int? {
            if case .edit(let id) = self { return id }
            return nil
        }
    }

    let mode: Mode
    @Binding var path: [GroupsRoute]

    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var store: GroupsStore
    @EnvironmentObject var toasts: GroupsToastCenter

    @State private var name = ""
    @State private var detail = ""
    @State private var cover: GroupCover = .palm
    @State private var visibility = 0
    @State private var isSaving = false
    /// The form fills itself from the store once, not on every redraw — the
    /// live stream can update the group underneath while it's being edited.
    @State private var hasFilled = false

    private var copy: GroupsCopy { GroupsCopy(isEnglish: isEnglish) }
    private var isEnglish: Bool { languageManager.currentLanguage == .english }
    private var isPublic: Bool { visibility == 0 }
    private var isEditing: Bool { mode.groupID != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    var body: some View {
        GroupsScreen(title: isEditing ? copy.editGroup : copy.newGroup,
                     onBack: { path.removeLast() }) {
            field(label: copy.groupName, count: "\(name.count)/30") {
                GroupTextField(text: $name, placeholder: copy.groupNameHint, limit: 30)
            }

            field(label: copy.shortDescription, count: "\(detail.count)/120") {
                GroupTextField(text: $detail, placeholder: copy.descriptionHint, limit: 120)
            }

            field(label: copy.cover, count: nil) {
                HStack(spacing: 9) {
                    ForEach(GroupCover.allCases) { option in
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) { cover = option }
                        } label: {
                            SaduCover(cover: option, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(cover == option ? GroupStyle.ink : .clear, lineWidth: 2.5)
                                )
                                .scaleEffect(cover == option ? 1.04 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            field(label: copy.visibility, count: nil) {
                VStack(spacing: 8) {
                    GroupSegmented(titles: [copy.publicOption, copy.privateOption], selection: $visibility)

                    Text(isPublic ? copy.publicHelp : copy.privateHelp)
                        .font(.system(size: 11.5))
                        .foregroundColor(GroupStyle.ink2)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11)
                                        .strokeBorder(GroupStyle.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                )
                        )
                }
            }

            GroupWideButton(title: isSaving ? copy.loading : (isEditing ? copy.saveChanges : copy.createGroup),
                            isEnabled: canSave) {
                save()
            }
            .padding(.top, 4)
        }
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let id = mode.groupID, !hasFilled, let group = store.group(id) else { return }
        hasFilled = true
        name = group.name
        detail = group.detail
        cover = group.cover
        visibility = group.isPublic ? 0 : 1
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespaces)
        isSaving = true

        if let id = mode.groupID {
            store.update(id, name: trimmedName, detail: trimmedDetail,
                         cover: cover, isPublic: isPublic, isEnglish: isEnglish) { ok in
                isSaving = false
                guard ok else { return }   // the store has already surfaced the server's words
                toasts.show(copy.toastSaved)
                path.removeLast()
            }
        } else {
            store.create(name: trimmedName, detail: trimmedDetail,
                         cover: cover, isPublic: isPublic, isEnglish: isEnglish) { group in
                isSaving = false
                guard let group else { return }
                toasts.show(copy.toastCreated(group.name))
                // Straight back to the list, where the new card is waiting at
                // the top — the design's "invite your first member" nudge.
                path.removeAll()
            }
        }
    }

    private func field<Content: View>(
        label: String,
        count: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundColor(GroupStyle.ink)
                Spacer()
                if let count {
                    Text(count)
                        .font(.system(size: 12.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(GroupStyle.ink3)
                }
            }
            content()
        }
        .padding(.bottom, 15)
    }
}

/// A single-line field that stops at the limit rather than letting the counter
/// run past it.
struct GroupTextField: View {
    @Binding var text: String
    let placeholder: String
    let limit: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 14.5))
            .foregroundColor(GroupStyle.ink)
            .focused($isFocused)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(isFocused ? GroupStyle.palm : GroupStyle.line, lineWidth: 1.5)
                    )
            )
            // iOS 16's single-argument form: the deployment target is 16.6.
            .onChange(of: text) { newValue in
                if newValue.count > limit {
                    text = String(newValue.prefix(limit))
                }
            }
    }
}
