/**
 Skin-tone picker sheet: long-pressing a tone-capable emoji in the grid reveals
 a row of six tone variants. Defined here alongside the `EmojiHoldGesture`
 UIViewRepresentable that detects the long-press and `EmojiCellFramesKey` /
 `EmojiGridFrameKey` preference keys used to position the picker.
 */
import SwiftUI
import UIKit

// MARK: - Skin-tone picker

/// The skin-tone swatch bar raised while holding an emoji: that emoji in neutral
/// + the five Fitzpatrick tones, with the `highlighted` swatch lifted to show the
/// current selection. Purely presentational — `EmojiHoldGesture` drives the
/// selection and commit. Styled like the key popups (glass on glass themes).
struct SkinTonePicker: View {
    let base: String
    let highlighted: SkinTone
    let theme: Theme
    let cornerRadius: CGFloat

    static let swatch: CGFloat = 44
    static let hPadding: CGFloat = 8
    static let width: CGFloat = swatch * CGFloat(SkinTone.allCases.count) + hPadding * 2
    static let height: CGFloat = 56

    /// The bar's centre x (in `.global`), placed so the swatch at `anchorIndex`
    /// (the emoji's current tone) sits directly above the held cell, then clamped
    /// so the whole bar stays on-screen.
    static func center(cellMidX: CGFloat, anchorIndex: Int, in grid: CGRect) -> CGFloat {
        // Offset of the anchor swatch's centre from the bar's left edge.
        let anchorOffset = hPadding + swatch * (CGFloat(anchorIndex) + 0.5)
        let desired = cellMidX - anchorOffset + width / 2
        guard grid.width > width else { return grid.midX }
        return min(max(desired, grid.minX + width / 2 + 6), grid.maxX - width / 2 - 6)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let swatchShape = RoundedRectangle(cornerRadius: max(2, cornerRadius - 5), style: .continuous)
        let hlIndex = SkinTone.allCases.firstIndex(of: highlighted) ?? 0
        // Centre of the highlighted swatch, measured from the bar's left edge.
        let hlCenterX = Self.hPadding + Self.swatch * (CGFloat(hlIndex) + 0.5)
        let box = Self.swatch - 6

        // Swatches: a fixed-size row whose only variable is which one is picked.
        // Apple's emoji font renders the Fitzpatrick-modified glyphs with slightly
        // different metrics than the neutral base, so an unscaled row *looks* like a
        // jumble of sizes. To cut through that, the currently-picked swatch blows up
        // to one consistent large size — and stays there for the whole hold. It only
        // shrinks back when the finger lifts (the bar dismisses), never mid-slide, so
        // there's no flicker or shrink-as-you-go between tones.
        return HStack(spacing: 0) {
            ForEach(SkinTone.allCases) { tone in
                let isPicked = tone == highlighted
                Text(EmojiSkinTone.applied(tone, to: base))
                    .font(.system(size: 28))
                    .frame(width: Self.swatch, height: Self.swatch)
            }
        }
        .animation(Motion.skinTonePick.animation, value: highlighted)
        .padding(.horizontal, Self.hPadding)
        .frame(height: Self.height)
        // The selection highlight sits *behind* the swatches — positioned by exact
        // swatch maths so it's always perfectly centred and slides cleanly between
        // them (fully decoupled from the swatches, which never move) — so the chosen
        // emoji stays crisp and in front of the accent chip, not frosted under it.
        .background(alignment: .leading) {
            swatchShape
                .fill(theme.accent.color.opacity(0.3))
                .overlay(swatchShape.strokeBorder(theme.accent.color, lineWidth: 2.5))
                .frame(width: box, height: box)
                .offset(x: hlCenterX - box / 2)
                .animation(Motion.skinTonePick.animation, value: highlighted)
        }
        .background {
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(theme.keyFill.color), in: shape)
            } else {
                shape.fill(theme.keyFill.color)
            }
        }
        .overlay(shape.strokeBorder(theme.specialKeyText.color.opacity(0.12)))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }
}

// MARK: - Preference keys for the emoji grid

