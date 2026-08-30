import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var languageManager: LanguageManager
    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var showValidation = false

    private var trimmedName: String { fullName.trimmingCharacters(in: .whitespaces) }
    private var nameError: Bool { showValidation && trimmedName.count < 2 }
    private var emailError: Bool {
        showValidation &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isValidEmail(email)
    }

    private func isValidEmail(_ value: String) -> Bool {
        let pred = NSPredicate(format: "SELF MATCHES %@",
                               "[A-Z0-9a-z._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}")
        return pred.evaluate(with: value.trimmingCharacters(in: .whitespaces))
    }

    /// Sanitise a name input: letters + Arabic only, single spaces, no leading space.
    private func sanitiseName(_ input: String) -> String {
        // Keep only letters (covers A-Z, a-z, Arabic, etc.) and spaces
        let lettersAndSpaces = input.unicodeScalars.filter {
            CharacterSet.letters.union(.init(charactersIn: " ")).contains($0)
        }
        var result = String(String.UnicodeScalarView(lettersAndSpaces))
        // Collapse consecutive spaces into one
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        // Prevent a leading space
        if result.hasPrefix(" ") { result.removeFirst() }
        return result
    }
    
    // Floating particles
    let particles = ["👤", "✨", "💫", "⭐"]
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(hex: "#EFF6FF"),
                    Color(hex: "#FAF5FF"),
                    Color(hex: "#FDF2F8")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Floating particles
            ForEach(particles.indices, id: \.self) { index in
                FloatingParticleProfile(emoji: particles[index], index: index)
            }
            
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)
                    
                    // Icon with gradient background
                    ZStack {
                        Circle()
                            .fill(RadialGradient(
                                colors: [Color(hex: "#3B82F6"), Color(hex: "#A855F7"), Color(hex: "#EC4899")],
                                center: .center,
                                startRadius: 0,
                                endRadius: 60
                            ))
                            .frame(width: 120, height: 120)
                        Text("👤")
                            .font(.system(size: 64))
                    }
                    
                    // Title & Description
                    VStack(spacing: 12) {
                        Text(languageManager.currentLanguage == .english ? "Complete your profile" : "أكمل ملفك الشخصي")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                        
                        Text(languageManager.currentLanguage == .english ? "Tell us a bit about yourself" : "أخبرنا قليلاً عن نفسك")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    
                    // Form
                    VStack(spacing: 20) {
                        // Full Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text(languageManager.currentLanguage == .english ? "Full Name" : "الاسم الكامل")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)

                            TextField("", text: $fullName)
                                .placeholder(when: fullName.isEmpty) {
                                    Text(languageManager.currentLanguage == .english ? "Enter your full name" : "أدخل اسمك الكامل")
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(nameError ? Color.red : Color.gray.opacity(0.5),
                                                lineWidth: nameError ? 1.5 : 2)
                                )
                                .foregroundColor(.black)
                                .autocapitalization(.words)
                                .onChange(of: fullName) { value in
                                    let clean = sanitiseName(value)
                                    if clean != value { fullName = clean }
                                    authManager.errorMessage = nil
                                }

                            if nameError {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 12))
                                    Text(languageManager.currentLanguage == .english
                                         ? "Please enter your full name."
                                         : "يرجى إدخال اسمك الكامل.")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        // Email
                        VStack(alignment: .leading, spacing: 6) {
                            Text(languageManager.currentLanguage == .english ? "Email (Optional)" : "البريد الإلكتروني (اختياري)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)

                            TextField("", text: $email)
                                .placeholder(when: email.isEmpty) {
                                    Text("your.email@example.com")
                                        .foregroundColor(.purple)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(emailError ? Color.red : Color.gray.opacity(0.5),
                                                lineWidth: emailError ? 1.5 : 2)
                                )
                                .foregroundColor(.black)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .onChange(of: email) { _ in
                                    authManager.errorMessage = nil
                                }

                            if emailError {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 12))
                                    Text(languageManager.currentLanguage == .english
                                         ? "Please enter a valid email."
                                         : "يرجى إدخال بريد إلكتروني صحيح.")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        Text("✨ No password needed!")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .padding(.bottom,16)
                    }
                    
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.9)))
                    .padding(.horizontal, 16,)
                    
                    
                    // API / validation error from AuthManager
                    if let error = authManager.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 14))
                            Text(error)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 32)
                        .multilineTextAlignment(.center)
                    }

                    // Continue Button
                    Button(action: {
                        withAnimation { showValidation = true }
                        guard trimmedName.count >= 2 else { return }
                        guard email.trimmingCharacters(in: .whitespaces).isEmpty || isValidEmail(email) else { return }
                        authManager.tempFullName = trimmedName
                        authManager.tempEmail = email.trimmingCharacters(in: .whitespaces)
                        authManager.completeProfileSetup()
                    }) {
                        Group {
                            if authManager.isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(Color(hex: "#3B82F6"))
                                    Text(languageManager.currentLanguage == .english ? "Setting up..." : "جاري الإعداد...")
                                        .font(.system(size: 18, weight: .bold))
                                }
                                .foregroundColor(Color(hex: "#3B82F6"))
                            } else {
                                HStack {
                                    Text(languageManager.currentLanguage == .english ? "Continue" : "متابعة")
                                        .font(.system(size: 18, weight: .bold))
                                    Image(systemName: "arrow.forward")
                                }
                                .foregroundColor(Color(hex: "#3B82F6"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, 32)
                    .disabled(authManager.isLoading)
                    .opacity(authManager.isLoading ? 0.6 : 1.0)
                    
                    Spacer(minLength: 40)
                }
            }
        }
    }
}

// MARK: - Floating Particle
struct FloatingParticleProfile: View {
    let emoji: String
    let index: Int
    @State private var animate = false
    
    var body: some View {
        let positions = [
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

// MARK:
#Preview {
    ProfileSetupView()
        .environmentObject(AuthManager())
        .environmentObject(LanguageManager())
}
