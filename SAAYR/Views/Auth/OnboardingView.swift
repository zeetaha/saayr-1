import SwiftUI
import AppTrackingTransparency
import AdSupport


struct OnboardingSlide: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let titleAr: String
    let description: String
    let descriptionAr: String
    let gradient: [Color]
    let backgroundGradient: [Color]
    let particles: [String]
}
struct OnboardingView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var languageManager: LanguageManager

    @State private var currentPage = 0

    @State private var didAskTracking = false

    var isRTL: Bool {
        languageManager.currentLanguage == .arabic
    }

    let slides: [OnboardingSlide] = [
        OnboardingSlide(
            emoji: "🌍",
            title: "Explore the real world",
            titleAr: "استكشف العالم الحقيقي",
            description: "Visit merchants and shops around Riyadh to earn XP and grow your falcon companion",
            descriptionAr: "قم بزيارة المتاجر في الرياض لكسب نقاط الخبرة وتنمية صقرك",
            gradient: [Color(hex: "#3B82F6"), Color(hex: "#06B6D4"), Color(hex: "#14B8A6")],
            backgroundGradient: [
                Color(hex: "#EFF6FF").opacity(0.8),
                Color(hex: "#ECFEFF").opacity(0.6),
                Color(hex: "#F0FDFA").opacity(0.4)
            ],
            particles: ["💎", "⭐", "✨", "🌟"]
        ),
        OnboardingSlide(
            emoji: "🎁",
            title: "Earn XP and rewards",
            titleAr: "اكسب نقاط الخبرة والمكافآت",
            description: "Every 1 SAR you spend = 1 XP. Collect 100 XP to earn 1 Point",
            descriptionAr: "كل ريال تنفقه = نقطة خبرة واحدة. اجمع 100 نقطة لتحصل على نقطة",
            gradient: [Color(hex: "#A855F7"), Color(hex: "#EC4899"), Color(hex: "#F43F5E")],
            backgroundGradient: [
                Color(hex: "#FAF5FF").opacity(0.8),
                Color(hex: "#FDF2F8").opacity(0.6),
                Color(hex: "#FFF1F2").opacity(0.4)
            ],
            particles: ["🎁", "💰", "🏆", "💫"]
        ),
        OnboardingSlide(
            emoji: "🦅",
            title: "Grow your companion",
            titleAr: "نمِّ رفيقك",
            description: "Watch your falcon evolve from an egg to a legendary creature",
            descriptionAr: "شاهد صقرك يتطور من بيضة إلى مخلوق أسطوري",
            gradient: [Color(hex: "#F97316"), Color(hex: "#EF4444"), Color(hex: "#EC4899")],
            backgroundGradient: [
                Color(hex: "#FFEDD5").opacity(0.8),
                Color(hex: "#FEE2E2").opacity(0.6),
                Color(hex: "#FDF2F8").opacity(0.4)
            ],
            particles: ["🦅", "🔥", "⚡", "👑"]
        )
    ]

    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                colors: slides[currentPage].backgroundGradient,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Animated Background
            AnimatedBackgroundOrbs(colors: slides[currentPage].gradient)
            FloatingParticles(particles: slides[currentPage].particles)

            VStack {
                // Language Toggle
                HStack {
                    Spacer()
                    Button {
                        languageManager.toggleLanguage()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                            Text(isRTL ? "English" : "العربية")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.9))
                        .cornerRadius(16)
                        .shadow(radius: 8)
                    }
                }
                .padding()

                // Pager
                TabView(selection: $currentPage) {
                    ForEach(slides.indices, id: \.self) { index in
                        OnboardingSlideView(
                            slide: slides[index],
                            isRTL: isRTL
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Progress Bar
                ProgressView(value: Double(currentPage + 1), total: Double(slides.count))
                    .tint(slides[currentPage].gradient.first!)
                    .padding(.horizontal, 32)

                // Dots
                HStack(spacing: 12) {
                    ForEach(slides.indices, id: \.self) { index in
                        Capsule()
                            .frame(width: index == currentPage ? 40 : 12, height: 12)
                            .background(
                                Group {
                                    if index == currentPage {
                                        LinearGradient(
                                            colors: slides[index].gradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    } else {
                                        Color.white.opacity(0.4)
                                    }
                                }
                            )
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 16)


                // Buttons
                HStack(spacing: 12) {
                    if currentPage > 0 {
                        Button {
                            withAnimation {
                                currentPage -= 1
                            }
                        } label: {
                            Image(systemName: isRTL ? "chevron.right" : "chevron.left")
                                .frame(width: 64, height: 64)
                                .background(Color.white)
                                .cornerRadius(16)
                        }
                    }

                    Button {
                        if currentPage == slides.count - 1 {
                            requestTrackingPermissionIfNeeded {
                                        authManager.completeOnboarding()
                            }
                        } else {
                            withAnimation {
                                currentPage += 1
                            }
                        }
                    } label: {
                        HStack {
                            if currentPage == slides.count - 1 {
                                Image(systemName: "sparkles")
                            }
                            Text(currentPage == slides.count - 1
                                 ? (isRTL ? "ابدأ" : "Get Started")
                                 : (isRTL ? "التالي" : "Next"))
                                .fontWeight(.bold)
                            if currentPage < slides.count - 1 {
                                Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(
                            LinearGradient(
                                colors: slides[currentPage].gradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                }
                .padding(32)
            }
        
        }
    }
    
    private func requestTrackingPermissionIfNeeded(completion: @escaping () -> Void) {
        guard !didAskTracking else {
            completion()
            return
        }

        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    didAskTracking = true
                    completion()

                    switch status {
                    case .authorized:
                        print("Tracking authorized")
                    case .denied:
                        print("Tracking denied")
                    case .restricted:
                        print("Tracking restricted")
                    case .notDetermined:
                        print("Not determined")
                    @unknown default:
                        break
                    }
                }
            }
        } else {
            completion()
        }
    }

}

struct OnboardingSlideView: View {
    let slide: OnboardingSlide
    let isRTL: Bool

    @State private var rotate = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: slide.gradient.map { $0.opacity(0.3) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 220, height: 220)
                    .scaleEffect(pulse ? 1.1 : 0.95)
                    .blur(radius: 40)
                    .animation(.easeInOut(duration: 2).repeatForever(), value: pulse)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: slide.gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(rotate ? 360 : 0))
                    .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: rotate)

                Text(slide.emoji)
                    .font(.system(size: 96))
            }
            .onAppear {
                rotate = true
                pulse = true
            }

            Text(isRTL ? slide.titleAr : slide.title)
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    LinearGradient(
                        colors: slide.gradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text(isRTL ? slide.descriptionAr : slide.description)
                .font(.system(size: 18))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

struct AnimatedBackgroundOrbs: View {
    let colors: [Color]
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: colors.map { $0.opacity(0.2) },
                                   center: .center,
                                   startRadius: 0,
                                   endRadius: 200)
                )
                .frame(width: 260, height: 260)
                .offset(x: -80, y: -120)
                .scaleEffect(animate ? 1.2 : 0.8)

            Circle()
                .fill(
                    RadialGradient(colors: colors.map { $0.opacity(0.2) },
                                   center: .center,
                                   startRadius: 0,
                                   endRadius: 240)
                )
                .frame(width: 320, height: 320)
                .offset(x: 100, y: 240)
                .scaleEffect(animate ? 1.3 : 0.9)
        }
        .blur(radius: 64)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever()) {
                animate.toggle()
            }
        }
    }
}


struct FloatingParticles: View {
    let particles: [String]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(particles.indices, id: \.self) { index in
                FloatingParticle(
                    emoji: particles[index],
                    delay: Double(index) * 0.5,
                    index: index
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
struct FloatingParticle: View {
    let emoji: String
    let delay: Double
    let index: Int

    @State private var float = false

    var body: some View {
        Text(emoji)
            .font(.system(size: 36))
            // ✅ base position (top-leading)
            .offset(
                x: CGFloat(20 + index * 24),
                y: CGFloat(120 + index * 40)
            )
            // ✅ animated floating
            .offset(y: float ? -120 : 0)
            .opacity(float ? 1 : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 3)
                        .delay(delay)
                        .repeatForever(autoreverses: true)
                ) {
                    float = true
                }
            }
    }
}


#Preview {
    OnboardingView()
        .environmentObject(AuthManager())
        .environmentObject(LanguageManager())
}
