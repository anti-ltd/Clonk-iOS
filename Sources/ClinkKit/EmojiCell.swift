/**
 `EmojiCell`: one tappable emoji in the grid. Handles the insert tap, the
 long-press for skin-tone picking, and the glass bloom flash on press.
 */
import SwiftUI

// MARK: - Emoji cell

/// One tappable emoji. A `Button` (not a gesture) so it cooperates with the
/// enclosing `ScrollView` — drags scroll, taps insert. The press bloom comes from
/// the button style; the showcase simulator drives `simulatedPressed` to bloom a
/// cell with no finger on it.
struct EmojiCell: View {
    let glyph: String
    var simulatedPressed: Bool = false
    /// Glyph point size — scaled by the grid to the cell it'll occupy, so more
    /// rows/columns shrink the emoji instead of overlapping them.
    var glyphSize: CGFloat = 30
    /// Pins the cell's main-axis extent to a computed square side. The cross axis
    /// fills its flexible grid track; only one of the two is set per scroll axis
    /// (`fixedWidth` while scrolling horizontally, `fixedHeight` while vertical).
    var fixedWidth: CGFloat? = nil
    var fixedHeight: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The cell rectangle: one axis pinned to the square side, the other
            // fills its flexible grid track. The glyph rides in an overlay at its
            // natural size (`fixedSize`) so it's CENTERED in the cell and never
            // clipped — a large emoji simply spills into the inter-cell gap rather
            // than being cut by the cell bounds.
            Color.clear
                .frame(width: fixedWidth, height: fixedHeight)
                .frame(maxWidth: fixedWidth == nil ? .infinity : nil,
                       maxHeight: fixedHeight == nil ? .infinity : nil)
                .overlay {
                    Text(glyph)
                        .font(.system(size: glyphSize))
                        .fixedSize()
                        .scaleEffect(simulatedPressed ? 1.3 : 1)
                        .animation(Motion.emojiCellPress.animation, value: simulatedPressed)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(EmojiBloomStyle())
        // Hold-to-pick is handled at the grid level by `EmojiHoldGesture`, which
        // suppresses this Button's tap once a hold is recognised — so a quick tap
        // inserts, a hold raises the swatch bar. The press flash is drawn once at
        // the grid level (see `flashOverlay`), never per-cell — a `glassEffect` on
        // every cell would be ruinously expensive in the extension.
    }
}

// MARK: - Glass press flash

/// The glass press indicator: a single tinted liquid-glass droplet that morphs in
/// over the just-tapped emoji and settles away, using the same `.glassEffect`
/// material as the keys so it reads as the surface itself deforming. The tapped
/// glyph is redrawn crisp on top so the glass sits *behind* it. Exactly one of
/// these is ever mounted, and only while a flash is in flight.
@available(iOS 26.0, *)
struct EmojiGlassFlashView: View {
    let glyph: String
    let tint: Color
    let trigger: Int

    /// Animated state: the droplet's scale (the morph) and its opacity (in/out).
    /// Driven by explicit writes with render-side animations — NOT a
    /// `keyframeAnimator`, whose content closure re-runs on the main thread
    /// every frame and was REBUILDING the `glassEffect` view per frame for the
    /// whole 0.38s flash (expensive on older GPUs), and NOT a `phaseAnimator`,
    /// which can park on a bright phase when re-triggered mid-cycle (the
    /// stuck-lit-key bug — see `TapPulse`). The glass view below is built once;
    /// only its scale/opacity animate, and every path ends faded out.
    @State private var scale: CGFloat = 0.55
    @State private var opacity: Double = 0
    @State private var playTask: Task<Void, Never>?

    var body: some View {
        let shape = Capsule(style: .continuous)
        ZStack {
            Color.clear
                .glassEffect(.regular.tint(tint), in: shape)
                .scaleEffect(scale)
                .opacity(opacity)
            // The glyph, crisp on top of the glass droplet.
            Text(glyph).font(.system(size: 30))
        }
        .allowsHitTesting(false)
        // This view is freshly mounted per flash (the overlay unmounts at
        // rest), so play on appear; a repeat tap that lands before unmount
        // changes `trigger` and re-plays from the rest pose.
        .onAppear { play() }
        .onChange(of: trigger) { _, _ in play() }
    }

    /// Replay the morph: snap back to the rest pose, then run the same curve
    /// the keyframes traced — scale 0.55 → 1.08 (0.15s) settling to 0.97
    /// (0.23s), opacity blooming to 0.85 (0.06s) then easing away (0.32s).
    private func play() {
        MotionDiagnostics.event("emoji.flash")
        playTask?.cancel()
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { scale = 0.55; opacity = 0 }
        // A fresh runloop turn (the sequence task), so the reset above is
        // committed and these animate from the rest pose instead of coalescing.
        playTask = runMotionSequence([
            MotionStep(animation: Motion.emojiFlashBloom.animation)  { opacity = 0.85 }, // bloom in
            MotionStep(animation: Motion.emojiFlashMorph.animation)  { scale = 1.08 },   // morph out past full
            MotionStep(delay: .seconds(0.06),
                       animation: Motion.emojiFlashFade.animation)   { opacity = 0 },    // ease away
            MotionStep(delay: .seconds(0.09),                                            // 0.15 from start
                       animation: Motion.emojiFlashSettle.animation) { scale = 0.97 },   // settle back in
        ])
    }
}

// MARK: - Bloom button style

/// Blooms an emoji while the finger is down, springs back on release.
struct EmojiBloomStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.3 : 1)
            .animation(Motion.emojiCellPress.animation,
                       value: configuration.isPressed)
    }
}
