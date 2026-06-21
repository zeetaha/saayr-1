import SwiftUI
import Kingfisher

struct HomeView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager
    @State private var showPVPPayment = false
    @State private var showActiveMatch = false
    @State private var activeMatchForResume: FullMatchData? = nil
    @State private var isCheckingPVP = false
    @State private var particles: [Particle] = []
    @State private var pollTimer: Timer?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(hex: "#F0F9FF"), Color(hex: "#FFFFFF"), Color(hex: "#FFF7ED")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Oud smoke ambient layer — visible on Fridays in Riyadh time
                if isFridayInRiyadh {
                    OudSmokeOverlay()
                }

                // Floating particles
                ForEach(particles) { particle in
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: particle.size, height: particle.size)
                        .offset(x: particle.x, y: particle.y)
                        .blur(radius: 0.2)
                }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Center content and limit max width for iPad
                        VStack(spacing: 24) {
                            if userManager.isLoadingData {
                                HomeSkeletonView()
                            } else {
                            greetingSection
                            PetDisplayCard(
                                petName: userManager.userData.petName ?? "",
                                level: userManager.userData.level ?? 0,
                                stage: userManager.userData.petStage,
                                xpProgress: userManager.userData.current_percentage ?? 0.0,
                                progessText: userManager.userData.text_of_progress,
                                gifUrl: userManager.userData.gif_url
                            )
                            .padding(.horizontal)

                            statsGrid
//                           PVPBattleCard(isLoading: isCheckingPVP) {
//                               guard userManager.userData.pvp_enabled, !isCheckingPVP else { return }
//                               isCheckingPVP = true
//                               ServiceModel.shared.fetchMyMatchFull { result in
//                                   DispatchQueue.main.async {
//                                       isCheckingPVP = false
//                                       if case .success(let response) = result,
//                                          let match = response.data,
//                                          match.status == "in_progress" {
//                                           activeMatchForResume = match
//                                           showActiveMatch = true
//                                       } else {
//                                           showPVPPayment = true
//                                       }
//                                   }
//                               }
//                           }
                            leaderboardSection
                            } // end if isLoadingData
                        }
                        .frame(maxWidth: 700) // Limit width on iPad
                        .padding(.horizontal)
                        
                        Spacer(minLength: 100)
                    }
                    .frame(maxWidth: .infinity) // Center content on wider screens
                }
            }
            .navigationBarHidden(true)
            
            .fullScreenCover(isPresented: $showPVPPayment) {
                PVPPaymentDialog(isPresented: $showPVPPayment)
                    .environmentObject(languageManager)
                    .environmentObject(userManager)
            }
            .fullScreenCover(isPresented: $showActiveMatch) {
                if let match = activeMatchForResume {
                    ActiveMatchView(
                        isPresented: $showActiveMatch,
                        initialMatch: match
                    )
                    .environmentObject(userManager)
                }
            }
            .onAppear {
                generateParticles()
                userManager.fetchAllUserData()
                pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                    userManager.fetchMyMatch()
                }
            }
            .onDisappear {
                pollTimer?.invalidate()
                pollTimer = nil
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Fix iPad NavigationView
    }
    
    // MARK: - Sections
    
    private var greetingSection: some View {
        HStack {
            VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 4) {
                Text(languageManager.currentLanguage == .english
                        ? (userManager.userData.greeting_en ?? "Welcome back,")
                        : (userManager.userData.greeting_ar ?? "مرحبًا بك مجددًا،"))
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                Text(userManager.userData.fullName ?? "".components(separatedBy: " ").first! + " 👋")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
            }
            Spacer()
            
            // Points Badge
//            HStack(spacing: 6) {
//                Image(systemName: "star.fill")
//                    .resizable()
//                    .scaledToFit()
//                    .frame(width: 18, height: 18)
//                    .foregroundColor(.white)
//                
//                Text("\(userManager.userData.points)")
//                    .font(.system(size: 16, weight: .bold))
//                    .foregroundColor(.white)
//            }
//            .padding(.horizontal, 16)
//            .padding(.vertical, 10)
//            .background(
//                RoundedRectangle(cornerRadius: 20)
//                    .fill(userManager.stageColor)
//                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
//            )
        }
        .padding(.top, 16)
    }
    
    private var statsGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        
        return LazyVGrid(columns: columns, spacing: 12) {
            StatCard(
                icon: "star.fill",
                label: languageManager.currentLanguage == .english ? "Total XP" : "إجمالي XP",
                value: "\(userManager.userData.totalXP)",
                gradient: [Color.blue, Color.cyan]
            )
            StatCard(
                icon: "map.fill",
                label: languageManager.currentLanguage == .english ? "Total Points" : "مجموع النقاط",
                value: userManager.userData.petType ?? "0",
                gradient: [Color.green, Color.teal]
            )
            StatCard(
                icon: "bolt.fill",
                label: languageManager.currentLanguage == .english ? "Level" : "المستوى",
                value: "\(userManager.userData.userLevel ?? 0)",
                gradient: [Color.purple, Color.pink]
            )
        }
        .padding(.vertical)
    }

    
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(languageManager.currentLanguage == .english ? "Leaderboard" : "قائمة المتصدرين")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
                NavigationLink(destination: LeaderboardFullView()) {
                    Text(languageManager.currentLanguage == .english ? "View All" : "عرض الكل")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Text("Riyadh")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
            }

            VStack(spacing: 10) {
                ForEach(userManager.leaderboardUsers) { user in
                    LeaderboardCard(user: .constant(user), rank: user.rank)
                }
            }
        }
    }
    
    // Returns true all day Friday, using Riyadh time regardless of device timezone
    private var isFridayInRiyadh: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        return cal.component(.weekday, from: Date()) == 6  // 6 = Friday
        
    }

    // MARK: - Particles
    func generateParticles() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        particles = (0..<15).map { _ in
            Particle(
                x: CGFloat.random(in: -screenWidth/2...screenWidth/2),
                y: CGFloat.random(in: -screenHeight/2...screenHeight/2),
                size: CGFloat.random(in: 20...60)
            )
        }
    }
}

