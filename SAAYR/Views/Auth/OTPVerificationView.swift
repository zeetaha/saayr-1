import SwiftUI
import Combine

import SwiftUI

struct OTPVerificationView: View {
    
    let phoneNumber: String
    let onVerified: () -> Void
    let onBack: () -> Void
    
    @State private var otp = ""
    @State private var isVerifying = false
    @State private var showSuccess = false
    @State private var resendTimer = 60
    @EnvironmentObject var authManager: AuthManager
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(hex: "#ECFDF5"),
                    Color(hex: "#D1FAE5"),
                    Color(hex: "#CCFBF1")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Floating particles
            ForEach(Array(["📬","✉️","✨","⭐"].enumerated()), id: \.offset) { index, emoji in
                FloatingParticleOTP(emoji: emoji, index: index)
            }
            
            VStack {
                header
                content
                numberPad
            }
            .padding(24)
            
            if showSuccess {
                successOverlay
            }
        }
        .onReceive(timer) { _ in
            if resendTimer > 0 {
                resendTimer -= 1
            }
        }
        .onChange(of: otp) { newValue in
            // Clear error when user starts typing
            if !newValue.isEmpty {
                authManager.errorMessage = nil
            }
            autoVerify()
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            if authManager.authState == .resetOtp {
                EmptyView()
            }else{
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "#059669"))
                }
            }
            Spacer()
            // ✅ SHOW OTP (DEBUG ONLY)
            if let otp = authManager.otp {
                Text("OTP: \(otp)")
                    .foregroundColor(.green)
            }
        }
    }
    
    // MARK: - Main Content
    private var content: some View {
        VStack(spacing: 32) {
            
            // Error Message
            if let errorMessage = authManager.errorMessage, !errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#10B981"),
                                Color(hex: "#059669"),
                                Color(hex: "#14B8A6")
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 80
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Text("📬")
                    .font(.system(size: 64))
            }
            
            Text("Enter verification code")
                .font(.system(size: 32, weight: .bold))
            
            Text(maskedPhoneText)
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            otpBoxes
            resendSection
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - OTP Boxes
    private var otpBoxes: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            index < otp.count
                            ? Color(hex: "#10B981")
                            : Color.gray.opacity(0.3),
                            lineWidth: 2
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.9))
                        )
                    
                    Text(digit(at: index))
                        .font(.system(size: 24, weight: .bold))
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
    }
    
    // MARK: - Resend
    // MARK: - Resend
    private var resendSection: some View {
        ZStack {
            if resendTimer > 0 {
                // Background ring (gray/transparent)
                Circle()
                    .stroke(Color(hex: "#DCFCE7"), lineWidth: 8)
                    .frame(width: 60, height: 60)
                
                // Progress ring (green)
                Circle()
                    .trim(from: 0, to: CGFloat(resendTimer) / 60)
                    .stroke(Color(hex: "#10B981"), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90)) // start from top
                    .frame(width: 60, height: 60)
                    .animation(.linear(duration: 1), value: resendTimer)
                
                // Timer text
                Text("\(resendTimer)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#059669"))
            } else {
                Button("Resend Code") {
                    resendTimer = 60
                    otp = ""
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: "#10B981"))
            }
        }
    }
    
    
    // Pie slice shape for filled circle progress
    struct PieSlice: Shape {
        var progress: Double // 0.0 → 1.0
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            let endAngle = Angle(degrees: 360 * progress)
            
            path.move(to: center)
            path.addArc(center: center,
                        radius: radius,
                        startAngle: .degrees(0),
                        endAngle: endAngle,
                        clockwise: false)
            path.closeSubpath()
            return path
        }
        
        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }
    }
    
    
    // MARK: - Number Pad
    private var numberPad: some View {
        VStack(spacing: 12) {
            ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { number in
                        NumberButton(text: "\(number)") {
                            appendDigit("\(number)")
                        }
                    }
                }
            }
            
            HStack(spacing: 12) {
                Spacer()
                NumberButton(text: "0") {
                    appendDigit("0")
                }
                Button(action: deleteDigit) {
                    Image(systemName: "delete.left")
                        .foregroundColor(Color(hex: "#059669"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(hex: "#DCFCE7"))
                        .cornerRadius(12)
                }
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            
            ForEach(0..<20, id: \.self) { index in
                ConfettiParticle(index: index)
            }
            
            Circle()
                .fill(Color.white)
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(Color(hex: "#10B981"))
                )
        }
        .transition(.opacity.combined(with: .scale))
    }
    
    // MARK: - Helpers
    private func digit(at index: Int) -> String {
        guard index < otp.count else { return "" }
        return String(Array(otp)[index])
    }
    
    private func appendDigit(_ digit: String) {
        if otp.count < 6 {
            otp.append(digit)
        }
    }
    
    private func deleteDigit() {
        guard !otp.isEmpty else { return }
        otp.removeLast()
        isVerifying = false
    }
    
    private func autoVerify() {
        guard otp.count == 6, !isVerifying else { return }

        isVerifying = true
        authManager.errorMessage = nil // Clear previous errors before retry

        authManager.verifyOTP(otp: otp) { isNewUser in
            // ❌ Check if verification failed
            if authManager.errorMessage != nil {
                isVerifying = false
                otp = "" // Clear OTP for user to retry
                return
            }

            // 1️⃣ Show success overlay
            withAnimation(.easeInOut) {
                showSuccess = true
            }

            // 2️⃣ WAIT so user can see it
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {

                withAnimation(.easeInOut) {
                    if isNewUser {
                        authManager.authState = .profileSetup
                    } else {
                        authManager.authState = .login
                    }
                }

                isVerifying = false
            }
        }
    }

    
    private var maskedPhoneText: String {
        let masked = phoneNumber.prefix(7) + "**" + phoneNumber.suffix(2)
        return "We sent a 6-digit code to\n+966 \(masked)"
    }
}

