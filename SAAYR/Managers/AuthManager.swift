import Foundation
import SwiftUI
import Combine
import Alamofire

enum AuthState {
    case onboarding
    case phoneEntry
    case otpVerification
    case profileSetup
    case authenticated
    case pinFlow
    case petName
    case login
    case forgotPasscode
    case resetPasscode
    case resetOtp
}

class AuthManager: ObservableObject {
    @Published var authState: AuthState
    @Published var phoneNumber: String = ""
    @Published var countryCode: String = "+966" // Saudi Arabia default
    @Published var otpCode: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isBlockedAlert: Bool = false
    @Published var blockedMessage: String = "Your account has been blocked. Please contact support."
    
    // Temporary storage for profile setup
    @Published var tempFullName: String = ""
    @Published var tempEmail: String = ""
    @Published var tempPetName: String = ""
    @Published var tempPetType: String = ""
    @Published var tempPasscode: String = ""
    
    @Published var otp: String?
    
    
    init() {
        // Check if user is already authenticated
        if UserDefaults.standard.bool(forKey: "isAuthenticated") {
            self.authState = .authenticated
        } else if UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
            self.authState = .phoneEntry
        } else {
            self.authState = .onboarding
        }

        NotificationCenter.default.addObserver(
            forName: .userAccountBlocked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.logout()
            self.blockedMessage = notification.object as? String
                ?? "Your account has been blocked. Please contact support."
            self.isBlockedAlert = true
        }
    }
    
    
    
    func sendOTP() {
        isLoading = true
        otp = nil
        errorMessage = nil
        
        let parameters: [String: Any] = [
            "phone_number": "966" + phoneNumber
        ]
        
        print("➡️ Auth State:", self.authState)
        print("➡️ Endpoint:", self.authState == .forgotPasscode
              ? WebService.forgotPasscode
              : WebService.sendOtp)
        
        ServiceModel.shared.postRequest(endpoint: self.authState == .forgotPasscode ? WebService.forgotPasscode : WebService.sendOtp ,
                                        parameters: parameters) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let data):
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            
                            if let otp = json["otp"] as? String {
                                self.otp = otp
                                print("✅ OTP:", otp)
                                self.authState = self.authState == .forgotPasscode ? .resetPasscode : .otpVerification
                                
                                
                            } else {
                                self.errorMessage = json["message"] as? String ?? "Unexpected response"
                                print("❌ Error:", self.errorMessage ?? "")
                            }
                        }
                    } catch {
                        self.errorMessage = error.localizedDescription
                        print("❌ Parsing Error:", error.localizedDescription)
                    }
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    print("❌ API Error:", error.localizedDescription)
                }
            }
        }
    }
    
    
    func verifyOTP(otp: String, onResult: @escaping (_ isNewUser: Bool) -> Void) {
        isLoading = true
        errorMessage = nil
        
        var parameters: [String: Any] = [
            "phone_number": "966" + phoneNumber,
            "otp": otp
        ]
        
        
        if self.authState == .resetOtp {
            parameters["new_passcode"] = tempPasscode
            
            ServiceModel.shared.postRequest(
                endpoint: WebService.resetPasscode,
                parameters: parameters
            ) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success(let data):
                        do {
                            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                
                                let success = json["success"] as? Bool ?? false
                                let message = json["message"] as? String ?? "Something went wrong"
                                
                                if success {
                                    print("✅ Passcode Reset Success:", message)
                                    
                                    // Clear temp passcode
                                    self.tempPasscode = ""
                                    
                                    self.authState = .login
                                } else {
                                    self.errorMessage = message
                                    print("❌ Reset Failed:", message)
                                }
                            }
                        } catch {
                            self.errorMessage = error.localizedDescription
                            print("❌ Parsing Error:", error.localizedDescription)
                        }
                        
                    case .failure(let error):
                        self.errorMessage = self.extractErrorMessage(from: error) ?? error.localizedDescription
                        print("❌ API Error:", self.errorMessage ?? "")
                    }
                }
            }
        }
        else{
            ServiceModel.shared.postRequest(endpoint: WebService.verifyOtp,
                                            parameters: parameters) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success(let data):
                        do {
                            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                
                                let success = json["success"] as? Bool ?? false
                                if success, let data = json["data"] as? [String: Any] {
                                    let isNewUser = data["is_new_user"] as? Bool ?? false
                                    let userId = data["user_id"] as? Int
                                    
                                    print("✅ OTP Verified")
                                    print("🆕 Is New User:", isNewUser)
                                    print("👤 User ID:", userId ?? -1)
                                    
                                    onResult(isNewUser)
                                    
                                } else {
                                    // ✅ HERE json exists
                                    self.errorMessage = json["message"] as? String ?? "OTP failed"
                                    print("❌ OTP Failed:", self.errorMessage ?? "")
                                }
                            }
                        } catch {
                            self.errorMessage = error.localizedDescription
                            print("❌ Parsing Error:", error.localizedDescription)
                        }
                        
                    case .failure(let error):
                        self.errorMessage = self.extractErrorMessage(from: error) ?? error.localizedDescription
                        print("❌ API Error:", self.errorMessage ?? "")
                    }
                }
            }
        }
        
        
    }
    
    
    
    func completeSignup(onSuccess: @escaping () -> Void) {
        guard !tempFullName.isEmpty, !tempPasscode.isEmpty else { return }
        guard tempEmail.isEmpty || tempEmail.contains("@") else { return }
        
        isLoading = true
        errorMessage = nil
        
        // Prepare parameters
        var parameters: [String: Any] = [
            "phone_number": "966" + phoneNumber,
            "full_name": tempFullName,
            "email": tempEmail,
            "passcode": tempPasscode
        ]
        
        
        
        
        ServiceModel.shared.postRequest(
            endpoint: WebService.completeSignup,
            parameters: parameters,
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let data):
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            
                            if let accessToken = json["access_token"] as? String,
                               let tokenType = json["token_type"] as? String,
                               let userId = json["user_id"] as? Int {
                                
                                print("✅ Signup Success")
                                print("Access Token:", accessToken)
                                print("Token Type:", tokenType)
                                print("User ID:", userId)
                                
                                // Save user data
                                let user = User(
                                    email: self.tempEmail,
                                    firstName: self.tempFullName,
                                    lastName: "",
                                    accessToken: accessToken,
                                    refreshToken: "",
                                    id: userId
                                )
                                UserModel.shared.saveUser(user)
                                
                                // Call success closure for UI navigation
                                onSuccess()
                                
                            } else {
                                self.errorMessage = "Unexpected response from server"
                                print("❌ Error:", self.errorMessage ?? "")
                            }
                            
                        }
                    } catch {
                        self.errorMessage = error.localizedDescription
                        print("❌ Parsing Error:", error.localizedDescription)
                    }
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    print("❌ API Error:", error.localizedDescription)
                }
            }
        }
    }
    
    func completeLogin(onSuccess: @escaping () -> Void) {
        guard !tempPasscode.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        let parameters: [String: Any] = [
            "phone_number": "966" + phoneNumber,
            "passcode": tempPasscode
        ]
        
        ServiceModel.shared.postRequest(
            endpoint: WebService.login,
            parameters: parameters
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let data):
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            
                            // ❌ ERROR CASE (401)
                            if let detail = json["detail"] as? String {
                                self.errorMessage = detail
                                print("❌ Login Failed:", detail)
                                return
                            }
                            
                            // ✅ SUCCESS CASE
                            if let accessToken = json["access_token"] as? String,
                               let tokenType = json["token_type"] as? String,
                               let userId = json["user_id"] as? Int {
                                
                                print("✅ Login Success")
                                
                                let user = User(
                                    email: "",
                                    firstName: "",
                                    lastName: "",
                                    accessToken: accessToken,
                                    refreshToken: "",
                                    id: userId
                                )
                                UserModel.shared.saveUser(user)
                                
                                onSuccess()
                            } else {
                                self.errorMessage = "Unexpected response"
                            }
                        }
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Onboarding
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        withAnimation {
            authState = .phoneEntry
        }
    }
    
    func sendPinFlow() {
        
        isLoading = true
        errorMessage = nil
        
        // Simulate API call to send OTP
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isLoading = false
            
            // In production, this would call your backend API
            // For demo, we'll simulate success
            withAnimation {
                self?.authState = .pinFlow
            }
            
            // For demo purposes - print OTP code (in production, this comes via SMS)
            print("📱 Demo pin Code: 123456")
        }
    }
    
    func validatePhoneNumber() -> Bool {
        // Basic validation - should have at least 9 digits for Saudi numbers
        let digits = phoneNumber.filter { $0.isNumber }
        return digits.count >= 9
    }
    
    // MARK: - OTP Verification
    
    func verifyOTP() {
        guard otpCode.count == 6 else {
            errorMessage = "Please enter the 6-digit code"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Simulate API call to verify OTP
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isLoading = false
            
            // In production, verify with backend
            // For demo, accept "123456" as valid OTP
            if self?.otpCode == "123456" {
                // Check if user exists (has profile)
                let hasProfile = UserDefaults.standard.bool(forKey: "hasProfile")
                
                withAnimation {
                    if hasProfile {
                        // Existing user - go straight to app
                        self?.completeAuthentication()
                    } else {
                        // New user - need profile setup
                        self?.authState = .profileSetup
                    }
                }
            } else {
                self?.errorMessage = "Invalid code. Please try again."
            }
        }
    }
    
    func resendOTP() {
        otpCode = ""
        errorMessage = nil
        sendOTP()
    }
    
    // MARK: - Profile Setup
    
    func completeProfileSetup() {
        guard validateProfileData() else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Save profile data
        UserDefaults.standard.set(tempFullName, forKey: "fullName")
        UserDefaults.standard.set(tempEmail, forKey: "email")
        UserDefaults.standard.set(true, forKey: "hasProfile")
        
        DispatchQueue.main.async {
            self.isLoading = false
            // Complete authentication
            self.sendPinFlow()
        }
    }
    
    func completeSetup() {
        
        
        guard !tempPetName.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        let parameters: [String: Any] = [
            "falcon_name": tempPetName
        ]
        
        ServiceModel.shared.postRequest(
            endpoint: WebService.addFalconName,
            parameters: parameters,
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let data):
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            
                            let success = json["success"] as? Bool ?? false
                            let message = json["message"] as? String ?? "Falcon name update failed"
                            
                            if success {
                                print("✅ Falcon Name Added:", message)
                                // Optionally update tempPetName or save to user model
                                if let data = json["data"] as? [String: Any],
                                   let falconName = data["falcon_name"] as? String {
                                    self.tempPetName = falconName
                                }
                                
                                self.completeAuthentication()
                                
                            } else {
                                self.errorMessage = message
                                print("❌ Error:", message)
                            }
                        }
                    } catch {
                        self.errorMessage = error.localizedDescription
                        print("❌ Parsing Error:", error.localizedDescription)
                    }
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    if let errorCode = error.responseCode , errorCode == 400 {
                        self.errorMessage =  "Falcon name already taken"
                    }
                    print("❌ API Error:", error.localizedDescription)
                }
            }
        }
        
    }
    
    func validateProfileData() -> Bool {
        // Required field
        if tempFullName.isEmpty {
            return false
        }

        // Optional email: validate only if entered
        if !tempEmail.isEmpty && !tempEmail.contains("@") {
            return false
        }

        // Optional future validations
        // if tempPetName.isEmpty { return false }
        // if tempPetType.isEmpty { return false }

        return true
    }
    
    // MARK: - Complete Authentication
    
    func completeAuthentication() {
        UserDefaults.standard.set(true, forKey: "isAuthenticated")
        UserDefaults.standard.set("\(countryCode)\(phoneNumber)", forKey: "phoneNumber")
        
        withAnimation {
            authState = .authenticated
        }
    }
    
    // MARK: - Logout
    
    func logout() {
        UserDefaults.standard.set(false, forKey: "isAuthenticated")
        
        // Clear sensitive data
        phoneNumber = ""
        otpCode = ""
        tempFullName = ""
        tempEmail = ""
        tempPetName = ""
        tempPetType = ""
        
        withAnimation {
            authState = .phoneEntry
        }
    }
    
    // MARK: - Edit Phone Number
    
    func editPhoneNumber() {
        otpCode = ""
        errorMessage = nil
        withAnimation {
            authState = .phoneEntry
        }
    }
    
    // MARK: - Error Handling
    
    private func extractErrorMessage(from error: AFError) -> String? {
        // Provide user-friendly messages based on error codes
        if let code = error.responseCode {
            switch code {
            case 400:
                return "Invalid OTP. Please check your input."
            case 401:
                return "Unauthorized. Please try again."
            case 422:
                return "Invalid OTP or phone number. Please try again."
            case 429:
                return "Too many attempts. Please try again later."
            case 500...599:
                return "Server error. Please try again later."
            default:
                return nil
            }
        }
        return nil
    }
}
