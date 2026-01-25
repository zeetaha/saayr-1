import SwiftUI
import SafariServices


struct WebPage: Identifiable {
    let id = UUID()
    let url: URL
}

struct PhoneAuthView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var languageManager: LanguageManager
    @FocusState private var isPhoneFocused: Bool
    
    @State private var showWeb = false
    @State private var selectedPage: WebPage? = nil


    
    let gradientColors: [Color] = [
        Color(hex: "#3B82F6"),
        Color(hex: "#06B6D4"),
        Color(hex: "#14B8A6")
    ]
    
    let backgroundColors: [Color] = [
        Color(hex: "#EFF6FF"),
        Color(hex: "#ECFEFF"),
        Color(hex: "#F0FDFA")
    ]
    
    
    
    var body: some View {
        ZStack {
            // ✅ Background (Compose match)
            LinearGradient(
                colors: backgroundColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // ✅ Floating Particles
            ForEach(Array(["📱", "💬", "✨", "⭐"].enumerated()), id: \.offset) { index, emoji in
                FloatingParticleOTP(emoji: emoji, index: index)
            }
            
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)
                    
                    // ✅ Icon with radial gradient
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: gradientColors,
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Text("📱")
                            .font(.system(size: 64))
                    }
                    
                    // Title
                    Text(languageManager.currentLanguage == .english
                         ? "Enter your phone number"
                         : "أدخل رقم هاتفك")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)
                    
                    // Description
                    Text(languageManager.currentLanguage == .english
                         ? "We'll send you a verification code to confirm your number"
                         : "سنرسل رمز تحقق لتأكيد رقم هاتفك")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    
                    // ✅ Glassmorphic Card
                    VStack(spacing: 24) {
                        HStack {
                            Text("+966")
                                .fontWeight(.bold)
                                .foregroundColor(Color(hex: "#3B82F6"))
                            
                            TextField("05X XXX XXXX", text: $authManager.phoneNumber)
                                .keyboardType(.numberPad)
                                .focused($isPhoneFocused)
                                .onChange(of: authManager.phoneNumber) { value in
                                    let filtered = value.filter { $0.isNumber }
                                    authManager.phoneNumber = String(filtered.prefix(10))
                                }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(hex: "#3B82F6"), lineWidth: 1)
                        )
                        
                        Button {
                            isPhoneFocused = false
                            authManager.sendOTP()
                        } label: {
                            if authManager.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                HStack(spacing: 8) {
                                    Text(languageManager.currentLanguage == .english
                                         ? "Send Code"
                                         : "إرسال الرمز")
                                    .font(.system(size: 18, weight: .bold))
                                    Image(systemName: "arrow.right")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity ,minHeight:56)
                        .background(Color(hex: "#3B82F6"))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .disabled(authManager.phoneNumber.count < 10 || authManager.isLoading)
                        .opacity(authManager.phoneNumber.count < 10 ? 0.6 : 1)
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(24)
                    .shadow(radius: 8)
                    .padding(.horizontal, 24)
                    
                    // ❌ ERROR MESSAGE
                    if let error = authManager.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                    
                    VStack(spacing: 8) {
                        Text(languageManager.text("legal.agreeText"))
                            .font(.system(size: 13))
                            .foregroundColor(.gray)

                        HStack(spacing: 4) {
                            Button(languageManager.text("legal.terms")) {
                                if let url = URL(string: "https://api.saayr.sa/api/v1/legal/terms-and-conditions") {
                                    selectedPage = WebPage(url: url)
                                }
                            }
                            .underline()

                            Text(languageManager.text("legal.and"))
                                .font(.system(size: 13))
                                .foregroundColor(.gray)

                            Button(languageManager.text("legal.privacy")) {
                                if let url = URL(string: "https://api.saayr.sa/api/v1/legal/privacy-policy") {
                                    selectedPage = WebPage(url: url)
                                }
                            }
                            .underline()
                        }
                        .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.top, 24)




                    Spacer(minLength: 40)
                }
            }
        }
        .onAppear {
            isPhoneFocused = true
        }
        .sheet(item: $selectedPage) { page in
            SafariView(url: page.url)
        }


        
    }

}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}




// Custom TextField placeholder modifier
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
            
            ZStack(alignment: alignment) {
                placeholder().opacity(shouldShow ? 1 : 0)
                self
            }
        }
}

#Preview {
    PhoneAuthView()
        .environmentObject(AuthManager())
        .environmentObject(LanguageManager())
}
