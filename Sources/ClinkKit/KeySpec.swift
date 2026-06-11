/**
 `KeySpec`: a single key's identity, label, and action — the value type rebuilt
 cheaply on every shift/plane change.
 */
import SwiftUI

/// A single key's appearance + behaviour. Value type so rows can be rebuilt
/// cheaply on every shift/plane change.
struct KeySpec: Identifiable {
    enum Kind { case character, function }
    enum Label { case text(String); case system(String) }

    let id = UUID()
    let kind: Kind
    let label: Label
    let weight: Double
    let highlighted: Bool
    /// Pressed state glows red instead of accent (the backspace key).
    let isDestructive: Bool
    /// The space bar — taps insert a space, press-and-drag moves the cursor.
    let isSpace: Bool
    /// Repeats `action` while held (the backspace key).
    let isRepeatable: Bool
    /// Fired when this key is pressed and dragged upward past a threshold (the
    /// 123→emoji gesture). When it fires, the key's normal tap `action` is
    /// suppressed for that touch. nil for keys with no drag-up behaviour.
    let onDragUp: (() -> Void)?
    /// After `onDragUp` has fired, each subsequent move reports the finger's
    /// window-coordinate position — used to drag onto a panel-picker row.
    let onDragUpMove: ((CGPoint) -> Void)?
    /// Fired on release after a drag-up, with the finger's window position, so the
    /// canvas can select the row under it (or dismiss).
    let onDragUpEnd: ((CGPoint) -> Void)?
    /// The shift key — it has its own glass + symbol animation, so it opts out
    /// of the generic press-warp bloom (which would double up and look janky).
    let isShift: Bool
    /// The globe / next-keyboard key — kept tappable in combined cursor mode so
    /// the user can always switch away (every other key is rebound to the pad).
    let isNextKeyboard: Bool
    /// Called with a signed character delta while dragging the space bar.
    let onCursorMove: ((Int) -> Void)?
    /// Override glyph point size (the number row uses this); nil = default sizing.
    let fontSize: CGFloat?
    /// Long-press accent options for this key: the base glyph first, then its
    /// diacritic variants (e.g. "e" → ["e","è","é",…]). Empty for keys with no
    /// accents — the router then shows no accent popup on hold.
    let accents: [String]
    /// Commit a chosen accent variant: the base was already inserted on
    /// touch-down, so this replaces it (backspace + insert) when the picked glyph
    /// differs from the base. nil for keys with no accents.
    let onAccentCommit: ((String) -> Void)?
    /// Fired when this key is pressed and dragged horizontally (the backspace
    /// swipe-to-delete-word gesture): once per word as the finger glides left.
    /// When it engages, the key's auto-repeat is stopped. nil disables the gesture.
    let onDeleteWord: (() -> Void)?
    let action: () -> Void

    init(kind: Kind, label: Label, weight: Double, highlighted: Bool = false,
         isDestructive: Bool = false, isSpace: Bool = false, isRepeatable: Bool = false,
         isShift: Bool = false, isNextKeyboard: Bool = false,
         onCursorMove: ((Int) -> Void)? = nil,
         onDragUp: (() -> Void)? = nil,
         onDragUpMove: ((CGPoint) -> Void)? = nil,
         onDragUpEnd: ((CGPoint) -> Void)? = nil,
         fontSize: CGFloat? = nil,
         accents: [String] = [],
         onAccentCommit: ((String) -> Void)? = nil,
         onDeleteWord: (() -> Void)? = nil,
         action: @escaping () -> Void) {
        self.kind = kind; self.label = label; self.weight = weight
        self.highlighted = highlighted; self.isDestructive = isDestructive
        self.isSpace = isSpace; self.isRepeatable = isRepeatable; self.isShift = isShift
        self.isNextKeyboard = isNextKeyboard
        self.onCursorMove = onCursorMove; self.onDragUp = onDragUp
        self.onDragUpMove = onDragUpMove; self.onDragUpEnd = onDragUpEnd
        self.fontSize = fontSize
        self.accents = accents; self.onAccentCommit = onAccentCommit
        self.onDeleteWord = onDeleteWord
        self.action = action
    }
}