// MARK: - Models
struct Particle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
}

struct LeaderboardUser: Identifiable {
    let id: Int
    let rank: Int
    let name: String
    let level: Int
    let points: Int
    let avatar: String?
    let bgColor: Color
}


// MARK: - Components
struct TextButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let gradient: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundColor(.white)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
            )
        }
    }
}

struct PVPBattleCard: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack() {
                // Icon with red background
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.94, green: 0.27, blue: 0.27)) // #EF4444
                        .frame(width: 52, height: 52)
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }

                // Texts
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.currentLanguage == .english ? "PVP Battle" : "معركة PVP")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text(userManager.userData.pvp_message)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(20)
            .background(
                userManager.userData.pvp_enabled  ? RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.07, green: 0.09, blue: 0.15)) : RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.7))
            )
        }
        .buttonStyle(PlainButtonStyle()) // Remove default button styling
    }
}


// Color extension for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - PetDisplayCard
struct PetDisplayCard: View {
    let petName: String
    let level: Int?
    let stage: PetStage
    let xpProgress: Double
    let progessText: String
    var gifUrl: String? = nil

    @EnvironmentObject var languageManager: LanguageManager

    var body: some View {
        VStack(spacing: 16) {
            // Circular progress ring with pet GIF or fallback emoji
            ZStack {
                CircularProgressRing(
                    progress: xpProgress,
                    size: 120,
                    lineWidth: 8
                )
                if let urlStr = gifUrl, let url = URL(string: urlStr) {
                    KFAnimatedImage(url)
                        .configure { $0.framePreloadCount = 3 }
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                        .clipShape(Circle())
                }
            }
            
            // Pet Name & Level
            VStack(spacing: 4) {
                Text(petName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
                Text("\(languageManager.currentLanguage == .english ? "Level" : "المستوى") \(level ?? 0)")
                    .font(.system(size: 16))
                    .foregroundColor(.black.opacity(0.8))
            }
            
            // XP Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(progessText)")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.9))
                    Spacer()
                    Text("\(Int(xpProgress))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [Color.blue.opacity(0.7), Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing))
                            .frame(width: geometry.size.width * (xpProgress/100), height: 12)
                    }
                }
                .frame(height: 12)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 10)
        )
    }
}

// MARK: - StatCard
struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let gradient: [Color]
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.black)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.black.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 10)
        )
    }
}

// MARK: - LeaderboardCard
struct LeaderboardCard: View {
    @Binding var user: LeaderboardUser
    var rank: Int = 0

    private var rankColor: Color {
        switch rank {
        case 1: return Color(hex: "#F59E0B")
        case 2: return Color(hex: "#9CA3AF")
        case 3: return Color(hex: "#D97706")
        default: return Color(hex: "#6366F1")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(rank <= 3 ? ["🥇","🥈","🥉"][rank - 1] : "#\(rank)")
                    .font(.system(size: rank <= 3 ? 18 : 12, weight: .bold))
                    .foregroundColor(rankColor)
            }

            // Avatar
            ZStack {
                Circle()
                    .fill(user.bgColor)
                    .frame(width: 44, height: 44)
                if let urlStr = user.avatar, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                }
            }

            // Name + Level
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                Text("Level \(user.level)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            Spacer()

            // Points
            Text("\(user.points) pts")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(hex: "#6366F1")))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}


// MARK: - CircularProgressRing
struct CircularProgressRing: View {
    let progress: Double // 0 → 1
    let size: CGFloat
    let lineWidth: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [Color.blue, Color.cyan]), center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - ActivePVPBanner
