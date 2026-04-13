import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var activeAlert: SettingsAlert? = nil

    enum SettingsAlert: Identifiable {
        case language, logout
        var id: Int { hashValue }
    }
    @State private var showWeb = false
    @State private var selectedURL: URL?

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // General Section
                        VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 8) {
                            Text(languageManager.text("settings.general"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 0) {
                                SettingsRow(
                                    icon: "globe",
                                    label: languageManager.text("settings.language"),
                                    value: languageManager.currentLanguage == .english ? "English" : "العربية",
                                    gradient: [Color.blue, Color.cyan]
                                ) {
                                    activeAlert = .language
                                }
                            }
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Privacy & Security Section
                        VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 8) {
                            Text(languageManager.text("settings.privacy"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 0) {
                                NavigationSettingsRow(
                                    icon: "lock.shield.fill",
                                    label: languageManager.text("settings.privacyPolicy"),
                                    gradient: [Color.purple, Color(hex: "#8B5CF6")]
                                ) {
                                    selectedURL = URL(string: "https://api.saayr.sa/api/v1/legal/privacy-policy")
                                    showWeb = true
                                }
                                .sheet(isPresented: $showWeb) {
                                    if let selectedURL {
                                        SafariView(url: selectedURL)
                                    }
                                }

                                NavigationSettingsRow(
                                    icon: "doc.text.fill",
                                    label: languageManager.text("settings.termsAndConditions"),
                                    gradient: [Color.blue, Color(hex: "#3B82F6")]
                                ) {
                                    selectedURL = URL(string: "https://api.saayr.sa/api/v1/legal/terms-and-conditions")
                                    showWeb = true
                                }

                                
                                Divider()
                                    .padding(.leading, 70)
                                
//                                NavigationSettingsRow(
//                                    icon: "key.fill",
//                                    label: languageManager.text("settings.changePassword"),
//                                    gradient: [Color.orange, Color.red]
//                                )
                            }
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // About Section
                        VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 8) {
                            Text(languageManager.text("settings.about"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 0) {
                                NavigationSettingsRow(
                                    icon: "info.circle.fill",
                                    label: languageManager.text("settings.aboutSaayr"),
                                    gradient: [Color.indigo, Color.blue],
                                    subtitle: "\(languageManager.text("settings.version")) 1.0.0"
                                )
                            }
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
//                        // Logout Section
//                        VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 8) {
//                            Text(languageManager.text("settings.logout"))
//                                .font(.system(size: 13, weight: .semibold))
//                                .foregroundColor(.secondary)
//                                .padding(.horizontal)
//                            
//                            VStack(spacing: 0) {
//                                SettingsRow(
//                                    icon: "arrow.left.circle.fill",
//                                    label: languageManager.text("settings.logout"),
//                                    value: "",
//                                    gradient: [Color.red, Color.orange]
//                                ) {
//                                    showLogoutConfirm = true
//                                }
//                            }
//                            .background(Color(UIColor.secondarySystemGroupedBackground))
//                            .cornerRadius(12)
//                            .padding(.horizontal)
//                        }
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle(languageManager.text("settings.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: languageManager.currentLanguage == .english ? "chevron.left" : "chevron.right")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .environment(\.layoutDirection, languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight)
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .language:
                let target = languageManager.currentLanguage == .english ? "العربية" : "English"
                return Alert(
                    title: Text("Switch Language"),
                    message: Text("Switch app language to \(target)?"),
                    primaryButton: .default(Text("Switch")) {
                        languageManager.toggleLanguage()
                    },
                    secondaryButton: .cancel()
                )
            case .logout:
                return Alert(
                    title: Text(languageManager.text("settings.logout")),
                    message: Text(languageManager.text("settings.logoutConfirm")),
                    primaryButton: .destructive(
                        Text(languageManager.text("settings.logout")),
                        action: {
                            authManager.logout()
                            dismiss()
                        }
                    ),
                    secondaryButton: .cancel()
                )
            }
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let label: String
    let value: String
    let gradient: [Color]
    let action: () -> Void
    @EnvironmentObject var languageManager: LanguageManager
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
                
                Text(label)
                    .font(.system(size: 17))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(value)
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

struct NavigationSettingsRow: View {
    let icon: String
    let label: String
    let gradient: [Color]
    var subtitle: String? = nil
    var action: (() -> Void)? = nil

    @EnvironmentObject var languageManager: LanguageManager

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }

                VStack(
                    alignment: languageManager.currentLanguage == .english ? .leading : .trailing,
                    spacing: 2
                ) {
                    Text(label)
                        .font(.system(size: 17))
                        .foregroundColor(.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}


struct SettingsDetailView: View {
    let title: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var languageManager: LanguageManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 16) {
                Text("This is a placeholder for \(title)")
                    .font(.system(size: 17))
                    .foregroundColor(.primary)
                    .padding()
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environmentObject(LanguageManager())
        .environmentObject(AuthManager())
}
