//
//  TopToast.swift
//  SAAYR
//
//  A message that drops in from the top and leaves on its own. For outcomes
//  worth reading but not worth interrupting for — a server saying "joining
//  opens in 2m 17s", or a reward landing — where an alert is too heavy and an
//  inline label is too easy to miss, because it sits far from the button that
//  was just tapped.
//
//  It also outlives the screen that triggered it: attach it to the host and a
//  full-screen cover can report its result on the way out.
//

import SwiftUI

/// What a toast is saying. Equatable so `onChange` can drive the timer, which
/// means it can't hold anything richer than the text itself.
struct ToastContent: Equatable {

    enum Kind: Equatable {
        case success
        case error

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error:   return "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return BossStyle.gold
            case .error:   return BossStyle.live
            }
        }
    }

    let message: String
    let kind: Kind

    static func success(_ message: String) -> ToastContent {
        ToastContent(message: message, kind: .success)
    }

    static func error(_ message: String) -> ToastContent {
        ToastContent(message: message, kind: .error)
    }
}

struct TopToast: View {

    let content: ToastContent
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: content.kind.icon)
                .font(.system(size: 13))

            Text(content.message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .foregroundColor(content.kind.tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(BossStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(content.kind.tint.opacity(0.45), lineWidth: 1)
        )
        // It floats over content rather than sitting in the layout, so it
        // needs a shadow to read as being above it.
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.message)
    }
}

extension View {

    /// Shows `toast` until it's tapped or the timeout passes.
    ///
    /// Setting the binding to a non-nil value shows it; the modifier clears
    /// the binding itself when it goes away, so the caller only has to assign.
    /// Re-assigning while one is visible restarts the timer with the new text.
    func topToast(_ toast: Binding<ToastContent?>, duration: TimeInterval = 4) -> some View {
        modifier(TopToastModifier(toast: toast, duration: duration))
    }
}

private struct TopToastModifier: ViewModifier {

    @Binding var toast: ToastContent?
    let duration: TimeInterval

    /// Identifies the current toast so a stale timer can't dismiss a newer
    /// one that replaced it.
    @State private var generation = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    TopToast(content: toast, onDismiss: dismiss)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: toast)
            .onChange(of: toast) { new in
                guard new != nil else { return }
                generation += 1
                let shown = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    guard generation == shown else { return }
                    dismiss()
                }
            }
    }

    private func dismiss() {
        toast = nil
    }
}
