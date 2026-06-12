/**
 `AccentPicker`: the accent-variant bar raised while holding a letter key — the
 base glyph plus its diacritic variants, with the `selected` swatch highlighted.
 Purely presentational; `KeyTouchRouter` drives the long-press, slide-to-select,
 and release-to-commit (the same interaction model as the emoji skin-tone
 picker), and the canvas positions this bar above the held key. Styled like the
 key popups (glass on glass themes, solid otherwise).
 

 Module: touch · Target: ClinkKit
 Learn: docs/03-touch-and-input.md
 */
import SwiftUI

struct AccentPicker: View {
    let options: [String]
    let selected: Int
    let theme: Theme
    let cornerRadius: CGFloat

    // MARK: - Layout constants

    static let swatch: CGFloat = 42
    static let hPadding: CGFloat = 8
    static let height: CGFloat = 54

    static let edgeInset: CGFloat = 6

    /// Total bar width for `count` options.
    static func width(count: Int) -> CGFloat {
        swatch * CGFloat(max(count, 1)) + hPadding * 2
    }

    /// The bar's left edge, anchored so the BASE swatch (index 0) sits centred
    /// over the held key — like the system keyboard, where the first option lines
    /// up under your finger and the variants fan out to the right — then clamped
    /// so the whole bar stays on screen. Shared verbatim by the renderer and the
    /// router's finger→swatch hit-test, so the highlighted swatch is always the
    /// one under the finger (no offset).
    static func barLeft(keyMidX: CGFloat, count: Int, containerWidth: CGFloat) -> CGFloat {
        let w = width(count: count)
        let desired = keyMidX - hPadding - swatch / 2
        let maxLeft = max(edgeInset, containerWidth - w - edgeInset)
        return min(max(desired, edgeInset), maxLeft)
    }

    // MARK: - View

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let swatchShape = RoundedRectangle(cornerRadius: max(2, cornerRadius - 5), style: .continuous)
        let idx = max(0, min(selected, options.count - 1))
        // Centre of the highlighted swatch, measured from the bar's left edge.
        let hlCenterX = Self.hPadding + Self.swatch * (CGFloat(idx) + 0.5)
        let box = Self.swatch - 6

        return HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, glyph in
                Text(glyph)
                    .font(.system(size: 24,
                                  weight: theme.keyFontWeight.fontWeight,
                                  design: theme.keyFontDesign.fontDesign))
                    .foregroundStyle(i == idx ? Color.white : theme.keyText.color)
                    .frame(width: Self.swatch, height: Self.swatch)
            }
        }
        .padding(.horizontal, Self.hPadding)
        .frame(height: Self.height)
        // Selection highlight sits behind the glyphs, slid by exact swatch maths
        // so it tracks the chosen index cleanly (decoupled from the glyphs, which
        // never move).
        .background(alignment: .leading) {
            swatchShape
                .fill(theme.accent.color)
                .frame(width: box, height: box)
                .offset(x: hlCenterX - box / 2)
                .animation(Motion.accentHighlight.animation, value: selected)
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
