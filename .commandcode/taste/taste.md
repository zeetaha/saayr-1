# Taste (Continuously Learned by [CommandCode][cmd])

[cmd]: https://commandcode.ai/

# swiftui
- Buttons that trigger validation should only be disabled for `isLoading`/`isSubmitting` — never disable for empty-field or count checks, so the tap action fires and can show inline validation errors. Confidence: 0.85
- Use `.sheet(item:)` with an `Identifiable` wrapper struct (not `.sheet(isPresented:)` with `if let`) to avoid blank screens from SwiftUI rendering before state propagates. Confidence: 0.75
- Use a single `alert(item:)` with an `Identifiable` enum rather than multiple `.alert` modifiers — SwiftUI ignores all but the last `.alert`. Confidence: 0.80

