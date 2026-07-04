//
//  UserModel.swift
//  lechef
//
//  Created by Awais Raza on 29/09/2024.
//

import Foundation

struct User: Codable {
    var email: String
    var firstName: String
    var lastName: String
    var accessToken: String
    var refreshToken: String
    var id: Int
}

class UserModel {
    static let shared = UserModel() // Singleton instance

    private let userDefaults = UserDefaults.standard
    private let userKey = "savedUser" // Key for storing the user
    private let languageCodeKey = "languageCode" // Key for storing the code
    private let latitudeKey = "Latitude" // Key for storing the code
    private let longitudeKey = "longitude" // Key for storing the code
    private let countryKey = "countryCode" // Key for storing the code

    var user: User? {
        get {
            if let savedUserData = userDefaults.data(forKey: userKey),
               let decodedUser = try? JSONDecoder().decode(User.self, from: savedUserData) {
                return decodedUser
            }
            return nil
        }
        set {
            if let user = newValue {
                if let encodedUser = try? JSONEncoder().encode(user) {
                    userDefaults.set(encodedUser, forKey: userKey)
                }
            } else {
                userDefaults.removeObject(forKey: userKey)
            }
        }
    }
    
    var languageCode: String? {
        get {
            if let savedUserData = userDefaults.data(forKey: languageCodeKey),
               let decodedUser = try? JSONDecoder().decode(String.self, from: savedUserData) {
                return decodedUser
            }
            return "en"
        }
        set {
            if let user = newValue {
                if let encodedUser = try? JSONEncoder().encode(user) {
                    userDefaults.set(encodedUser, forKey: languageCodeKey)
                }
            } else {
                userDefaults.removeObject(forKey: languageCodeKey)
            }
        }
    }
    
    var countryCode: String? {
        get {
            if let savedUserData = userDefaults.data(forKey: countryKey),
               let decodedUser = try? JSONDecoder().decode(String.self, from: savedUserData) {
                return decodedUser
            }
            return ""
        }
        set {
            if let user = newValue {
                if let encodedUser = try? JSONEncoder().encode(user) {
                    userDefaults.set(encodedUser, forKey: countryKey)
                }
            } else {
                userDefaults.removeObject(forKey: countryKey)
            }
        }
    }
    
    var latitude: String? {
        get {
            if let savedUserData = userDefaults.data(forKey: latitudeKey),
               let decodedUser = try? JSONDecoder().decode(String.self, from: savedUserData) {
                return decodedUser
            }
            return "en"
        }
        set {
            if let user = newValue {
                if let encodedUser = try? JSONEncoder().encode(user) {
                    userDefaults.set(encodedUser, forKey: latitudeKey)
                }
            } else {
                userDefaults.removeObject(forKey: latitudeKey)
            }
        }
    }
    var longitude: String? {
        get {
            if let savedUserData = userDefaults.data(forKey: longitudeKey),
               let decodedUser = try? JSONDecoder().decode(String.self, from: savedUserData) {
                return decodedUser
            }
            return "en"
        }
        set {
            if let user = newValue {
                if let encodedUser = try? JSONEncoder().encode(user) {
                    userDefaults.set(encodedUser, forKey: longitudeKey)
                }
            } else {
                userDefaults.removeObject(forKey: languageCodeKey)
            }
        }
    }
    
    /// Returns the most current access token:
    /// prefers the Keychain‑stored token (refreshed by TokenManager),
    /// falls back to the UserDefaults token (legacy / first launch).
    var currentAccessToken: String? {
        TokenManager.shared.accessToken ?? user?.accessToken
    }

    // Private init prevents direct instantiation
    private init() {}
    
    // Save user manually
    func saveUser(_ user: User) {
        self.user = user
        print("User saved globally: \(user.firstName)")
    }
    
    // Remove user
    func removeUser() {
        self.user = nil
        print("User removed globally")
    }
}
//UserManager.shared.removeUser()

