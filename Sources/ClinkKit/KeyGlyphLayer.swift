/**
 Glyph-layer preference key plumbing. Each key publishes its glyph info and
 bloom transform via `KeyGlyphKey`; the canvas collects them and draws a single
 unified glyph pass above all key backgrounds.
 */
import SwiftUI

// MARK: - Glyph layer plumbing
//
// Each key publishes its glyph + bounds + bloom transform; the canvas draws them
// all in one layer ABOVE the glass container, so the container's morph (which
// blends a bloomed key into its neighbours) never displaces the letter.

struct KeyGlyphInfo: Identifiable, Equatable {
    let id: String
    let anchor: Anchor<CGRect>
    let isSystem: Bool
    let glyph: String
    let color: Color
    let scaleX: CGFloat
    let scaleY: CGFloat
    let offsetX: CGFloat
    let hidden: Bool
    let deleteTick: Int
    /// True while a backspace swipe-to-delete-word is engaged on this key — drives
    /// the emphasised "eating words" glyph animation. False for every other key.
    let deleteSwiping: Bool
    let multiChar: Bool
    /// Override glyph point size (number row); nil = default sizing.
    var fontSize: CGFloat? = nil
    /// First long-press alternate for this key, shown as a small corner glyph when
    /// long-press hints are enabled. nil when the key has no alternates or hints are off.
    var hint: String? = nil
}

struct KeyGlyphKey: PreferenceKey {
    static let defaultValue: [KeyGlyphInfo] = []
    static func reduce(value: inout [KeyGlyphInfo], nextValue: () -> [KeyGlyphInfo]) {
        value.append(contentsOf: nextValue())
    }
}
