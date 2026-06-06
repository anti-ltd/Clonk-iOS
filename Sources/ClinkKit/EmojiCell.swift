import SwiftUI

// MARK: - Emoji cell

/// One tappable emoji. A `Button` (not a gesture) so it cooperates with the
/// enclosing `ScrollView` — drags scroll, taps insert. The press bloom comes from
/// the button style; the showcase simulator drives `simulatedPressed` to bloom a
/// cell with no finger on it.
struct EmojiCell: View {
    let glyph: String
    var simulatedPressed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 30))
                .frame(maxWidth: .infinity, minHeight: 40)
                .scaleEffect(simulatedPressed ? 1.3 : 1)
                .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.6), value: simulatedPressed)
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
    private struct Flash { var scale: CGFloat = 0.55; var opacity: Double = 0 }

    /// `keyframeAnimator` only fires when its trigger *changes while mounted*. This
    /// view is freshly mounted per flash (the overlay unmounts at rest), so the
    /// external `trigger` never changes within one lifetime — the morph would never
    /// play. Bumping a local tick on appear gives the animator the change it needs;
    /// also bumping on `trigger` re-morphs a repeat tap that lands before unmount.
    @State private var tick = 0

    var body: some View {
        let shape = Capsule(style: .continuous)
        ZStack {
            Color.clear.keyframeAnimator(initialValue: Flash(), trigger: tick) { _, f in
                Color.clear
                    .glassEffect(.regular.tint(tint), in: shape)
                    .scaleEffect(f.scale)
                    .opacity(f.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.55, duration: 0.001)
                    CubicKeyframe(1.08, duration: 0.15)   // morph out past full
                    CubicKeyframe(0.97, duration: 0.23)   // settle back in
                }
                KeyframeTrack(\.opacity) {
                    CubicKeyframe(0.0, duration: 0.001)
                    CubicKeyframe(0.85, duration: 0.06)   // bloom in
                    CubicKeyframe(0.0, duration: 0.32)    // ease away
                }
            }
            // The glyph, crisp on top of the glass droplet.
            Text(glyph).font(.system(size: 30))
        }
        .allowsHitTesting(false)
        .onAppear { tick &+= 1 }
        .onChange(of: trigger) { _, _ in tick &+= 1 }
    }
}

// MARK: - Bloom button style

/// Blooms an emoji while the finger is down, springs back on release.
struct EmojiBloomStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.3 : 1)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}
