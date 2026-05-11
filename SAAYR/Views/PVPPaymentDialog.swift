import SwiftUI
import MoyasarSdk

extension String: @retroactive Identifiable {
    public var id: String { self }
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

    @State private var creditCardItem: CreditCardPaymentItem? = nil
    @State private var paymentError: String? = nil
    @State private var showErrorAlert = false
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
            ServiceModel.shared.fetchPVPInfo { result in
                DispatchQueue.main.async {
                    isLoadingInfo = false
                    if case .success(let info) = result { pvpInfo = info }
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
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#F3F4F6"))
                        .frame(width: 48, height: 36)
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "#6B7280"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Credit / Debit Card")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                    Text("Visa, Mastercard, Mada")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#6B7280"))
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#9CA3AF"))
                Text("Secure payment")
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

    private var orderedRewards: [PVPReward] {
        guard let rewards = pvpInfo?.rewards else { return [] }
        let order = ["winner", "mission", "loser"]
        return order.compactMap { type in rewards.first { $0.type == type } }
    }

    private func rewardColor(for index: Int) -> Color {
        switch index {
        case 0: return Color(hex: "#16A34A")
        case 1: return Color(hex: "#2563EB")
        default: return Color(hex: "#F97316")
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

    private var joinBattleButton: some View {
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

    // MARK: - Payment Actions

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
                matchFlowPaymentId = payment.id
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

// MARK: - Credit Card Payment Sheet

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
