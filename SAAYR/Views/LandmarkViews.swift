//
//  LandmarkViews.swift
//  SAAYR
//
//  The three faces of an undiscovered landmark: the mystery pin on the map,
//  the card when you tap it, and the reveal when you finally walk into it.
//

import SwiftUI
import CoreLocation
import Kingfisher

// MARK: - Palette

private enum MysteryStyle {
    static let deep    = Color(hex: "#4C1D95")
    static let bright  = Color(hex: "#7C3AED")
    static let glow    = Color(hex: "#A78BFA")
    static let goldXP  = Color(hex: "#D97706")
}

// MARK: - Mystery pin

/// What an unrevealed landmark looks like on the map: no name, no photo, no
/// category — the whole point is that the player doesn't know what it is until
/// they stand in it.
struct MysteryMarkerView: View {

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(MysteryStyle.glow.opacity(0.35))
                .frame(width: 60, height: 60)
                .scaleEffect(pulse ? 1.7 : 1)
                .opacity(pulse ? 0 : 0.7)
                .animation(
                    .easeOut(duration: 2.4).repeatForever(autoreverses: false),
                    value: pulse
                )

            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: [MysteryStyle.bright, MysteryStyle.deep],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(MysteryStyle.glow.opacity(0.9), lineWidth: 2.5)
                )
                .shadow(radius: 6)

            Text("?")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Mystery card

/// Shown instead of the check-in card when a mystery pin is tapped. Says how
/// close the player is and nothing whatsoever about what's there.
struct MysteryLandmarkCard: View {

    let landmark: NearbyLocationResponse
    let userLocation: CLLocationCoordinate2D?
    let isEnglish: Bool
    var onClose: (() -> Void)? = nil