struct NumberButton: View {
    let text: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.white.opacity(0.9))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#10B981").opacity(0.3), lineWidth: 1)
                )
        }
    }
}

struct FloatingParticleOTP: View {
    let emoji: String
    let index: Int
    
    @State private var offsetY: CGFloat = 0
    @State private var offsetX: CGFloat = 0
    
    private let positions: [(CGFloat, CGFloat)] = [
        (0.15, 0.2),
        (0.85, 0.25),
        (0.1, 0.6),
        (0.9, 0.65)
    ]
    
    var body: some View {
        GeometryReader { geo in
            let pos = positions[index % positions.count]
            
            Text(emoji)
                .font(.system(size: 32))
                .opacity(0.4)
                .position(
                    x: geo.size.width * pos.0 + offsetX,
                    y: geo.size.height * pos.1 + offsetY
                )
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 3 + Double(index))
                        .repeatForever(autoreverses: true)
                    ) {
                        offsetY = -30
                        offsetX = 15
                    }
                }
        }
        .ignoresSafeArea()
    }
}

struct ConfettiParticle: View {
    let index: Int
    
    @State private var offsetY: CGFloat = -200
    @State private var rotation: Double = 0
    
    private let emojis = ["🎉", "✨", "🎊", "⭐", "💫", "🌟"]
    
    var body: some View {
        GeometryReader { geo in
            let startX = CGFloat.random(in: -geo.size.width/2...geo.size.width/2)
            
            Text(emojis[index % emojis.count])
                .font(.system(size: 24))
                .opacity(0.8)
                .rotationEffect(.degrees(rotation))
                .position(x: geo.size.width / 2 + startX, y: offsetY)
                .onAppear {
                    withAnimation(
                        .linear(duration: 2 + Double(index) * 0.1)
                        .repeatForever(autoreverses: false)
                    ) {
                        offsetY = geo.size.height + 200
                        rotation = 360
                    }
                }
        }
        .ignoresSafeArea()
    }
}



#Preview {
    OTPVerificationView(
        phoneNumber: "512345678",
        onVerified: {
            print("Verified")
        },
        onBack: {
            print("Back")
        }
    )
    .environmentObject(AuthManager())
    .environmentObject(LanguageManager())
}
