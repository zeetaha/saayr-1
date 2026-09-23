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
import os

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
  static var notificationsEnabled = false
  
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    MapPreferences.registerDefaults()
    
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
    guard let token = fcmToken, AppDelegate.notificationsEnabled else {
      // Usually fires at launch, before permission is confirmed — the token
      // is uploaded from setupNotifications() instead.
      HealthKitManager.log.log("🔑 FCM token arrived before permission — upload deferred")
      return
    }
    AppDelegate.uploadFcmToken(token)
  }

  /// Every path that obtains a token sends it here, so the backend always
  /// pushes to this install and not one from an earlier build.
  static func uploadFcmToken(_ token: String) {
    HealthKitManager.log.log("🔑 FCM token: \(token, privacy: .public)")
    DispatchQueue.main.async {
      ServiceModel.shared.updateFcmToken(token) { result in
        switch result {
        case .success:
          HealthKitManager.log.log("🔑 FCM token sent to backend")
        case .failure(let error):
          HealthKitManager.log.error("🔑 FCM token upload FAILED: \(String(describing: error), privacy: .public)")
        }
      }
    }
  }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        HealthKitManager.log.log("🍎 APNs registered, device token \(deviceToken.map { String(format: "%02x", $0) }.joined(), privacy: .public)")

        Messaging.messaging().apnsToken = deviceToken

        // Only now can Firebase mint a token — asking any earlier fails with
        // "No APNS token specified before fetching FCM Token".
        Messaging.messaging().token { token, error in
            if let error {
                HealthKitManager.log.error("🔑 FCM token error: \(error.localizedDescription, privacy: .public)")
            } else if let token {
                AppDelegate.uploadFcmToken(token)
            }
        }
    }
    
func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Commonly "no valid aps-environment entitlement" — a signing problem.
        HealthKitManager.log.error("🍎 APNs registration FAILED: \(error.localizedDescription, privacy: .public)")
    }

  // MARK: - Silent push
  /// Background pushes (`content-available: 1`) land here, not in the
  /// UNUserNotificationCenter delegate. The backend sends
  /// `{"type": "steps_sync", "from": "yyyy-MM-dd", "to": "yyyy-MM-dd"}`
  /// (both dates optional, default today) to pull steps on demand.
  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    Messaging.messaging().appDidReceiveMessage(userInfo)
    // Every data push, so "did anything arrive?" has an answer in Console.app
    // even when the type isn't one handled here.
    HealthKitManager.log.log("📬 Data push received, type=\(userInfo["type"] as? String ?? "(none)", privacy: .public) keys=\(userInfo.keys.map { "\($0)" }.sorted().joined(separator: ","), privacy: .public)")
    guard (userInfo["type"] as? String) == "steps_sync" else {
      completionHandler(.noData)
      return
    }
    StepsSyncPush.handle(userInfo, completion: completionHandler)
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
    /// Holds an invite link from the moment it arrives until a screen acts on
    /// it — which may be several seconds and a whole sign-in later.
    @StateObject private var invites = InviteLinkCoordinator()

    @Environment(\.scenePhase) private var scenePhase
    @State private var trackingRequested = false
    @State private var notificationsEnabled = false

    var body: some Scene {

        WindowGroup {
            Group {
                if authManager.authState == .authenticated {
                    ContentView()
                        .environmentObject(invites)
                        .environmentObject(languageManager)
                        .environmentObject(userManager)
                        .environmentObject(authManager)
                        .environmentObject(router)
                        .environment(\.layoutDirection, languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight)
                } else {
                    AuthenticationFlow()
                        .environmentObject(invites)
                        .environmentObject(languageManager)
                        .environmentObject(authManager)
                        .environment(\.layoutDirection, languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight)
                }
            }
            .preferredColorScheme(.light)
            // A universal link reaches a SwiftUI app through both of these,
            // and a cold launch can fire both for the same tap. The
            // coordinator drops the duplicate.
            .onOpenURL { url in
                openInvite(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                openInvite(url)
            }
            .onAppear {
                // If the app launches already authenticated (token persisted),
                // start HealthKit tracking immediately.
                if authManager.authState == .authenticated {
                    setupHealthKit()
                    setupNotifications()

                    #if DEBUG
                    // TEMPORARY: holds the boss live-feed open while a boss
                    // is live so its SSE frames keep printing. Delayed so the
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
                    #if DEBUG
                    BossLiveFeedDebug.start()
                    #endif
                }
            } else if phase == .background || phase == .inactive {
                HealthKitManager.shared.stopLiveTracking()
                #if DEBUG
                BossLiveFeedDebug.stop()
                #endif
            }
        }
        .onChange(of: authManager.authState) { state in
            if state == .authenticated {
                setupHealthKit()
                setupNotifications()
                // A link tapped by a signed-out player waited through the
                // whole phone-and-OTP flow to get here.
                invites.redeemIfPending(isEnglish: languageManager.currentLanguage == .english)
            } else {
                // User logged out — stop receiving HealthKit background wakes
                HealthKitManager.shared.stopBackgroundDelivery()
                #if DEBUG
                BossLiveFeedDebug.stop()
                #endif
            }
        }
    }

    private func openInvite(_ url: URL) {
        invites.handle(
            url,
            isAuthenticated: authManager.authState == .authenticated,
            isEnglish: languageManager.currentLanguage == .english
        )
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
                HealthKitManager.log.log("🔔 Notification permission granted — registering with APNs")
                // The FCM token is fetched and uploaded once APNs answers, in
                // didRegisterForRemoteNotificationsWithDeviceToken.
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }

            } else {
                // Without this, registerForRemoteNotifications is never
                // called, so no push of any kind — silent included — arrives.
                HealthKitManager.log.error("🔕 Notification permission not granted: \(error?.localizedDescription ?? "denied", privacy: .public)")
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
