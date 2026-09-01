//
//  GroupsView.swift
//  SAAYR
//
//  The Groups home: the crews you're in, and the ones you could join. Opened
//  from the Profile tile. Everything below the root pushes onto one stack so
//  the back gesture always means the same thing, and one `GroupsStore` lives
//  for the whole flow so a change made deep in it is already true on the way
//  back out.
//

import Combine
import SwiftUI

/// Where the stack can go. Preview and feed are the same destination — which
/// one a player gets is decided by their role in the group, not by the route.
enum GroupsRoute: Hashable {
    case group(Int)
    case create
    case edit(Int)
    case admin(Int)
    case requests(Int)
}

/// The confirmation line at the bottom of the screen. Held above the stack so
/// a toast raised in the admin screen survives the pop back to the list.
final class GroupsToastCenter: ObservableObject {
    @Published var message: String?
    private var token = 0

    func show(_ text: String) {
        token += 1
        let mine = token
        withAnimation(.easeOut(duration: 0.2)) { message = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard self.token == mine else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.message = nil }
        }
    }
}

struct GroupsView: View {

    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var store = GroupsStore()
    @StateObject private var toasts = GroupsToastCenter()
    @State private var path: [GroupsRoute] = []
    @State private var tab = 0
    @State private var query = ""
    /// Typing shouldn't hit the search endpoint on every keystroke.
    @State private var searchDebounce: DispatchWorkItem?

