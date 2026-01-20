import SwiftUI

struct PetSelectionView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var languageManager: LanguageManager
    @State private var petName: String = ""
    @State private var showError: Bool = false
    // Floating particles
    let particles = ["🦅", "🔥", "⚡", "👑"]
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color(hex: "#FDF2F8"), Color(hex: "#FAF5FF"), Color(hex: "#FFEDD5")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Floating particles
            ForEach(particles.indices, id: \.self) { index in
                FloatingParticlePet(emoji: particles[index], index: index)
            }
            
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)
                    
                    // Animated Floating Egg
                    AnimatedFloatingEgg()
                    
                    // Title & Description
                    VStack(spacing: 16) {
                        Text(languageManager.currentLanguage == .english ? "Name your companion" : "سمِ رفيقك")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                        
                        Text(languageManager.currentLanguage == .english ?
                             "Choose a name for your falcon companion.\nIt will grow with you on your journey!" :
                                "اختر اسمًا لصقر رفيقك.\nسينمو معك في رحلتك!")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    }
                    .padding(.horizontal)
                    
                    // Input Card
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(languageManager.currentLanguage == .english ? "Falcon Name" : "اسم الصقر")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                            
                            TextField("", text: $petName)
                                .placeholder(when: petName.isEmpty) {
                                    Text(languageManager.currentLanguage == .english ? "Enter a name" : "أدخل اسمًا")
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color(hex: "#EC4899"), lineWidth: 2)
                                )
                                .foregroundColor(.black)
                                .onChange(of: petName) { newValue in
                                    if newValue.count > 20 { petName = String(newValue.prefix(20)) }
                                }
                        }
                        
                        // Warning Note
                        HStack {
                            Text("⚠️")
                            Text(languageManager.currentLanguage == .english ?
                                 "Note: You won't be able to change the name later" :
                                    "ملاحظة: لن تتمكن من تغيير الاسم لاحقًا")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#BE123C"))
                        }
                        .padding(12)
                        .background(Color(hex: "#FFF1F2"))
                        .cornerRadius(12)
                        
                        if showError, let message = authManager.errorMessage {
                            Text(message)
                                .foregroundColor(.red)
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        // Start Journey Button
                        Button(action: {
                            guard petName.count >= 2 else { return }
                            
                            authManager.tempPetName = petName
                            authManager.completeSetup()
                        }) {
                            HStack {
                                Text(languageManager.currentLanguage == .english ? "Start Your Journey" : "ابدأ رحلتك")
                                    .font(.system(size: 18, weight: .bold))
                                Image(systemName: "arrow.forward")
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(hex: "#EC4899"))
                            .cornerRadius(16)
                        }
                        .disabled(petName.count < 2)
                        .opacity(petName.count < 2 ? 0.6 : 1)
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(24)
                    .padding(.horizontal, 24)
                    .onChange(of: authManager.errorMessage) { newValue in
                        if newValue != nil {
                            withAnimation {
                                showError = true
                            }
                        }
                    }
                    
                    
                    
                    Spacer(minLength: 40)
                }
            }
        }
    }
}

// MARK: - Animated Egg
struct AnimatedFloatingEgg: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Gradient Glow
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "#EC4899").opacity(0.3),
                            Color(hex: "#A855F7").opacity(0.2),
                            Color(hex: "#F97316").opacity(0.1),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)
                .scaleEffect(animate ? 1.1 : 1.0)
            
            // Egg Emoji
            Text("🥚")
                .font(.system(size: 120))
                .offset(y: animate ? -20 : 0)
                .rotationEffect(.degrees(animate ? 5 : -5))
                .scaleEffect(animate ? 1.1 : 1.0)
            
            // Sparkles
            ForEach(0..<5) { index in
                SparkleParticle(index: index)
            }
        }
        .frame(width: 200, height: 200)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - Sparkles
struct SparkleParticle: View {
    let index: Int
    @State private var animate = false
    
    var body: some View {
        let positions: [CGPoint] = [
            CGPoint(x: -60, y: -80),
            CGPoint(x: 60, y: -70),
            CGPoint(x: -70, y: 50),
            CGPoint(x: 70, y: 60),
            CGPoint(x: 0, y: -100)
        ]
        let pos = positions[index % positions.count]
        
        Text("✨")
            .font(.system(size: 24))
            .offset(x: pos.x, y: pos.y)
            .scaleEffect(animate ? 1.2 : 0.5)
            .opacity(animate ? 1 : 0.3)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(index) * 0.1)) {
                    animate.toggle()
                }
            }
    }
}

// MARK: - Floating Particles
struct FloatingParticlePet: View {
    let emoji: String
    let index: Int
    @State private var animate = false
    
    var body: some View {
        let positions: [CGPoint] = [
            CGPoint(x: 0.15, y: 0.2),
            CGPoint(x: 0.85, y: 0.3),
            CGPoint(x: 0.25, y: 0.7),
            CGPoint(x: 0.75, y: 0.65)
        ]
        let pos = positions[index % positions.count]
        
        Text(emoji)
            .font(.system(size: 32))
            .opacity(0.4)
            .position(
                x: UIScreen.main.bounds.width * pos.x + (animate ? 15 : -15),
                y: UIScreen.main.bounds.height * pos.y + (animate ? -30 : 0)
            )
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    animate.toggle()
                }
            }
    }
}

#Preview {
    PetSelectionView()
        .environmentObject(AuthManager())
        .environmentObject(LanguageManager())
}
