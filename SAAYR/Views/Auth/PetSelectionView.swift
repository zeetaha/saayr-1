import SwiftUI

struct PetSelectionView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var languageManager: LanguageManager
    @State private var petName: String = ""
    @State private var showValidation: Bool = false

    let particles = ["🦅", "🔥", "⚡", "👑"]

    private var validationError: String? {
        if petName.count < 2 {
            return languageManager.currentLanguage == .english
                ? "Name must be at least 2 characters."
                : "يجب أن يحتوي الاسم على حرفين على الأقل."
        }
        if petName.contains(" ") {
            return languageManager.currentLanguage == .english
                ? "Spaces are not allowed in a falcon name."
                : "لا يُسمح باستخدام المسافات في اسم الصقر."
        }
        let allowed = CharacterSet.letters.union(.decimalDigits)
        if petName.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return languageManager.currentLanguage == .english
                ? "Only letters and numbers are allowed (no special characters)."
                : "يُسمح فقط بالحروف والأرقام، دون رموز خاصة."
        }
        return nil
    }
    
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
                                        .stroke(
                                            showValidation && validationError != nil ? Color.red : Color(hex: "#EC4899"),
                                            lineWidth: showValidation && validationError != nil ? 1.5 : 2
                                        )
                                )
                                .foregroundColor(.black)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .onChange(of: petName) { newValue in
                                    if newValue.count > 20 { petName = String(newValue.prefix(20)) }
                                    authManager.errorMessage = nil
                                }

                            // Inline client-side validation error
                            if showValidation, let err = validationError {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 12))
                                    Text(err)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
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
                        
                        // Server-side error (e.g. name already taken)
                        if let message = authManager.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 14))
                                Text(message)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.red)
                        }

                        // Start Journey Button
                        Button(action: {
                            withAnimation { showValidation = true }
                            guard validationError == nil else { return }
                            authManager.tempPetName = petName
                            authManager.completeSetup()
                        }) {
                            Group {
                                if authManager.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView().tint(Color(hex: "#EC4899"))
                                        Text(languageManager.currentLanguage == .english ? "Setting up..." : "جاري الإعداد...")
                                            .font(.system(size: 18, weight: .bold))
                                    }
                                    .foregroundColor(Color(hex: "#EC4899"))
                                } else {
                                    HStack {
                                        Text(languageManager.currentLanguage == .english ? "Start Your Journey" : "ابدأ رحلتك")
                                            .font(.system(size: 18, weight: .bold))
                                        Image(systemName: "arrow.forward")
                                    }
                                    .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(authManager.isLoading ? Color.white : Color(hex: "#EC4899"))
                            .cornerRadius(16)
                        }
                        .disabled(authManager.isLoading)
                        .opacity(authManager.isLoading ? 0.6 : 1)
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(24)
                    .padding(.horizontal, 24)
                    
                    
                    
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
