//
//  SAAYRApp.swift
//  SAAYR
//
//  Created by Awais Raza on 19/12/2025.
//

import SwiftUI
import AppTrackingTransparency

@main
struct SAAYRApp: App {
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var userManager = UserManager()
    @StateObject private var authManager = AuthManager()


    @Environment(\.scenePhase) private var scenePhase
    @State private var trackingRequested = false

    var body: some Scene {

        WindowGroup {
            Group {
                if authManager.authState == .authenticated {
                    ContentView()
                        .environmentObject(languageManager)
                        .environmentObject(userManager)
                        .environmentObject(authManager)
                        .environment(\.layoutDirection, languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight)
                } else {
                    AuthenticationFlow()
                        .environmentObject(languageManager)
                        .environmentObject(authManager)
                        .environment(\.layoutDirection, languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight)
                }
            }
            .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && !trackingRequested {
                trackingRequested = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    requestTrackingPermission()
                }
            }
        }
    }

    private func requestTrackingPermission() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                switch status {
                case .authorized:
                    print("ATT: Tracking authorized")
                case .denied:
                    print("ATT: Tracking denied")
                case .restricted:
                    print("ATT: Tracking restricted")
                case .notDetermined:
                    print("ATT: Not determined")
                @unknown default:
                    break
                }
            }
        }
    }
}