struct ActivePVPBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Active PVP Battle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("Tap to return to battle")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.orange, Color(red: 1, green: 0.45, blue: 0)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .shadow(color: Color.orange.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.5

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0),   location: 0),
                            .init(color: Color.white.opacity(0.55), location: 0.45),
                            .init(color: Color.white.opacity(0),   location: 1)
                        ],
                        startPoint: UnitPoint(x: phase,     y: 0.5),
                        endPoint:   UnitPoint(x: phase + 1, y: 0.5)
                    )
                    .blendMode(.screen)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// Reusable grey pill used in skeletons
private struct ShimmerBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.15))
            .frame(width: width, height: height)
            .shimmer()
    }
}

// MARK: - Home Skeleton

struct HomeSkeletonView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Greeting skeleton
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerBlock(width: 110, height: 13)
                    ShimmerBlock(width: 170, height: 22)
                }
                Spacer()
                ShimmerBlock(width: 80, height: 36, cornerRadius: 20)
            }
            .padding(.top, 16)

            // Pet card skeleton
            VStack(spacing: 16) {
                ShimmerBlock(width: 120, height: 120, cornerRadius: 60)
                ShimmerBlock(width: 140, height: 20)
                ShimmerBlock(width: 100, height: 14)
                ShimmerBlock(height: 12, cornerRadius: 6)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.07)))
            .padding(.horizontal)

            // Stats grid skeleton
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 8) {
                        ShimmerBlock(width: 28, height: 28, cornerRadius: 6)
                        ShimmerBlock(width: 50, height: 20)
                        ShimmerBlock(width: 60, height: 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.07)))
                }
            }
            .padding(.vertical)

            // PVP card skeleton
            HStack(spacing: 16) {
                ShimmerBlock(width: 52, height: 52, cornerRadius: 14)
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerBlock(width: 100, height: 18)
                    ShimmerBlock(width: 150, height: 13)
                }
                Spacer()
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.gray.opacity(0.1)))

            // Leaderboard skeleton
            VStack(alignment: .leading, spacing: 12) {
                ShimmerBlock(width: 140, height: 20)
                ShimmerBlock(width: 60, height: 13)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 12) {
                        ShimmerBlock(width: 44, height: 44, cornerRadius: 22)
                        VStack(alignment: .leading, spacing: 6) {
                            ShimmerBlock(width: 120, height: 15)
                            ShimmerBlock(width: 70, height: 12)
                        }
                        Spacer()
                        ShimmerBlock(width: 60, height: 28, cornerRadius: 14)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.07)))
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Oud Smoke Overlay

struct OudSmokeOverlay: View {
    // 5 wisp streams clustered near the screen's lower-centre, like rising bakhoor
    private static let streams: [(xFrac: Double, phase0: Double, speedMul: Double)] = [
        (0.44, 0.00, 1.00),
        (0.48, 0.33, 0.92),
        (0.50, 0.67, 1.08),
        (0.52, 0.17, 0.95),
        (0.56, 0.50, 1.03),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let originY = size.height * 0.75

                for (si, cfg) in Self.streams.enumerated() {
                    let baseX  = size.width * cfg.xFrac
                    let sif    = Double(si)

                    for slot in 0..<12 {
                        let slotF = Double(slot)
                        let speed = 0.055 * cfg.speedMul + slotF * 0.003
                        let phase = (t * speed + cfg.phase0 + slotF / 12)
                            .truncatingRemainder(dividingBy: 1.0)

                        // Rise vertically, sway horizontally
                        let y      = originY - phase * size.height * 0.62
                        let sway   = 8.0 + phase * 36.0
                        let x      = baseX + sin(t * (0.25 + sif * 0.06) + slotF * 1.1 + sif * 0.8) * sway

                        // Grow from a tight wisp to a broad cloud
                        let radius = 5.0 + phase * 54.0

                        // Quick fade-in, slow fade-out
                        let fadeIn  = min(phase / 0.12, 1.0)
                        let fadeOut = 1.0 - max((phase - 0.20) / 0.80, 0.0)
                        let alpha   = fadeIn * fadeOut * 0.13

                        guard alpha > 0.003 else { continue }

                        // Warm amber near the source → cool ivory as it rises
                        let warmth = 1.0 - phase
                        let r = 0.94 + warmth * 0.04
                        let g = 0.86 + warmth * 0.05
                        let b = 0.70 + warmth * 0.06 + phase * 0.10

                        ctx.fill(
                            Path(ellipseIn: CGRect(
                                x: x - radius, y: y - radius,
                                width: radius * 2, height: radius * 2
                            )),
                            with: .color(Color(red: r, green: g, blue: b).opacity(alpha))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

#Preview {
    HomeView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