/// Publishes each visible emoji cell's on-screen (`.global`) frame, keyed by base
/// emoji, so the hold gesture can map a window-space touch back to an emoji and
/// the swatch bar can anchor above it.
struct EmojiCellFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Publishes the grid viewport's `.global` frame — used to clamp the swatch bar
/// on-screen and to map a finger position to a swatch.
struct EmojiGridFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Hold-to-pick gesture bridge
//
// The skin-tone interaction is "press an emoji, the swatch bar rises, slide to a
// tone, release to commit" — one continuous touch. A `UILongPressGestureRecognizer`
// is the exact primitive: it fires `.began` after a short still hold, streams
// `.changed` as the finger slides, and `.ended` on release. SwiftUI's own
// gestures are unreliable inside a keyboard extension (the same reason the letter
// keyboard and emoji tab bar route touches through bare UIViews), so we bridge to
// UIKit here.
//
// The recogniser is attached to the scroll view's container (an ancestor of the
// cell Buttons) so it sees every touch without blocking taps: a quick tap never
// reaches the hold threshold and flows to the Button, while `cancelsTouchesInView`
// cancels that Button once a hold is recognised — so committing a tone never also
// fires a plain insert. Touch points are read in window space to match SwiftUI's
// `.global` cell frames.

struct EmojiHoldGesture: UIViewRepresentable {
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    /// Seconds the emoji must be held before its skin-tone bar appears.
    var holdDelay: Double = 0.28

    func makeUIView(context: Context) -> HoldHostView {
        let v = HoldHostView()
        v.coordinator = context.coordinator
        v.holdDelay = holdDelay
        return v
    }

    func updateUIView(_ uiView: HoldHostView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        uiView.holdDelay = holdDelay
        // Live-update an already-attached recogniser so the setting takes effect
        // without re-creating the gesture.
        context.coordinator.recognizer?.minimumPressDuration = holdDelay
    }

    static func dismantleUIView(_ uiView: HoldHostView, coordinator: Coordinator) {
        if let lp = coordinator.recognizer { lp.view?.removeGestureRecognizer(lp) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// A zero-size, non-interactive handle that attaches the hold recogniser once
    /// it lands in a window — to the scroll container (an ancestor of the cell
    /// Buttons) so the gesture spans the grid without blocking taps or scrolling
    /// the rest of the app.
    @MainActor
    final class HoldHostView: UIView {
        weak var coordinator: Coordinator?
        /// Seconds before the hold recogniser fires (set from the live setting).
        var holdDelay: Double = 0.28

        init() {
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let coordinator, coordinator.recognizer == nil else { return }
            var scrollView: UIScrollView?
            var node: UIView? = self
            while let n = node {
                if let s = n as? UIScrollView { scrollView = s; break }
                node = n.superview
            }
            guard let host = scrollView?.superview ?? window else { return }
            let lp = UILongPressGestureRecognizer(target: coordinator,
                                                  action: #selector(Coordinator.handle(_:)))
            lp.minimumPressDuration = 0.28
            lp.cancelsTouchesInView = true
            lp.delegate = coordinator
            host.addGestureRecognizer(lp)
            coordinator.recognizer = lp
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var recognizer: UILongPressGestureRecognizer?
        var onBegan: (CGPoint) -> Void = { _ in }
        var onChanged: (CGPoint) -> Void = { _ in }
        var onEnded: (CGPoint) -> Void = { _ in }

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            // Report in the host (grid-container) local space. The SwiftUI side
            // adds the grid's `.global` origin to land in `.global` exactly —
            // independent of any window / safe-area offset.
            let p = g.location(in: g.view)
            switch g.state {
            case .began:                    onBegan(p)
            case .changed:                  onChanged(p)
            case .ended, .cancelled, .failed: onEnded(p)
            default:                        break
            }
        }

        // Coexist with the scroll view's pan: the hold only recognises after a
        // still ~0.28s, by which point a real scroll would already have moved and
        // failed it. Scrolling is frozen by the view once a pick is in progress.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
