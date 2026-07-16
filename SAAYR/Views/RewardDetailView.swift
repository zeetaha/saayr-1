//
//  RewardDetailView.swift
//  SAAYR
//
//  Created by Awais Raza on 05/07/2026.
//

import SwiftUI

struct RewardDetailView: View {
    @Environment(\.dismiss) var dismiss
    let redemption: Redemption
    
    @State private var detailedRedemption: Redemption?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copiedCode = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#F5F3FF"),
                    Color(hex: "#FAF5FF"),
                    Color(hex: "#FDF2F8")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    
                    Text("Reward Details")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                    
                    Spacer()
                }
                .padding()
                .background(Color.white.opacity(0.95))
                .shadow(radius: 2)
                
                if isLoading {
                    VStack {
                        ProgressView()
                            .tint(Color(hex: "#8B5CF6"))
                        Text("Loading details...")
                            .foregroundColor(.gray)
                            .padding(.top, 12)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    let data = detailedRedemption ?? redemption
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            // MARK: Icon & Title
                            VStack(spacing: 16) {
                                if let urlString = data.imageUrl, let url = URL(string: urlString) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            ZStack {
                                                LinearGradient(
                                                    colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                                ProgressView()
                                                    .tint(.white)
                                            }
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        case .failure(_):
                                            ZStack {
                                                LinearGradient(
                                                    colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                                Image(systemName: "gift.fill")
                                                    .font(.system(size: 56, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                        @unknown default:
                                            ZStack {
                                                LinearGradient(
                                                    colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                                Image(systemName: "gift.fill")
                                                    .font(.system(size: 56, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .frame(width: 100, height: 100)
                                    .cornerRadius(20)
                                    .clipped()
                                } else {
                                    ZStack {
                                        LinearGradient(
                                            colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        Image(systemName: "gift.fill")
                                            .font(.system(size: 56, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 100, height: 100)
                                    .cornerRadius(20)
                                }
                                
                                VStack(spacing: 8) {
                                    Text(data.rewardTitle ?? "")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.black)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.center)
                                    
                                    Text(data.merchantName ?? "")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(16)
                            .padding()
                            
                            // MARK: Status & Type
                            HStack(spacing: 12) {
                                DetailStatusBadge(
                                    title: "Status",
                                    value: data.status?.uppercased() ?? "UNKNOWN",
                                    color: statusColor(data.status ?? "")
                                )
                                
                                DetailStatusBadge(
                                    title: "Type",
                                    value: data.rewardType?.uppercased() ?? "N/A",
                                    color: Color(hex: "#3B82F6")
                                )
                            }
                            .padding(.horizontal)
                            
                            // MARK: Redemption Code
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Redemption Code")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.gray)
                                    
                                    Spacer()
                                    
                                    Button(action: copyCode) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(hex: "#8B5CF6"))
                                    }
                                }
                                
                                HStack {
                                    Text(data.redemptionCode ?? "Not available")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    if copiedCode {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .semibold))
                                            Text("Copied")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        .foregroundColor(Color(hex: "#10B981"))
                                        .transition(.opacity)
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(10)
                            }
                            .padding()
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(16)
                            .padding(.horizontal)
                            
                            // MARK: Details
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Details")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.gray)
                                
                                DetailRow(
                                    label: "XP Spent",
                                    value: "\(data.xpSpent ?? 0) XP"
                                )
                                
                                DetailRow(
                                    label: "Claimed",
                                    value: formatDate(data.claimedAt ?? "")
                                )
                                
                                if let redeemedAt = data.redeemedAt, !redeemedAt.isEmpty {
                                    DetailRow(
                                        label: "Redeemed",
                                        value: formatDate(redeemedAt)
                                    )
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(16)
                            .padding(.horizontal)
                            
                            // MARK: Instructions
                            if let instructions = data.redemptionInstructions, !instructions.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Instructions")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.gray)
                                    
                                    Text(instructions)
                                        .font(.system(size: 13))
                                        .foregroundColor(.black)
                                        .lineLimit(nil)
                                }
                                .padding()
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(16)
                                .padding(.horizontal)
                            }
                            
                            Spacer(minLength: 20)
                        }
                        .padding(.vertical)
                    }
                }
                
                if let error = errorMessage {
                    VStack {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            fetchRedemptionDetail()
        }
    }
    
    private func fetchRedemptionDetail() {
        isLoading = true
        errorMessage = nil
        
        ServiceModel.shared.fetchRedemptionDetail(id: redemption.id) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let detail):
                    detailedRedemption = detail
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func copyCode() {
        let data = detailedRedemption ?? redemption
        guard let code = data.redemptionCode, !code.isEmpty else { return }
        UIPasteboard.general.string = code
        
        withAnimation(.easeInOut(duration: 0.3)) {
            copiedCode = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                copiedCode = false
            }
        }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "claimed":
            return Color(hex: "#10B981")
        case "redeemed":
            return Color(hex: "#3B82F6")
        default:
            return Color.gray
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let displayFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df
        }()

        guard !dateString.isEmpty else {
            return "Unknown"
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }

        return dateString
    }
}

struct DetailStatusBadge: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color)
                .cornerRadius(10)
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(14)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .borderBottom(color: Color.gray.opacity(0.1))
    }
}

extension View {
    func borderBottom(color: Color) -> some View {
        VStack {
            self
            Divider()
                .background(color)
        }
    }
}
