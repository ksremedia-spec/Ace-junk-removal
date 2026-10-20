import SwiftUI

/// The talk button (Kyle, Oct 20: "maybe a hold to talk"). Press and hold to
/// talk, let go to send, like a walkie-talkie. A quick tap instead keeps
/// listening hands-free until the next tap, for the truck.
struct HoldToTalkButton: View {
    var idleTitle = "Hold to talk"
    let isListening: Bool
    var onStart: () -> Void
    var onEnd: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var pressing = false
    @State private var pressedAt: Date?
    /// Listening after a quick tap; the next tap sends.
    @State private var handsFree = false

    /// Shorter than this is a tap, not a hold.
    private let tapLength: TimeInterval = 0.4

    var body: some View {
        Label(title, systemImage: isListening ? "waveform" : "mic.fill")
            .symbolEffect(.variableColor.iterative, isActive: isListening)
            .font(.callout.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(Capsule().fill(isListening ? Tint.overdue : Color.accentColor))
            .scaleEffect(pressing ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: pressing)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
            .gesture(press)
            .sensoryFeedback(.impact(weight: .light), trigger: isListening)
            .onChange(of: isListening) { _, listening in
                if !listening { handsFree = false }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isListening ? "Stop and send" : idleTitle)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isListening {
                    onEnd()
                } else {
                    handsFree = true
                    onStart()
                }
            }
    }

    private var title: String {
        guard isListening else { return idleTitle }
        return handsFree ? "Tap to send" : "Release to send"
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard isEnabled, !pressing else { return }
                pressing = true
                // Already listening (hands-free, or a hold that outlived the
                // microphone prompt): this press sends.
                if isListening {
                    handsFree = false
                    pressedAt = nil
                    onEnd()
                    return
                }
                pressedAt = Date()
                onStart()
            }
            .onEnded { _ in
                pressing = false
                guard let started = pressedAt else { return }
                pressedAt = nil
                if Date().timeIntervalSince(started) < tapLength {
                    handsFree = true
                } else {
                    onEnd()
                }
            }
    }
}

/// What WhisperKit has heard so far while listening: settled words in full
/// colour, words still being worked out in grey.
struct LiveWords: View {
    let engine: WhisperKitEngine
    var placeholder: String
    var minHeight: CGFloat = 24

    var body: some View {
        let confirmed = engine.liveConfirmed
        let tentative = engine.liveTentative
        let gap = confirmed.isEmpty || tentative.isEmpty ? "" : " "
        Text("\(confirmed)\(gap)\(Text(tentative).foregroundStyle(.secondary))")
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .animation(.default, value: confirmed)
            .overlay(alignment: .topLeading) {
                if confirmed.isEmpty && tentative.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                }
            }
    }
}
