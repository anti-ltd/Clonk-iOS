/**
 Glyph-layer preference key plumbing. Each key publishes its glyph info and
 bloom transform via `KeyGlyphKey`; the canvas collects them and draws a single
 unified glyph pass above all key backgrounds.
 

 Module: keyboard-core · Target: ClinkKit
 Learn: docs/02-keyboard-core.md
 */
import SwiftUI

// MARK: - Glyph layer plumbing
//
// Each key publishes its glyph + bounds + bloom transform; the canvas draws them
// all in one layer ABOVE the glass container, so the container's morph (which
// blends a bloomed key into its neighbours) never displaces the letter.

/// Published state for one key's glyph in the canvas overlay layer.
struct KeyGlyphInfo: Identifiable, Equatable {
    /// Stable row-col key ID (`"\(rowID)-\(index)"`).
    let id: String
    /// Key bounds in the glyph overlay's coordinate space.
    let anchor: Anchor<CGRect>
    /// When true, `glyph` is an SF Symbol name; otherwise literal text.
    let isSystem: Bool
    let glyph: String
    /// Foreground colour (white while pressed).
    let color: Color
    /// Press bloom scale from the key surface — applied to the overlay glyph.
    let scaleX: CGFloat
    let scaleY: CGFloat
    /// Space-bar lean offset — applied before the bloom spring on release.
    let offsetX: CGFloat
    /// Reserved; popups float above the key so the base glyph stays visible.
    let hidden: Bool
    /// Bumped on each auto-repeat delete to bounce the backspace glyph.
    let deleteTick: Int
    /// True while a backspace swipe-to-delete-word is engaged on this key — drives
    /// the emphasised "eating words" glyph animation. False for every other key.
    let deleteSwiping: Bool
    /// True for multi-character labels ("space", return title) — smaller font.
    let multiChar: Bool
    /// Override glyph point size (number row); nil = default sizing.
    var fontSize: CGFloat? = nil
    /// First long-press alternate for this key, shown as a small corner glyph when
    /// long-press hints are enabled. nil when the key has no alternates or hints are off.
    var hint: String? = nil
}

/// Preference key aggregating all visible key glyphs for a single canvas draw pass.
struct KeyGlyphKey: PreferenceKey {
    static let defaultValue: [KeyGlyphInfo] = []
    static func reduce(value: inout [KeyGlyphInfo], nextValue: () -> [KeyGlyphInfo]) {
        value.append(contentsOf: nextValue())
    }
}
