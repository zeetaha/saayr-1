//
//  SAAYRApp.swift
//  SAAYR
//
//  Created by Awais Raza on 19/12/2025.
//

import SwiftUI
import AppTrackingTransparency
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
  static var notificationsEnabled = false
  
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    
    // Set up messaging delegate
    Messaging.messaging().delegate = self
    UNUserNotificationCenter.current().delegate = self

    #if DEBUG
    // A tap that cold-launches the app is the case `didReceive` alone can't
    // tell you about, so it's logged from the one place that sees it.
    NotificationLogger.launched(with: launchOptions)
    NotificationLogger.dumpSettings()
    #endif

    return true
  }
  
  // MARK: - MessagingDelegate
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let token = fcmToken, AppDelegate.notificationsEnabled else { return }
    print("FCM Token received: \(token)")
    
    // Send token to backend
    DispatchQueue.main.async {
      ServiceModel.shared.updateFcmToken(token) { result in
        switch result {
        case .success:
          print("FCM token sent to backend successfully")
        case .failure(let error):
          print("Failed to send FCM token: \(error)")
        }
      }
    }
  }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("APNs token received")

        Messaging.messaging().apnsToken = deviceToken
    }
    
func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error)")
    }
  
  // MARK: - UNUserNotificationCenterDelegate
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    #if DEBUG
    NotificationLogger.presented(notification)
    #endif
    BossPush.handle(notification.request.content.userInfo)
    completionHandler([.banner, .sound, .badge])
  }
  
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    #if DEBUG
    NotificationLogger.acted(on: response)
    #endif
    BossPush.handle(response.notification.request.content.userInfo)
    completionHandler()
  }
}

@main
struct SAAYRApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var userManager = UserManager()
    @StateObject private var authManager = AuthManager()
    @StateObject private var router = AppRouter()

    @Environment(\.scenePhase) private var scenePhase
    @State private var trackingRequested = false
    @State private var notificationsEnabled = false

    var body: some Scene {

        WindowGroup {
            Group {
                if authManager.authState == .authenticated {
                    ContentView()
                        .environmentObject(languageManager)
                        .environmentObject(userManager)
                        .environmentObject(authManager)
                        .environmentObject(router)
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
                    setupNotifications()

                    #if DEBUG
                    // TEMPORARY: holds the boss live-feed open for the whole
                    // session so its SSE frames keep printing. Delayed so the
                    // token is definitely in place before it authenticates.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        BossLiveFeedDebug.start()
                    }
                    #endif
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
                setupNotifications()
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
    
    /// Request notification permissions and set up FCM
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                AppDelegate.notificationsEnabled = true
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                print("Notification permission granted")
                
                AppDelegate.notificationsEnabled = true

                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }

                        Messaging.messaging().token { token, error in
                            if let error = error {
                                print("FCM token error: \(error)")
                            } else if let token = token {
                                print("FCM token: \(token)")
                            }
                        }
                
            } else if let error = error {
                print("Notification permission denied: \(error)")
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
