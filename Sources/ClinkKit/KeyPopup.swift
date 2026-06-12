/**
 Key-press popup bubble. Uses a `PreferenceKey` (`KeyPopupKey`) to pass key
 bounds from deep inside the grid up to the canvas, which then renders
 `KeyPopup` / `BalloonPopup` floating above all other content.
 

 Module: keyboard-core · Target: ClinkKit
 Learn: docs/02-keyboard-core.md
 */
import SwiftUI

// MARK: - Key-popup plumbing
//
// The pressed-key bubble must float above the WHOLE keyboard — a per-key
// overlay escaping its bounds gets occluded by the keys in the row above. So
// each pressed character key publishes its glyph + bounds up via an anchor
// preference, and the canvas draws a single popup on top of everything.

/// Anchor + glyph for the pressed-key magnifier bubble.
struct KeyPopup {
    let glyph: String
    let anchor: Anchor<CGRect>
}

/// Preference key carrying the currently pressed key's popup anchor (at most one).
struct KeyPopupKey: PreferenceKey {
    static let defaultValue: KeyPopup? = nil
    static func reduce(value: inout KeyPopup?, nextValue: () -> KeyPopup?) {
        if let next = nextValue() { value = next }
    }
}

/// Publishes the held key's bounds while its accent bar is up, so the canvas can
/// anchor the `AccentPicker` above it. The bar's contents (options + highlight)
/// come from the `KeyTouchRouter`; only the anchor travels through preferences.
struct AccentPopupKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Popup chrome + shapes

/// Fills a popup's shape with the right material (Liquid Glass or an opaque
/// bubble) plus a drop shadow — shared by every popup style.
struct PopupChrome<S: Shape>: ViewModifier {
    let shape: S
    let theme: Theme
    let glass: Bool
    /// When set, the popup takes this tint instead of the resting key fill — used
    /// by the balloon so it matches the pressed key it rises out of, blending into
    /// one continuous shape rather than reading as a detached blob.
    var tint: Color? = nil
    /// Override the drop shadow (opacity, radius, y). The balloon dips into the
    /// key, so it wants a faint shadow — a strong one paints a dark line across
    /// the key where the two shapes overlap. Defaults to the floating tile's.
    var shadow: (opacity: Double, radius: CGFloat, y: CGFloat) = (0.3, 6, 2)

    @ViewBuilder func body(content: Content) -> some View {
        if glass, #available(iOS 26.0, *) {
            content
                .glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
                .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        } else {
            let resting: Color = theme.material == .liquidGlass
                ? (theme.isDark ? Color(.sRGB, white: 0.16) : Color(.sRGB, white: 0.98))
                : theme.keyFill.color
            content
                .background(tint ?? resting, in: shape)
                .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        }
    }
}

/// A key-popup outline drawn as ONE continuous shape spanning the whole pressed
/// key: a wide, flat-topped rounded-rectangle head (like the system keyboard's
/// magnifier) that eases down through a short concave neck to the key's width,
/// then runs straight to a rounded foot. Because the balloon *is* the key (it
/// covers it exactly, same width / corners / tint) there's no seam — the head
/// reads as the key broadening upward.
struct BalloonPopupShape: Shape {
    let keyWidth: CGFloat
    /// Height of the rounded-rectangle head, before the neck begins.
    let headHeight: CGFloat
    /// Y of the key's top edge within the frame; below it the sides run straight
    /// down to the foot, above it is the head + neck.
    let shoulderY: CGFloat
    /// Roundness of the head's top corners.
    let topCorner: CGFloat
    /// Roundness of the foot's corners — the key's own corner radius.
    let bottomCorner: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2
        let rt = min(topCorner, w / 2)
        let kHalf = min(keyWidth, w) / 2
        let leftK = cx - kHalf, rightK = cx + kHalf
        let br = min(bottomCorner, kHalf)
        let shoulder = min(max(shoulderY, rt + 8), h - br - 1)
        // Head's straight sides end a little above the shoulder, leaving a short
        // neck to ease in to the key width.
        let headB = min(headHeight, shoulder - 8)

        var p = Path()
        // Head — wide rounded-rectangle top.
        p.move(to: CGPoint(x: rt, y: 0))
        p.addLine(to: CGPoint(x: w - rt, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: rt), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: headB))
        // Short right neck — concave ease to the key's right edge (vertical
        // tangents at both ends so head and key sides flow in smoothly).
        p.addCurve(to: CGPoint(x: rightK, y: shoulder),
                   control1: CGPoint(x: w, y: shoulder),
                   control2: CGPoint(x: rightK, y: headB))
        // Straight down the key's right side to the foot.
        p.addLine(to: CGPoint(x: rightK, y: h - br))
        p.addQuadCurve(to: CGPoint(x: rightK - br, y: h), control: CGPoint(x: rightK, y: h))
        p.addLine(to: CGPoint(x: leftK + br, y: h))
        p.addQuadCurve(to: CGPoint(x: leftK, y: h - br), control: CGPoint(x: leftK, y: h))
        // Up the key's left side, then the mirrored neck back to the head.
        p.addLine(to: CGPoint(x: leftK, y: shoulder))
        p.addCurve(to: CGPoint(x: 0, y: headB),
                   control1: CGPoint(x: leftK, y: headB),
                   control2: CGPoint(x: 0, y: shoulder))
        p.addLine(to: CGPoint(x: 0, y: rt))
        p.addQuadCurve(to: CGPoint(x: rt, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}

/// The balloon popup, with its "droplet" emerge: on press it springs up out of
/// the key — anchored at the foot, it stretches from a low squash to full height
/// and settles with a soft wobble, like a droplet drawn upward. A faint shadow
/// keeps the foot from painting a line across the key it overlaps.
struct BalloonPopup: View {
    let glyph: String
    let bulbWidth: CGFloat
    let totalHeight: CGFloat
    /// Signed offset of the glyph from the frame centre, up into the bulb.
    let glyphOffset: CGFloat
    let shape: BalloonPopupShape
    /// Pressed-key tint — the balloon covers the key footprint, so it reads as one shape.
    let tint: Color
    let theme: Theme
    let glass: Bool
    /// User-tuned emerge spring (resolved through `MotionProfile` on appear).
    var springResponse: Double = 0.32
    var springDamping: Double  = 0.62

    @State private var emerged = false

    var body: some View {
        Text(glyph)
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(.white)
            .offset(y: glyphOffset)                   // lift glyph into the bulb
            .frame(width: bulbWidth, height: totalHeight)
            .modifier(PopupChrome(shape: shape, theme: theme, glass: glass,
                                  tint: tint, shadow: (0.22, 5, 1.5)))
            // Droplet emerge: scale up from the foot (the key), so the bulb is
            // drawn upward out of the key rather than fading in over it.
            .scaleEffect(x: emerged ? 1 : 0.9, y: emerged ? 1 : 0.5, anchor: .bottom)
            .opacity(emerged ? 1 : 0.5)
            .onAppear {
                // User-tuned popup spring, resolved through the motion profile.
                withAnimation(MotionToken(curve: .spring(response: springResponse, damping: springDamping),
                                          role: .essential).animation) { emerged = true }
            }
    }
}
