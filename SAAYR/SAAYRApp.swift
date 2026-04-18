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
            .onAppear {
                // If the app launches already authenticated (token persisted),
                // start HealthKit tracking immediately.
                if authManager.authState == .authenticated {
                    setupHealthKit()
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                if !trackingRequested {
                    trackingRequested = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        requestTrackingPermission()
                    }
                }
                if authManager.authState == .authenticated {
                    HealthKitManager.shared.startLiveTracking()
                }
            } else if phase == .background || phase == .inactive {
                HealthKitManager.shared.stopLiveTracking()
            }
        }
        .onChange(of: authManager.authState) { state in
            if state == .authenticated {
                setupHealthKit()
            } else {
                // User logged out — stop receiving HealthKit background wakes
                HealthKitManager.shared.stopBackgroundDelivery()
            }
        }
    }

    /// Request HealthKit authorization then enable background step delivery.
    private func setupHealthKit() {
        HealthKitManager.shared.requestAuthorization { granted in
            guard granted else { return }
            HealthKitManager.shared.setupBackgroundDelivery()
            // Send today's steps immediately on first open
            HealthKitManager.shared.fetchAndSendTodaySensorSteps()
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
