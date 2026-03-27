//
//  SAAYRApp.swift
//  SAAYR
//
//  Created by Awais Raza on 19/12/2025.
//

import SwiftUI

@main
struct SAAYRApp: App {
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var userManager = UserManager()
    @StateObject private var authManager = AuthManager()
    
    
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
    }
}
