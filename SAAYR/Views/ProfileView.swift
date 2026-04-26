import SwiftUI
import Alamofire

struct ProfileView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var authManager: AuthManager

    @State private var isEditing = false
    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var showGroups = false
    @State private var showSupport = false
    @State private var showSetting = false

    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @State private var showDeleteConfirm = false
    @State private var showLogoutConfirm = false
    @State private var supportUnreadCount: Int = 0

    
    var body: some View {
        ZStack {
            // MARK: Background Gradient
            LinearGradient(
                colors: [
                    Color(hex: "#F5F3FF"),
                    Color(hex: "#FAF5FF"),
                    Color(hex: "#FDF2F8")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // MARK: Animated Orbs
            AnimatedOrb(
                size: 260,
                colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                offset: CGPoint(x: 40, y: 80)
            )
            
            AnimatedOrb(
                size: 320,
                colors: [Color(hex: "#EC4899"), Color(hex: "#F43F5E")],
                offset: CGPoint(x: -40, y: -120)
            )
            
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profile")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Manage your account and pet information")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(hex: "#8B5CF6"),
                                Color(hex: "#A855F7"),
                                Color(hex: "#EC4899")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        VStack{
                            // MARK: Profile Card
                            ProfileHeaderCard(user: userManager.userData)
                            
                            // MARK: Stats
                            HStack(spacing: 12) {
                                StatCardProfile(icon: "mappin", value: "\(userManager.userData.checkInStreak)", label: "Completed check-ins")
                                StatCardProfile(icon: "bolt.fill", value: "\(userManager.userData.pvpWins)", label: "PVP wins")
                                StatCardProfile(icon: "gift.fill", value: "\(userManager.userData.rewards ?? 0)", label: "Rewards claimed")
                            }
                        }
                        .padding()
                    
                   
                        
                    }
                    .cornerRadius(20)
                    .shadow(radius: 6)
                    .padding(.horizontal)

                    
                    // MARK: Editable Info
                    EditableInfoCard(
                        fullName: $fullName,
                        email: $email,
                        petName: userManager.userData.petName ?? "",
                        isEditing: $isEditing
                    )
                    .padding(.horizontal)
                    
                    VStack(spacing: 12) {
//                        ProfileMenuItem(
//                            icon: "person.3.fill",
//                            label: "My Groups",
//                            gradient: [Color(hex: "#A855F7"), Color(hex: "#8B5CF6")]
//                        )
//                        {
//                            showGroups = true
//                            }

                        ProfileMenuItem(
                            icon: "questionmark.circle.fill",
                            label: "Support",
                            gradient: [Color(hex: "#10B981"), Color(hex: "#059669")],
                            badgeCount: supportUnreadCount
                        ) {
                            showSupport = true
                        }

                        ProfileMenuItem(
                            icon: "gearshape.fill",
                            label: "Settings",
                            gradient: [Color(hex: "#3B82F6"), Color(hex: "#0EA5E9")]
                        ){
                            showSetting = true
                        }
                    }
                    .padding(.horizontal)

                    
                    // MARK: Delete
                    Button(role: .destructive) {
                        showDeleteConfirm = true   // 👈 ask first
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete Account")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // MARK: Logout
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.backward.square")
                            Text("Logout")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 80)
                }
                .padding(.top, 24)
            }
        }
        .onAppear {
            fullName = userManager.userData.fullName ?? ""
            email = userManager.userData.email ?? ""
            fetchSupportUnreadCount()
        }
        .sheet(isPresented: $showGroups) {
            GroupsView()
        }
        .fullScreenCover(isPresented: $showSupport) {
                SupportView()
        }
        .sheet(isPresented: $showSetting) {
            SettingsView()
        }
        .alert("Logout?", isPresented: $showLogoutConfirm) {
            Button("Logout", role: .destructive) { authManager.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to log out?")
        }
        .alert("Delete Account?",
               isPresented: $showDeleteConfirm) {

            Button("Delete", role: .destructive) {
                DeleteApi()   // 🔥 Only here we call API
            }

            Button("Cancel", role: .cancel) {}

        } message: {
            Text("""
            This action cannot be undone.
            All your progress, rewards, and data will be permanently deleted.
            """)
        }

    }
    
    private func fetchSupportUnreadCount() {
        ServiceModel.shared.getRequest(endpoint: WebService.supportUnreadCount) { result in
            guard case .success(let data) = result,
                  let json = try? JSONDecoder().decode([String: Int].self, from: data),
                  let count = json["unread_count"] else { return }
            DispatchQueue.main.async { supportUnreadCount = count }
        }
    }

    private func DeleteApi() {
        isLoading = true
        errorMessage = nil

        ServiceModel.shared.deleteRequest(
            endpoint: WebService.deleteAccount
        ) { result in

            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case .success(let data):
                    print("Account deleted:", String(data: data, encoding: .utf8) ?? "")

                    // ✅ Clear user session / logout
                    authManager.logout()

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
struct AnimatedOrb: View {
    let size: CGFloat
    let colors: [Color]
    let offset: CGPoint
    
    @State private var scale: CGFloat = 1
    
    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: colors, center: .center, startRadius: 10, endRadius: size)
            )
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(0.12)
            .blur(radius: 80)
            .offset(x: offset.x, y: offset.y)
            .onAppear {
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                    scale = 1.2
                }
            }
    }
}
struct ProfileHeaderCard: View {
    let user: UserData
    
