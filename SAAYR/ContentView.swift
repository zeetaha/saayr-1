import SwiftUI

struct ContentView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager
    @State private var selectedTab = 0
    @State private var showPVPPayment = false

    var body: some View {
        VStack(spacing: 0) {
            if userManager.activeMatchStatus {
                ActivePVPBanner {
                    showPVPPayment = true
                }
                .background(Color(.systemBackground))
            }

            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label(languageManager.text("nav.home"), systemImage: "house.fill")
                    }
                    .tag(0)

                ChallengesView()
                    .tabItem {
                        Label(languageManager.text("nav.challenges"), systemImage: "target")
                    }
                    .tag(1)

                MapView()
                    .tabItem {
                        Label(languageManager.text("nav.map"), systemImage: "map.fill")
                    }
                    .tag(2)

                RewardsView()
                    .tabItem {
                        Label(languageManager.text("nav.rewards"), systemImage: "gift.fill")
                    }
                    .tag(3)

                ProfileView()
                    .tabItem {
                        Label(languageManager.text("nav.profile"), systemImage: "person.fill")
                    }
                    .tag(4)
            }
            .accentColor(.blue)
        }
        .fullScreenCover(isPresented: $showPVPPayment) {
            PVPPaymentDialog(isPresented: $showPVPPayment)
        }
    }

    private func safeAreaTop() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 0
    }
}

#Preview {
    ContentView()
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
