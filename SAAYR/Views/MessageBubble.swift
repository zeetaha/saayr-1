//
//  MessageBubble.swift
//  SAAYR
//
//  Created by Awais Raza on 08/02/2026.
//

import SwiftUI
import Kingfisher

struct MessageBubble: View {
    let msg: MessageItem

    @State private var selectedImageURL: URL?
    @State private var showingFullImage = false

    var body: some View {
        VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
            HStack {
                if msg.isUser { Spacer() }

                VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 6) {

                    // Text message
                    if !msg.text.isEmpty {
                        Text(msg.text)
                            .foregroundColor(msg.isUser ? .black : .white)
                            .multilineTextAlignment(msg.isUser ? .trailing : .leading)
                    }

                    // Images
                    if !msg.images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(msg.images, id: \.self) { imgPath in
                                    if let url = fullImageUrl(from: imgPath) {
                                        KFImage(url)
                                            .placeholder {
                                                ProgressView()
                                                    .frame(width: 140, height: 140)
                                            }
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 140, height: 140)
                                            .clipped()
                                            .cornerRadius(8)
                                            .onTapGesture {
                                                selectedImageURL = url
                                                showingFullImage = true
                                            }
                                    }
                                }
                            }
                        }
                    }

                    // Time
                    Text(msg.time)
                        .font(.system(size: 12))
                        .foregroundColor(
                            msg.isUser ? .secondary : .white.opacity(0.7)
                        )
                }
                .padding(12)
                .background(bubbleBackground)
                .cornerRadius(16)

                if !msg.isUser { Spacer() }
            }
            .frame(maxWidth: .infinity, alignment: msg.isUser ? .trailing : .leading)
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingFullImage) {
            fullImageSheet
        }
    }

    // MARK: - Bubble Background
    @ViewBuilder
    private var bubbleBackground: some View {
        if msg.isUser {
            Color.white.opacity(0.9)
        } else {
            Color.blue.opacity(0.8)
        }
    }

    // MARK: - Full Image Sheet
    @ViewBuilder
    private var fullImageSheet: some View {
        if let url = selectedImageURL {
            FullScreenImageView(url: url)
        }
    }
}

// MARK: - Image URL Builder
func fullImageUrl(from path: String) -> URL? {
    if path.starts(with: "http") {
        return URL(string: path)
    }

    // WebService.baseUrl contains /api/v1/
    let host = WebService.baseUrl
        .replacingOccurrences(of: "/api/v1/", with: "")

    let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
    return URL(string: host + cleanPath)
}
