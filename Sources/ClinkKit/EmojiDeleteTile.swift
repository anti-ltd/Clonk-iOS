/**
 Emoji keyboard delete tile with hold-to-repeat. `HoldRepeatSurface` /
 `HoldRepeatView` handle the UIKit touch loop that fires the delete callback at
 an accelerating rate while the user holds the key.
 

 Module: emoji · Target: ClinkKit
 Learn: docs/05-emoji.md
 */
import SwiftUI
import UIKit

// MARK: - Emoji backspace tile
//
// Built to feel exactly like the letter keyboard's delete key: tap to delete
// one, hold to auto-repeat with the same 450ms delay and accelerating cadence,
// the glyph bouncing on each repeat, a destructive-red press tint, the press
// bloom, and the additive tap pulse. A bare UIView reports touch-down / -up
// (SwiftUI button taps are dropped in the extension); the repeat is a
// cancellable Task, torn down on release.

/// Emoji-bar backspace: tap once, hold to auto-repeat with the same timing as
/// the letter keyboard's delete key.
struct DeleteTile: View {
    let theme: Theme
    let cornerRadius: CGFloat
    let onBackspace: () -> Void
    let onAnyTap: () -> Void

    /// iOS-style destructive red for the pressed backspace — matches the letter
    /// keyboard's delete key.
    private static let destructiveTint = Color(.sRGB, red: 0.91, green: 0.22, blue: 0.18)

    @State private var pressed = false
    @State private var tapTick = 0
    @State private var deleteTick = 0
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tint = pressed ? Self.destructiveTint : theme.specialKeyFill.color
        let label = Image(systemName: "delete.left")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(pressed ? Color.white : theme.specialKeyText.color)
            // Bounce on each held-delete repeat, just like the letter keyboard.
            .symbolEffect(.bounce, value: deleteTick)
            .frame(width: 76, height: 38)

        return Group {
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                label.glassEffect(.regular.tint(tint), in: shape)
            } else {
                label.background(tint, in: shape)
            }
        }
        .scaleEffect(pressed ? 1.12 : 1)
        .animation(Motion.emojiTabPress.animation, value: pressed)
        .modifier(EmojiTapPulse(trigger: tapTick, shape: shape, enabled: true))
        .overlay { HoldRepeatSurface(onDown: down, onUp: up) }
    }

    private func down() {
        onAnyTap()
        tapTick &+= 1
        pressed = true
        startRepeating()
    }

    private func up() {
        stopRepeating()
        pressed = false
    }

    /// Delete once now, wait out the hold delay, then auto-repeat with an
    /// accelerating cadence — the exact timing of `TouchEngine.startRepeating`.
    private func startRepeating() {
        stopRepeating()
        repeatTask = Task { @MainActor in
            onBackspace()                                  // first delete now
            try? await Task.sleep(for: .milliseconds(450)) // hold delay
            var interval = 110
            while !Task.isCancelled {
                onAnyTap()                                 // clink on each repeat
                onBackspace()
                deleteTick &+= 1                           // bounce the glyph
                interval = max(40, interval - 6)           // accelerate
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

// MARK: - Tap pulse (emoji variant)

/// An additive white flash played on each press — the emoji-bar twin of the
/// letter keyboard's `TapPulse`, generic over the tile shape.
struct EmojiTapPulse<S: Shape>: ViewModifier {
    let trigger: Int
    let shape: S
    let enabled: Bool

    /// Explicit-state flash with render-side animations — same pattern (and
    /// rationale) as the letter keyboard's `TapPulse`: keyframeAnimator cost a
    /// per-frame compositing pass, and phaseAnimator could park bright on a
    /// fast re-trigger. Every path here ends fading to 0.
    @State private var flash: CGFloat = 0
    @State private var fadeTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        // Same expensive-effects gate as `TapPulse`: the additive layer rests
        // under power/thermal pressure.
        if enabled, MotionProfile.shared.allowsExpensiveEffects {
            content.overlay {
                shape.fill(.white)
                    .opacity(flash)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .onChange(of: trigger) { _, _ in
                fadeTask?.cancel()
                withAnimation(Motion.tapFlashIn.animation) { flash = 0.34 }   // snap bright
                fadeTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.05))
                    guard !Task.isCancelled else { return }
                    withAnimation(Motion.tapFlashOut.animation) { flash = 0 } // ease back out
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Hold-repeat UIKit surface

/// A bare UIView reporting touch-down and touch-up (release or cancel) — drives
/// the backspace's press state and hold-to-repeat where SwiftUI button taps are
/// unreliable inside the keyboard extension.
struct HoldRepeatSurface: UIViewRepresentable {
    let onDown: () -> Void
    let onUp: () -> Void

    func makeUIView(context: Context) -> HoldRepeatView {
        let v = HoldRepeatView()
        v.onDown = onDown
        v.onUp = onUp
        return v
    }

    func updateUIView(_ uiView: HoldRepeatView, context: Context) {
        uiView.onDown = onDown
        uiView.onUp = onUp
    }
}

@MainActor
final class HoldRepeatView: UIView {
    var onDown: () -> Void = {}
    var onUp: () -> Void = {}

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { onDown() }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { onUp() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { onUp() }
}
