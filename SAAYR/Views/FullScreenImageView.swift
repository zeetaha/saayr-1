//
//  FullScreenImageView.swift
//  SAAYR
//
//  Created by Copilot on 10/02/2026.
//

import SwiftUI
import Kingfisher

struct FullScreenImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            KFImage.url(url)
                .placeholder {
                    ProgressView()
                }
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    // double tap to reset/zoom
                    withAnimation { if scale > 1 { scale = 1; lastScale = 1 } else { scale = 2; lastScale = 2 } }
                }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }
}

#if DEBUG
struct FullScreenImageView_Previews: PreviewProvider {
    static var previews: some View {
        FullScreenImageView(url: URL(string: "https://via.placeholder.com/600")!)
    }
}
#endif
