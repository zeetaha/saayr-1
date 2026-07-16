//
//  ClaimedRewardsView.swift
//  SAAYR
//
//  Created by Awais Raza on 05/07/2026.
//

import SwiftUI

struct ClaimedRewardsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var redemptions: [Redemption] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedRedemption: Redemption?
    
    private let pageSize = 20
    @State private var currentPage = 1
    
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
                    
                    Text("Claimed Rewards")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                    
                    Spacer()
                }
                .padding()
                .background(Color.white.opacity(0.95))
                .shadow(radius: 2)
                
                if isLoading && redemptions.isEmpty {
                    VStack {
                        ProgressView()
                            .tint(Color(hex: "#8B5CF6"))
                        Text("Loading rewards...")
                            .foregroundColor(.gray)
                            .padding(.top, 12)
                    }
                    .frame(maxHeight: .infinity)
                } else if redemptions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "gift.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        Text("No Claimed Rewards Yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.gray)
                        
                        Text("Rewards you claim will appear here")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(redemptions) { redemption in
                                ClaimedRewardCard(redemption: redemption) {
                                    selectedRedemption = redemption
                                }
                            }
                        }
                        .padding()
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
        .fullScreenCover(item: $selectedRedemption) { redemption in
            RewardDetailView(redemption: redemption)
        }
        .onAppear {
            fetchRedemptions()
        }
    }
    
    private func fetchRedemptions() {
        isLoading = true
        errorMessage = nil
        
        ServiceModel.shared.fetchMyRedemptions(page: currentPage, pageSize: pageSize) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let response):
                    redemptions = response.redemptions
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct ClaimedRewardCard: View {
    let redemption: Redemption
    let onTap: () -> Void
    
    var statusColor: Color {
        switch redemption.status ?? "".lowercased() {
        case "claimed":
            return Color(hex: "#10B981")
        case "redeemed":
            return Color(hex: "#3B82F6")
        default:
            return Color.gray
        }
    }
    
    var statusIcon: String {
        switch redemption.status ?? "".lowercased() {
        case "claimed":
            return "checkmark.circle.fill"
        case "redeemed":
            return "checkmark.circle.fill"
        default:
            return "circle"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Icon
                    if let urlString = redemption.imageUrl, let url = URL(string: urlString) {
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
                                        .font(.system(size: 24, weight: .semibold))
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
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .frame(width: 56, height: 56)
                        .cornerRadius(12)
                        .clipped()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color(hex: "#8B5CF6"), Color(hex: "#A855F7")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "gift.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 56, height: 56)
                        .cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(redemption.rewardTitle ?? "")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .lineLimit(2)
                        
                        Text(redemption.merchantName ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 8) {
                            Image(systemName: statusIcon)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                            
                            Text(redemption.status ?? "".uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor)
                        .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.6))
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Code:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                        
                        Text(redemption.redemptionCode ?? "")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text("Claimed:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                        
                        Text(formatDate(redemption.claimedAt ?? ""))
                            .font(.system(size: 12))
                            .foregroundColor(.black)
                        
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }
            .padding()
            .background(Color.white.opacity(0.9))
            .cornerRadius(14)
            .shadow(radius: 2)
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

#Preview {
    ClaimedRewardsView()
}