    private var distanceText: String? {
        guard let userLocation else { return nil }
        let metres = LandmarkGeofence.distance(from: userLocation, to: landmark)

        if metres < 1000 {
            let rounded = Int(metres.rounded())
            return isEnglish ? "\(rounded) m away" : "على بعد \(rounded) م"
        }
        let km = String(format: "%.1f", metres / 1000)
        return isEnglish ? "\(km) km away" : "على بعد \(km) كم"
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(
                                colors: [MysteryStyle.bright, MysteryStyle.deep],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 56, height: 56)
                        Text("?")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isEnglish ? "Undiscovered landmark" : "معلم لم يُكتشف بعد")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)

                        Text(isEnglish
                             ? "Step inside to reveal what's here"
                             : "ادخل المكان لكشف ما بداخله")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)

                        if let distanceText {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(distanceText)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(MysteryStyle.bright)
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                    // The reward is deliberately hidden too — revealing the XP
                    // would leak how significant the landmark is.
                    Text(isEnglish ? "Reward hidden until discovered" : "المكافأة مخفية حتى الاكتشاف")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(MysteryStyle.goldXP)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(MysteryStyle.goldXP.opacity(0.08))
                .cornerRadius(12)
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: -4)
            .overlay(alignment: .topTrailing) {
                if let onClose {
                    CardCloseButton(action: onClose)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Discovered landmark card

/// What a landmark shows once it's been found. Deliberately has no check-in
/// button: a landmark is discovered by walking into it, once, and there is
/// nothing left to do at it afterwards — so the card is a plaque, not an
/// action.
struct DiscoveredLandmarkCard: View {

    let landmark: NearbyLocationResponse
    /// Detail from `discovered_landmarks`. Absent for a landmark the player
    /// hasn't found, and for one the server hasn't listed yet.
    let detail: DiscoveredLandmark?
    /// When the player found it. Nil for a landmark discovered before the app
    /// recorded timestamps — the seal then stands on its own.
    let discoveredAt: Date?
    let isEnglish: Bool
    var onClose: (() -> Void)? = nil

    /// The list entry wins: the location's own copy is nulled out by the
    /// backend until the landmark is discovered.
    private var title: String {
        detail?.localizedName(isEnglish: isEnglish) ?? landmark.name
    }

    /// Not rendered for now. The plumbing behind it — `discovered_landmarks`,
    /// the language fallback — is still live, so putting the paragraph back is
    /// a matter of dropping a `Text(description)` into the body.
    private var description: String? {
        detail?.localizedDescription(isEnglish: isEnglish)
            ?? landmark.localizedDescription(isEnglish: isEnglish)
    }

    private var icon: String {
        detail?.icon ?? landmark.icon ?? "🏛️"
    }

    /// Only shown when the backend actually awarded something — a landmark
    /// worth 0 XP shouldn't advertise it.
    private var xpEarned: Int? {
        guard let earned = detail?.xp_earned, earned > 0 else { return nil }
        return earned
    }

    /// "Today" and "Yesterday" for the recent ones, a plain date beyond that —
    /// the exact minute of a discovery stops mattering within a day or two,
    /// and the relative form reads better next to the seal.
    private var discoveredAtText: String? {
        guard let discoveredAt else { return nil }

        let calendar = Calendar.current
        if calendar.isDateInToday(discoveredAt) {
            return isEnglish ? "Discovered today" : "اكتُشف اليوم"
        }
        if calendar.isDateInYesterday(discoveredAt) {
            return isEnglish ? "Discovered yesterday" : "اكتُشف أمس"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en" : "ar")
        formatter.dateFormat = calendar.isDate(discoveredAt, equalTo: Date(), toGranularity: .year)
            ? "d MMM"
            : "d MMM yyyy"
        let day = formatter.string(from: discoveredAt)
        return isEnglish ? "Discovered \(day)" : "اكتُشف \(day)"
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(MysteryStyle.bright.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Text(icon).font(.system(size: 30))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                            // The dated form already says "Discovered", so the
                            // two never double up.
                            Text(discoveredAtText ?? (isEnglish ? "Discovered" : "تم اكتشافه"))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(MysteryStyle.bright)
                    }

                    // Leaves room for the close button in the corner.
                    Spacer(minLength: 34)
                }

                if let xpEarned {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isEnglish ? "+\(xpEarned) XP earned" : "+\(xpEarned) نقطة مكتسبة")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(MysteryStyle.goldXP)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(MysteryStyle.goldXP.opacity(0.08))
                    .cornerRadius(12)
                }
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: -4)
            .overlay(alignment: .topTrailing) {
                if let onClose {
                    CardCloseButton(action: onClose)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Reveal

/// The payoff. Name, details and XP, over the same fog-lift treatment the zone
/// unlock uses so the two moments feel like one game.
struct LandmarkRevealPopup: View {

    let reveal: LandmarkReveal
    let isEnglish: Bool
    let onDismiss: () -> Void

    @State private var revealed = false

    private var landmark: NearbyLocationResponse { reveal.landmark }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            FogLiftParticles()

            VStack(spacing: 22) {
                header

                VStack(spacing: 10) {
                    Text(isEnglish ? "Landmark discovered!" : "!تم اكتشاف معلم")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(MysteryStyle.bright)

                    Text(landmark.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)

                    if let category = landmark.category, !category.isEmpty {
                        Text(category)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                    }

                    if let description = landmark.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.top, 2)
                    }

                    if let address = landmark.address, !address.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 11))
                            Text(address)
                                .font(.system(size: 12))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.gray)
                    }
                }

                xpBadge

                Button(action: onDismiss) {
                    Text(isEnglish ? "Continue" : "متابعة")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(LinearGradient(
                            colors: [MysteryStyle.bright, MysteryStyle.deep],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .cornerRadius(14)
                }
            }
            .padding(28)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
            .padding(.horizontal, 32)
            .scaleEffect(revealed ? 1 : 0.92)
            .opacity(revealed ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { revealed = true }
        }
    }

    /// The landmark's photo if it has one — this is the first time the player
    /// gets to see it — otherwise the mystery mark, now unlocked.
    private var header: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [MysteryStyle.bright, MysteryStyle.deep],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 88, height: 88)

            if let urlString = WebService.resolvedImageUrl(landmark.image_url),
               let url = URL(string: urlString) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipped()
                    .clipShape(Circle())
            } else {
                Text("🏛️").font(.system(size: 40))
            }
        }
        .rotation3DEffect(.degrees(revealed ? 0 : 90), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.1), value: revealed)
    }

    private var xpBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
            Text("+\(reveal.xpAwarded) XP")
                .font(.system(size: 20, weight: .bold))
        }
        .foregroundColor(MysteryStyle.goldXP)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(MysteryStyle.goldXP.opacity(0.1))
        .cornerRadius(14)
    }
}