    private var copy: GroupsCopy { GroupsCopy(isEnglish: isEnglish) }
    private var isEnglish: Bool { languageManager.currentLanguage == .english }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: GroupsRoute.self) { route in
                    destination(for: route)
                }
        }
        .environmentObject(store)
        .environmentObject(toasts)
        .environment(\.layoutDirection, isEnglish ? .leftToRight : .rightToLeft)
        .overlay(alignment: .bottom) {
            if let message = toasts.message {
                GroupToast(message: message)
                    .padding(.bottom, 34)
            }
        }
        .tint(GroupStyle.palm)
        .onAppear { store.loadMine() }
        // Writes that fail report the server's own words rather than a
        // generic line — it is nearly always the more useful sentence.
        .onReceive(store.$errorMessage.compactMap { $0 }) { message in
            toasts.show(message)
            store.errorMessage = nil
        }
    }

    @ViewBuilder
    private func destination(for route: GroupsRoute) -> some View {
        switch route {
        case .group(let id):    GroupDetailView(groupID: id, path: $path)
        case .create:           GroupFormView(mode: .create, path: $path)
        case .edit(let id):     GroupFormView(mode: .edit(id), path: $path)
        case .admin(let id):    GroupAdminView(groupID: id, path: $path)
        case .requests(let id): GroupRequestsView(groupID: id)
        }
    }

    // MARK: - Root

    private var root: some View {
        GroupsScreen(title: copy.title, onBack: nil, trailing: closeButton) {
            GroupSegmented(titles: [copy.myGroups, copy.discover], selection: $tab)
                .padding(.bottom, 14)

            if tab == 0 {
                myGroups
            } else {
                discover
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: tab) { newTab in
            if newTab == 1 { store.loadDiscover() }
        }
        .refreshable {
            if tab == 0 {
                store.loadMine(force: true)
            } else {
                store.loadDiscover(search: query.isEmpty ? nil : query, force: true)
            }
        }
    }

    private var closeButton: some View {
        GroupCircleButton(systemName: "xmark") { dismiss() }
    }

    // MARK: My groups

    @ViewBuilder
    private var myGroups: some View {
        if store.isLoadingMine && store.mine.isEmpty {
            GroupsLoading(text: copy.loading)
        } else if store.mine.isEmpty {
            GroupLockBox(emoji: store.hasLoadedMine ? "👥" : "📡",
                         message: store.hasLoadedMine ? copy.noGroupsYet : copy.offline)
                .padding(.bottom, 14)
        } else {
            ForEach(store.mine) { group in
                Button {
                    path.append(.group(group.id))
                } label: {
                    GroupCard(group: group, copy: copy, isEnglish: isEnglish, showsRank: true)
                }
                .buttonStyle(GroupPressStyle())
                .padding(.bottom, 12)
            }
        }

        GroupWideButton(title: "＋ " + copy.createNew) { path.append(.create) }
            .padding(.top, 6)
    }

    // MARK: Discover

    @ViewBuilder
    private var discover: some View {
        GroupSearchField(text: $query, placeholder: copy.searchGroups)
            .padding(.bottom, 13)
            .onChange(of: query) { newValue in scheduleSearch(newValue) }

        Text(copy.sortNote)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(GroupStyle.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.bottom, 10)

        if store.isLoadingDiscover && store.discover.isEmpty {
            GroupsLoading(text: copy.loading)
        } else if store.discover.isEmpty {
            GroupLockBox(emoji: store.hasLoadedDiscover ? "🤔" : "📡",
                         message: store.hasLoadedDiscover ? copy.noResults : copy.offline)
        } else {
            ForEach(store.discover) { group in
                Button {
                    path.append(.group(group.id))
                } label: {
                    GroupCard(group: group, copy: copy, isEnglish: isEnglish, showsRank: false)
                }
                .buttonStyle(GroupPressStyle())
                .padding(.bottom, 12)
            }
        }
    }

    /// Search runs on the server — it has to, since Discover only ever holds
    /// one page — so the field waits for a pause in typing before asking.
    private func scheduleSearch(_ text: String) {
        searchDebounce?.cancel()
        let work = DispatchWorkItem {
            let term = text.trimmingCharacters(in: .whitespaces)
            store.loadDiscover(search: term.isEmpty ? nil : term, force: true)
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}

// MARK: - Screen chrome

/// The sand page every Groups screen sits on, with the mock's app bar: a
/// round back button, a left-aligned heavy title, and an optional round
/// action on the far side.
struct GroupsScreen<Content: View, Trailing: View>: View {

    let title: String
    let onBack: (() -> Void)?
    let trailing: Trailing
    @ViewBuilder let content: () -> Content

    init(title: String,
         onBack: (() -> Void)?,
         trailing: Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            GroupStyle.sand.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if let onBack {
                        GroupCircleButton(systemName: "chevron.left", action: onBack)
                    }
                    Text(title)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundColor(GroupStyle.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    trailing
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 10)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        content()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 2)
                    .padding(.bottom, 34)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension GroupsScreen where Trailing == EmptyView {
    init(title: String, onBack: (() -> Void)?, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, onBack: onBack, trailing: EmptyView(), content: content)
    }
}

struct GroupsLoading: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().tint(GroupStyle.palm)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(GroupStyle.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct GroupCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(GroupStyle.ink)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(Color.white).overlay(Circle().stroke(GroupStyle.line, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

/// Cards shrink very slightly when pressed, the way the mock's do.
struct GroupPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GroupSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(GroupStyle.ink3)
            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .foregroundColor(GroupStyle.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(GroupStyle.line, lineWidth: 1))
        )
    }
}

// MARK: - Group card

struct GroupCard: View {
    let group: SaayrGroup
    let copy: GroupsCopy
    let isEnglish: Bool
    /// My Groups shows the weekly rank pill; Discover shows the description
    /// instead, because a rank you don't have yet means nothing.
    let showsRank: Bool

    private var meta: String {
        var parts = [copy.members(group.memberCount)]
        if let relative = GroupsFormat.relative(group.lastActiveAt, isEnglish: isEnglish) {
            parts.append(copy.active(relative))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            SaduCover(cover: group.cover)
                .overlay(alignment: .topLeading) {
                    GroupCoverBadge(text: group.isPublic ? copy.publicBadge : copy.privateBadge)
                        .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    if group.isAdmin {
                        GroupCoverBadge(text: copy.youAreAdmin, isRole: true)
                            .padding(10)
                    }
                }

            if showsRank {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(GroupStyle.ink)
                        Text(meta)
                            .font(.system(size: 12))
                            .foregroundColor(GroupStyle.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let rank = group.weeklyRank {
                        RankPill(rank: rank, copy: copy)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(GroupStyle.ink)
                    Text(copy.members(group.memberCount))
                        .font(.system(size: 12))
                        .foregroundColor(GroupStyle.ink2)
                    if !group.detail.isEmpty {
                        Text(group.detail)
                            .font(.system(size: 12.5))
                            .foregroundColor(GroupStyle.ink2)
                            .lineSpacing(3)
                            .padding(.top, 3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: GroupStyle.radiusLarge))
        .groupCardShadow()
    }
}

/// "14th / THIS WEEK". Bronze when the group is on the podium, falcon
/// otherwise — the mock's one flourish for a rank worth bragging about.
struct RankPill: View {
    let rank: Int
    let copy: GroupsCopy

    private var isPodium: Bool { rank <= 3 }

    var body: some View {
        VStack(spacing: 1) {
            Text(copy.ordinal(rank))
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(isPodium ? GroupStyle.bronze : Color(hex: "#8A6114"))
            Text(copy.thisWeek)
                .font(.system(size: 8.5, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(isPodium ? Color(hex: "#B9793B") : Color(hex: "#B08A3E"))
        }
        .frame(minWidth: 56)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isPodium ? Color(hex: "#F6EADF") : GroupStyle.falconSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isPodium ? Color(hex: "#E2C4A2") : GroupStyle.falconLine, lineWidth: 1)
                )
        )
    }
}
