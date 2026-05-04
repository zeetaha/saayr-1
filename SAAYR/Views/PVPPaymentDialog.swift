import SwiftUI
import MoyasarSdk
import PassKit

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Payment Method Enum

enum PVPPaymentMethod {
    case card
    case applePay
}

// Wraps PaymentRequest so it can be used with .sheet(item:),
// guaranteeing the request is non-nil when the sheet renders.
private struct CreditCardPaymentItem: Identifiable {
    let id = UUID()
    let request: PaymentRequest
}

// MARK: - PVPPaymentDialog

struct PVPPaymentDialog: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var userManager: UserManager

    @State private var selectedMethod: PVPPaymentMethod = PKPaymentAuthorizationController.canMakePayments() ? .applePay : .card
    @State private var showPaymentMethod = false
    @State private var creditCardItem: CreditCardPaymentItem? = nil
    @State private var paymentError: String? = nil
    @State private var showErrorAlert = false
    @State private var applePayHandler = PVPApplePayHandler()
    @State private var matchFlowPaymentId: String? = nil

    @State private var pvpInfo: PVPInfoResponse? = nil
    @State private var isLoadingInfo = true

    private var entryFeeAmount: Int { (pvpInfo?.entry_fee.amount_sar ?? 5) * 100 }
    private var entryFeeSAR: Int { pvpInfo?.entry_fee.amount_sar ?? 5 }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "#F5F5F5").ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack() {
                        headerView
                        VStack(spacing: 16) {
                            entryFeeCard
                            paymentMethodCard
                            winRewardsCard

                            joinBattleButton

                            Button {
                                isPresented = false
                            } label: {
                                Text("Cancel")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: "#6B7280"))
                            }
                            .padding(.bottom, 32)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
        }
        .onAppear {
            applePayHandler.onResult = { success, paymentId, errorMsg in
                if success, let pid = paymentId {
                    startMatchFlow(paymentId: pid)
                } else {
                    paymentError = errorMsg ?? "Apple Pay failed. Please try again."
                    showErrorAlert = true
                }
            }
            ServiceModel.shared.fetchPVPInfo { result in
                DispatchQueue.main.async {
                    isLoadingInfo = false
                    if case .success(let info) = result { pvpInfo = info }
                }
            }
        }
        .sheet(isPresented: $showPaymentMethod) {
            PaymentMethodView(
                isPresented: $showPaymentMethod,
                selectedMethod: $selectedMethod,
                amountSAR: entryFeeSAR
            ) {
                showPaymentMethod = false
                // Wait for the PaymentMethodView sheet to fully dismiss before
                // presenting the next UI. Triggering either sheet or Apple Pay
                // while the previous sheet is still animating out causes blank
                // content or a silent failure to present.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if selectedMethod == .card {
                        if let req = makePVPPaymentRequest() {
                            creditCardItem = CreditCardPaymentItem(request: req)
                        }
                    } else {
                        triggerApplePay()
                    }
                }
            }
        }
        .sheet(item: $creditCardItem) { item in
            CreditCardPaymentSheet(
                request: item.request,
                onResult: handlePaymentResult,
                onCancel: { creditCardItem = nil }
            )
        }
        .alert("Payment Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(paymentError ?? "Something went wrong. Please try again.")
        }
        .fullScreenCover(item: $matchFlowPaymentId) { paymentId in
            PVPMatchFlowView(
                paymentId: paymentId,
                entryFeeSAR: entryFeeSAR,
                isPresented: Binding(
                    get: { matchFlowPaymentId != nil },
                    set: { if !$0 { matchFlowPaymentId = nil } }
                )
            )
            .environmentObject(userManager)
            .onDisappear {
                isPresented = false
            }
        }
    }

    // MARK: - startMatchFlow

    private func startMatchFlow(paymentId: String) {
        matchFlowPaymentId = paymentId
    }

    // MARK: - Header

    private var headerView: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                HStack {
                    Button { isPresented = false } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 72, height: 72)
                    Text("⚔️")
                        .font(.system(size: 32))
                }

                Text("Join PVP Battle")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("Compete against another player")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Entry Fee Card

    private var entryFeeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Entry Fee")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#92400E"))

            if isLoadingInfo {
                ProgressView()
                    .padding(.vertical, 8)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entryFeeSAR)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.black)
                    Text("SAR")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "#374151"))
                }

                if let winnerReward = pvpInfo?.rewards.first(where: { $0.type == "winner" }),
                   let xp = winnerReward.xp {
                    Text("Win up to \(xp) XP!")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#16A34A"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: "#FFFBEB"))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "#FDE68A"), lineWidth: 1)
        )
    }

    // MARK: - Payment Method Card

    private var paymentMethodCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#F3F4F6"))
                        .frame(width: 48, height: 36)
                    if selectedMethod == .applePay {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.black)
                    } else {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "#6B7280"))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedMethod == .applePay ? "Apple Pay" : "Credit / Debit Card")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                    Text("Payment method")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#6B7280"))
                }

                Spacer()

                Button {
                    showPaymentMethod = true
                } label: {
                    Text("Change")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "#16A34A"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#DCFCE7"))
                        .cornerRadius(20)
                }
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#9CA3AF"))
                Text("Secure payment methods")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#9CA3AF"))
                Spacer()
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: - Win Rewards Card

    // Display order: winner → mission → loser
    private var orderedRewards: [PVPReward] {
        guard let rewards = pvpInfo?.rewards else { return [] }
        let order = ["winner", "mission", "loser"]
        return order.compactMap { type in rewards.first { $0.type == type } }
    }

    private func rewardColor(for index: Int) -> Color {
        switch index {
        case 0: return Color(hex: "#16A34A") // winner — green
        case 1: return Color(hex: "#2563EB") // mission — blue
        default: return Color(hex: "#F97316") // loser — orange
        }
    }

    private var winRewardsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Win Rewards")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "#16A34A"))

            if isLoadingInfo {
                ProgressView().padding(.vertical, 4)
            } else {
                ForEach(Array(orderedRewards.enumerated()), id: \.offset) { index, reward in
                    rewardRow(number: "\(index + 1)",
                              color: rewardColor(for: index),
                              message: reward.message)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: "#F0FDF4"))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "#BBF7D0"), lineWidth: 1)
        )
    }

    private func rewardRow(number: String, color: Color, message: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#374151"))
            Spacer()
        }
    }

    // MARK: - Join Battle Button

    @ViewBuilder
    private var joinBattleButton: some View {
        if selectedMethod == .applePay {
            // Native PKPaymentButton for Apple Pay
            ApplePayJoinButton {
                triggerApplePay()
            }
            .frame(height: 56)
            .cornerRadius(16)
            .padding(.top, 8)
        } else {
            Button {
                if let req = makePVPPaymentRequest() {
                    creditCardItem = CreditCardPaymentItem(request: req)
                }
            } label: {
                Text("Join Battle — \(entryFeeSAR) SAR")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Payment Actions

    private func triggerApplePay() {
        guard let request = makePVPPaymentRequest() else { return }
        applePayHandler.present(request: request)
    }

    private func makePVPPaymentRequest() -> PaymentRequest? {
        do {
            return try PaymentRequest(
                apiKey: WebService.moyasarPublishableKey,
                amount: entryFeeAmount,
                currency: "SAR",
                description: "PVP Battle Entry Fee-mobile",
                metadata: ["user_id": .integerValue(UserModel.shared.user?.id ?? 0)],
                manual: true
            )
        } catch {
            paymentError = "Invalid payment configuration. Please contact support."
            showErrorAlert = true
            return nil
        }
    }

    private func handlePaymentResult(_ result: PaymentResult) {
        creditCardItem = nil
        switch result {
        case let .completed(payment):
            if payment.status == .authorized {
                startMatchFlow(paymentId: payment.id)
            } else {
                if case let .creditCard(source) = payment.source {
                    paymentError = source.message ?? "Payment was not completed."
                } else {
                    paymentError = "Payment was not completed."
                }
                showErrorAlert = true
            }
        case .canceled:
            break
        case let .failed(error):
            if case let .apiError(apiError) = error {
                paymentError = apiError.message ?? "Payment failed. Please try again."
            } else {
                paymentError = "Payment failed. Please try again."
            }
            showErrorAlert = true
        case .saveOnlyToken:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Payment Method View

struct PaymentMethodView: View {
    @Binding var isPresented: Bool
    @Binding var selectedMethod: PVPPaymentMethod
    var amountSAR: Int = 5
    var onContinue: () -> Void

    private let canUseApplePay = PKPaymentAuthorizationController.canMakePayments()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Payment Method")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                    Text("Choose how you'd like to pay \(amountSAR) SAR")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#6B7280"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)

                VStack(spacing: 12) {
                    // Credit / Debit Card option
                    methodRow(
                        icon: "creditcard.fill",
                        iconColor: Color(hex: "#6B7280"),
                        title: "Credit / Debit Card",
                        subtitle: "Visa, Mastercard, Mada",
                        method: .card
                    )

                    // Apple Pay option (only if device supports it)
                    if canUseApplePay {
                        methodRow(
                            icon: "apple.logo",
                            iconColor: .black,
                            title: "Apple Pay",
                            subtitle: "Touch ID or Face ID",
                            method: .applePay
                        )
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(hex: "#F5F5F5").ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text("Back")
                        }
                        .foregroundColor(Color(hex: "#374151"))
                        .font(.system(size: 15))
                    }
                }
            }
        }
    }

    private func methodRow(icon: String, iconColor: Color,
                           title: String, subtitle: String,
                           method: PVPPaymentMethod) -> some View {
        let isSelected = selectedMethod == method
        return Button {
            selectedMethod = method
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#F3F4F6"))
                        .frame(width: 48, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#6B7280"))
                }

                Spacer()

                Image(systemName: isSelected ? "record.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Color(hex: "#EF4444") : Color(hex: "#D1D5DB"))
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: "#EF4444") : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Apple Pay Handler

final class PVPApplePayHandler: NSObject, PKPaymentAuthorizationControllerDelegate {
    var onResult: ((Bool, String?, String?) -> Void)?

    private var applePayService: ApplePayService?
    private var controller: PKPaymentAuthorizationController?
    private var pendingPaymentRequest: PaymentRequest?
    private var pendingResult: (Bool, String?, String?)? = nil

    func present(request: PaymentRequest) {
        pendingPaymentRequest = request

        do {
            applePayService = try ApplePayService(apiKey: request.apiKey, baseUrl: request.baseUrl)
        } catch {
            onResult?(false, nil, "Failed to initialize Apple Pay.")
            return
        }

        let pkRequest = PKPaymentRequest()
        pkRequest.merchantIdentifier = WebService.applePayMerchantId
        pkRequest.countryCode = "SA"
        pkRequest.currencyCode = request.currency
        pkRequest.supportedNetworks = [.visa, .masterCard, .mada]
        pkRequest.merchantCapabilities = [.capability3DS, .capabilityCredit, .capabilityDebit]

        let merchantName = "SAAYR"
        let majorAmount = NSDecimalNumber(value: Double(request.amount) / 100.0)
        pkRequest.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "\(merchantName) Battle Entry Fee", amount: majorAmount, type: .final)
        ]

        controller = PKPaymentAuthorizationController(paymentRequest: pkRequest)
        controller?.delegate = self
        controller?.present()
    }

    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                        didAuthorizePayment payment: PKPayment,
                                        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        guard let request = pendingPaymentRequest, let service = applePayService else {
            pendingResult = (false, nil, "Apple Pay configuration error.")
            completion(PKPaymentAuthorizationResult(status: .failure, errors: []))
            return
        }

        Task {
            do {
                let apiPayment = try await service.authorizePayment(request: request, token: payment.token)
                await MainActor.run {
                    print("apiPayment : \(apiPayment)")
                    if apiPayment.status == .authorized {
                        pendingResult = (true, apiPayment.id, nil)
                        completion(PKPaymentAuthorizationResult(status: .success, errors: []))
                    } else {
                        let msg: String
                        if case let .applePay(source) = apiPayment.source {
                            msg = source.message ?? "Payment failed."
                        } else {
                            msg = "Payment failed."
                        }
                        pendingResult = (false, nil, msg)
                        completion(PKPaymentAuthorizationResult(status: .failure, errors: []))
                    }
                }
            } catch {
                await MainActor.run {
                    pendingResult = (false, nil, error.localizedDescription)
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                }
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {
            if let result = self.pendingResult {
                DispatchQueue.main.async {
                    self.onResult?(result.0, result.1, result.2)
                }
                self.pendingResult = nil
            }
        }
    }
}

// MARK: - Apple Pay Join Button

struct ApplePayJoinButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .plain, paymentButtonStyle: .black)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {}
}

// MARK: - Credit Card Payment Sheet

/// Owns CreditCardViewModel as @StateObject so parent re-renders never
/// recreate the view model and wipe entered card details.
private struct CreditCardPaymentSheet: View {
    @StateObject private var viewModel: CreditCardViewModel
    let onCancel: () -> Void

    init(request: PaymentRequest,
         onResult: @escaping ResultCallback,
         onCancel: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: CreditCardViewModel(
            paymentRequest: request,
            resultCallback: onResult
        ))
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationView {
            CreditCardView(viewModel: viewModel)
                .navigationTitle("Payment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
        }
    }
}

#Preview {
    PVPPaymentDialog(isPresented: .constant(true))
        .environmentObject(LanguageManager())
        .environmentObject(UserManager())
}
