//
//  GroupsStyle.swift
//  SAAYR
//
//  The Groups palette and the pieces every Groups screen reuses. Sand and
//  palm rather than the profile screen's violet: Groups is its own place,
//  and the design review pinned these tokens by name.
//

import SwiftUI

enum GroupStyle {
    static let sand       = Color(hex: "#F5EFE4")
    static let card       = Color.white
    static let line       = Color(hex: "#E8DFCE")
    static let palm       = Color(hex: "#0E6B45")
    static let palmDeep   = Color(hex: "#0A4E33")
    static let palmSoft   = Color(hex: "#E3EFE7")
    static let falcon     = Color(hex: "#E8A33D")
    static let falconSoft = Color(hex: "#FBF0DC")
    static let falconLine = Color(hex: "#F0DBB4")
    static let ink        = Color(hex: "#1F2A24")
    static let ink2       = Color(hex: "#5B675F")
    static let ink3       = Color(hex: "#93A099")
    static let danger     = Color(hex: "#C2452D")
    static let dangerSoft = Color(hex: "#FBE9E4")
    static let gold       = Color(hex: "#D9A422")
    static let silver     = Color(hex: "#9AA5AE")
    static let bronze     = Color(hex: "#B9793B")
    static let divider    = Color(hex: "#F1EBDD")

    static let radius: CGFloat = 16
    static let radiusLarge: CGFloat = 22
}

extension View {
    /// The one card shadow the design uses — soft and doubled, so cards lift
    /// off the sand without a visible edge.
    func groupCardShadow() -> some View {
        shadow(color: GroupStyle.ink.opacity(0.06), radius: 1, x: 0, y: 1)
            .shadow(color: GroupStyle.ink.opacity(0.07), radius: 10, x: 0, y: 6)
    }
}

// MARK: - Sadu cover

/// The woven band that stands in for a group photo. Diagonal two-tone stripes
/// with a dashed selvedge along the bottom, drawn rather than shipped as art
/// so any of the four reads crisply at any height.
struct SaduCover: View {
    let cover: GroupCover
    var height: CGFloat = 86

    var body: some View {
        Canvas { context, size in
            let (light, dark) = cover.stripes
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark))

            let band: CGFloat = cover.leansRight ? 12 : 14
            let step = band * 2
            // Stripes are drawn as rotated rectangles wide enough to cover the
            // diagonal, so nothing has to be clipped by hand.
            let reach = size.width + size.height
            var offset: CGFloat = -reach
            while offset < reach {
                var path = Path()
                if cover.leansRight {
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset + band, y: 0))
                    path.addLine(to: CGPoint(x: offset + band - size.height, y: size.height))
                    path.addLine(to: CGPoint(x: offset - size.height, y: size.height))
                } else {
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset + band, y: 0))
                    path.addLine(to: CGPoint(x: offset + band + size.height, y: size.height))
                    path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                }
                path.closeSubpath()
                context.fill(path, with: .color(light))
                offset += step
            }

            // The selvedge: a dashed white edge along the bottom.
            let edge: CGFloat = 10
            var x: CGFloat = 8
            while x < size.width {
                context.fill(
                    Path(CGRect(x: x, y: size.height - edge, width: 2, height: edge)),
                    with: .color(.white.opacity(0.35))
                )
                x += 16
            }
        }
        .frame(height: height)
    }
}

// MARK: - Small parts

/// A member's circle. Initials, not photos — same reason as the covers.
struct GroupAvatar: View {
    let initial: String
    let tint: Color
    var size: CGFloat = 38

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.37, weight: .heavy))
                    .foregroundColor(.white)
            )
    }
}

/// A person from the API: their photo when they have one, and the same
/// coloured initial as the mock when they don't. The colour is derived from
/// the user id so one player looks the same everywhere in the app.
struct GroupPersonAvatar: View {
    let name: String
    let avatar: String?
    let userID: Int
    var size: CGFloat = 38

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        Group {
            if let url = WebService.resolvedImageUrl(avatar).flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    GroupAvatar(initial: initial, tint: GroupStyle.tint(for: userID), size: size)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                GroupAvatar(initial: initial, tint: GroupStyle.tint(for: userID), size: size)
            }
        }
    }
}

extension GroupStyle {
    /// The mock's cast of avatar colours, in its order.
    static let avatarTints: [Color] = [
        GroupStyle.palmDeep,
        GroupStyle.gold,
        Color(hex: "#3E6E8C"),
        GroupStyle.bronze,
        Color(hex: "#7A5C3E"),
        GroupStyle.danger,
        GroupStyle.palm,
        Color(hex: "#5E4630")
    ]

    static func tint(for id: Int) -> Color {
        avatarTints[abs(id) % avatarTints.count]
    }
}

/// A pill floating on a cover — "🔒 Private", "You're the admin".
struct GroupCoverBadge: View {
    let text: String
    var isRole = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundColor(isRole ? .white : GroupStyle.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isRole ? GroupStyle.ink.opacity(0.45) : Color.white.opacity(0.92))
            )
    }
}

enum GroupButtonKind {
    case palm, ghost, danger

    var background: Color {
        switch self {
        case .palm:   return GroupStyle.palm
        case .ghost:  return .white
        case .danger: return GroupStyle.dangerSoft
        }
    }

    var foreground: Color {
        switch self {
        case .palm:   return .white
        case .ghost:  return GroupStyle.ink
        case .danger: return GroupStyle.danger
        }
    }
}

/// The full-width action button. One shape for every screen's primary move.
struct GroupWideButton: View {
    let title: String
    var kind: GroupButtonKind = .palm
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(kind.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(kind.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(kind == .ghost ? GroupStyle.line : .clear, lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// The small pill used inside rows — Approve, Decline, Remove, Invite.
struct GroupMiniButton: View {
    let title: String
    var kind: GroupButtonKind = .palm
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(kind.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(kind.background)
                        .overlay(Capsule().stroke(kind == .ghost ? GroupStyle.line : .clear, lineWidth: 1.5))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

/// The dashed box that stands in for content the player can't see yet, or
/// content that isn't there at all.
struct GroupLockBox: View {
    let emoji: String
    let message: String

    var body: some View {
        VStack(spacing: 7) {
            Text(emoji).font(.system(size: 26))
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(GroupStyle.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: GroupStyle.radius)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: GroupStyle.radius)
                        .strokeBorder(GroupStyle.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
        )
    }
}

/// A quiet centred footnote — the rules the design spells out in place rather
/// than hiding in a help screen.
struct GroupFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundColor(GroupStyle.ink3)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 10)
    }
}

struct GroupSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy))
            .tracking(0.4)
            .foregroundColor(GroupStyle.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

/// The segmented control at the top of the list screen, and again in the
/// create form for visibility.
struct GroupSegmented: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = index }
                } label: {
                    Text(titles[index])
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(selection == index ? GroupStyle.ink : GroupStyle.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selection == index ? Color.white : .clear)
                                .shadow(color: selection == index ? GroupStyle.ink.opacity(0.1) : .clear,
                                        radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#EDE6D6")))
    }
}

/// The bottom toast the mock uses to confirm every action. Kept local rather
/// than reusing `TopToast`: these are quiet confirmations that belong near
/// the thumb, not warnings that belong under the status bar.
struct GroupToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 13).fill(GroupStyle.ink))
            .padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
