import SwiftUI

struct HomeView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager
    @State private var showPVPPayment = false
    @State private var particles: [Particle] = []
    
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
                            greetingSection
                            PetDisplayCard(
                                petName: userManager.userData.petName,
                                level: userManager.userData.level,
                                stage: userManager.userData.petStage,
                                xpProgress: userManager.userData.xpProgress
                            )
                            .padding(.horizontal)
                            
                            statsGrid
//                            PVPBattleCard {
//                                showPVPPayment = true
//                            }
                            leaderboardSection
                        }
                        .frame(maxWidth: 700) // Limit width on iPad
                        .padding(.horizontal)
                        
                        Spacer(minLength: 100)
                    }
                    .frame(maxWidth: .infinity) // Center content on wider screens
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showPVPPayment) {
                PVPPaymentDialog(isPresented: $showPVPPayment)
            }
            .onAppear {
                generateParticles()
                userManager.fetchAllUserData()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Fix iPad NavigationView
    }
    
    // MARK: - Sections
    
    private var greetingSection: some View {
        HStack {
            VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 4) {
                Text(languageManager.currentLanguage == .english ? "Welcome back," : "مرحبًا بك مجددًا،")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                Text(userManager.userData.fullName.components(separatedBy: " ").first! + " 👋")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
            }
            Spacer()
            
            // Points Badge
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundColor(.white)
                
                Text("\(userManager.userData.points)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(userManager.stageColor)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
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
                label: languageManager.currentLanguage == .english ? "Check-ins" : "التسجيلات",
                value: "\(userManager.userData.checkInCount)",
                gradient: [Color.green, Color.teal]
            )
            StatCard(
                icon: "bolt.fill",
                label: languageManager.currentLanguage == .english ? "Level" : "المستوى",
                value: "\(userManager.userData.level)",
                gradient: [Color.purple, Color.pink]
            )
        }
        .padding(.vertical)
    }

    
    private var leaderboardSection: some View {
        VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 12) {
            HStack {
                Text(languageManager.currentLanguage == .english ? "Leaderboard" : "قائمة المتصدرين")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
                TextButton(title: languageManager.currentLanguage == .english ? "View All" : "عرض الكل") {}
            }
            
            Text("Riyadh")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
            
            VStack(spacing: 12) {
                ForEach($userManager.leaderboardUsers) { user in
                    LeaderboardCard(user: user)
                }
            }
        }
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
    let id: Int        // use API id
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
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon with red background
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.94, green: 0.27, blue: 0.27)) // #EF4444
                        .frame(width: 52, height: 52)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                
                // Texts
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.currentLanguage == .english ? "PVP Battle" : "معركة PVP")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text(languageManager.currentLanguage == .english ? "Entry: 5 SAR" : "الدخول: 5 ريال")
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
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.07, green: 0.09, blue: 0.15)) // #111827
            )
        }
        .buttonStyle(PlainButtonStyle()) // Remove default button styling
        .padding(.horizontal)
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
    let level: Int
    let stage: PetStage
    let xpProgress: XPProgress
    @EnvironmentObject var languageManager: LanguageManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Circular progress ring with pet emoji
            ZStack {
                CircularProgressRing(
                    progress: xpProgress.progressPercentage,
                    size: 120,
                    lineWidth: 8
                )
                Text(stage.emoji)
                    .font(.system(size: 90))
            }
            
            // Pet Name & Level
            VStack(spacing: 4) {
                Text(petName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
                Text("\(languageManager.currentLanguage == .english ? "Level" : "المستوى") \(level)")
                    .font(.system(size: 16))
                    .foregroundColor(.black.opacity(0.8))
            }
            
            // XP Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(xpProgress.currentLevelXP) / \(xpProgress.nextLevelXP) XP")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.9))
                    Spacer()
                    Text("\(Int(xpProgress.progressPercentage * 100))%")
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
                            .frame(width: geometry.size.width * xpProgress.progressPercentage, height: 12)
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
    @Binding var user: LeaderboardUser  // <-- only if you need to modify it

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(user.bgColor)
                    .frame(width: 55, height: 55)
                
                if let url = URL(string: user.avatar ?? "") {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()  // or a default avatar
                    }
                    .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "person.fill")  // fallback
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                }
            }

            // Name + Level
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.system(size: 16, weight: .semibold))
                Text("Level \(user.level)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            Spacer()
            
            // Points
            Text("\(user.points) pts")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.blue))
        }
        .padding()
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

#Preview {
    HomeView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
