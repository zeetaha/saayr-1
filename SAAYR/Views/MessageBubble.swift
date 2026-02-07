//
//  MessageBubble.swift
//  SAAYR
//
//  Created by Awais Raza on 08/02/2026.
//

import SwiftUI


struct MessageBubble: View {
    let msg: MessageItem

    var body: some View {
        VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
            HStack {
                if msg.isUser { Spacer() }

                VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 6) {
                    Text(msg.text)
                        .foregroundColor(msg.isUser ? .primary : .white)
                    
                    Text(msg.time)
                        .font(.system(size: 12))
                        .foregroundColor(msg.isUser ? .secondary : .white.opacity(0.7))
                }
                .padding()
                .background(background)
                .cornerRadius(16)

                if !msg.isUser { Spacer() }
            }
            .frame(maxWidth: .infinity, alignment: msg.isUser ? .trailing : .leading)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var background: some View {
        if msg.isUser {
            Color(UIColor.systemBackground)
        } else {
            LinearGradient(
                colors: [Color.purple.opacity(0.9), Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