    var body: some View {
       
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.fullName ?? "")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 8) {
                            Badge(icon: "star.fill", text: "Level \(user.userLevel ?? 0)")
                            Badge(icon: "sparkles", text: "\(user.points) XP")
                        }
                    }
                    Spacer()
                }
            }
          
    }
}
struct EditableInfoCard: View {
    @Binding var fullName: String
    @Binding var email: String
    let petName: String
    @Binding var isEditing: Bool

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showValidation = false

    private var trimmedName: String { fullName.trimmingCharacters(in: .whitespaces) }

    private var nameError: String? {
        guard showValidation else { return nil }
        if trimmedName.isEmpty { return "Full name is required." }
        if trimmedName.count < 2  { return "Name must be at least 2 characters." }
        return nil
    }

    private var emailError: String? {
        guard showValidation else { return nil }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil } // optional
        if !isValidEmail(trimmed) { return "Please enter a valid email." }
        return nil
    }

    private func isValidEmail(_ value: String) -> Bool {
        let pred = NSPredicate(format: "SELF MATCHES %@",
                               "[A-Z0-9a-z._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}")
        return pred.evaluate(with: value)
    }

    private func sanitiseName(_ input: String) -> String {
        let lettersAndSpaces = input.unicodeScalars.filter {
            CharacterSet.letters.union(.init(charactersIn: " ")).contains($0)
        }
        var result = String(String.UnicodeScalarView(lettersAndSpaces))
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        if result.hasPrefix(" ") { result.removeFirst() }
        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Personal Information")
                    .font(.headline)
                Spacer()
                Button {
                    if isEditing {
                        withAnimation { showValidation = true }
                        guard nameError == nil, emailError == nil,
                              !trimmedName.isEmpty else { return }
                        updateProfile()
                    } else {
                        showValidation = false
                        errorMessage = nil
                        isEditing = true
                    }
                } label: {
                    Label(isEditing ? "Save" : "Edit",
                          systemImage: isEditing ? "checkmark" : "pencil")
                        .font(.subheadline)
                }
                .disabled(isLoading)
            }

            // Full Name field
            VStack(alignment: .leading, spacing: 4) {
                TextField("Full Name", text: $fullName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEditing)
                    .autocapitalization(.words)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(nameError != nil ? Color.red : Color.clear, lineWidth: 1.5)
                    )
                    .onChange(of: fullName) { value in
                        let clean = sanitiseName(value)
                        if clean != value { fullName = clean }
                        errorMessage = nil
                    }

                if let err = nameError {
                    Label(err, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                }
            }

            // Email field
            VStack(alignment: .leading, spacing: 4) {
                TextField("Email (optional)", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEditing)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(emailError != nil ? Color.red : Color.clear, lineWidth: 1.5)
                    )
                    .onChange(of: email) { _ in errorMessage = nil }

                if let err = emailError {
                    Label(err, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                }
            }

            TextField("Pet Name", text: .constant(petName))
                .textFieldStyle(.roundedBorder)
                .disabled(true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(20)
        .shadow(radius: 6)
    }

    private func updateProfile() {
        isLoading = true
        errorMessage = nil

        var body: [String: Any] = ["full_name": trimmedName, "avatar": ""]
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if !trimmedEmail.isEmpty { body["email"] = trimmedEmail }

        ServiceModel.shared.putRequest(endpoint: WebService.updateProfile, parameters: body) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let data):
                    print("Profile updated:", String(data: data, encoding: .utf8) ?? "")
                    withAnimation { self.isEditing = false }

                case .failure(let error):
                    switch error.responseCode {
                    case 422:
                        self.errorMessage = "Invalid input. Please check your name and email."
                    case 400:
                        self.errorMessage = "Bad request. Please review your information."
                    default:
                        self.errorMessage = "Failed to update profile. Please try again."
                    }
                }
            }
        }
    }
}




struct StatCardProfile: View {
    let icon: String
    let value: String
    let label: String
    var modifierPadding: CGFloat = 14
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(modifierPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
    }
}


struct Badge: View {
    let icon: String?
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct ProfileMenuItem: View {
    let icon: String
    let label: String
    var gradient: [Color] = [Color.purple, Color.blue]
    var badgeCount: Int = 0
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            content
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
            }

            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gray.opacity(0.8))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.85))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}


#Preview {
    ProfileView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
