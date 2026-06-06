/**
 `KeyboardLiveState`: per-keystroke output from the suggestion engine —
 predictions, the pending auto-correction, and emoji suggestions — flowing from
 the extension into the `SuggestionBar` and vice-versa. Also defines `ActionPanel`
 and `Autocorrection`.
 */
import SwiftUI

/// One of the optional "action panels" the keyboard can surface from the
/// top-left button — currently the clipboard history and the quick notepad.
/// Which ones are available is driven by `KeyboardSettings`; when more than one
/// is enabled the button offers a picker, otherwise it toggles the only one
/// directly. The active panel (if any) is held live in `KeyboardLiveState`.
public enum ActionPanel: String, Sendable, CaseIterable, Identifiable {
    case clipboard
    case notepad
    /// The emoji keyboard. Unlike the others it doesn't render inside
    /// `KeyboardCanvas` — selecting it flips the controller's `showEmoji` to swap
    /// in the separate `EmojiCanvas` — but it shares the same activation UI.
    case emoji
    case calculator

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .clipboard:   return "Clipboard"
        case .notepad:     return "Notepad"
        case .emoji:       return "Emoji"
        case .calculator:  return "Calculator"
        }
    }

    /// One-line description shown under the label in the `cards` picker.
    public var summary: String {
        switch self {
        case .clipboard:   return "Recent copied text"
        case .notepad:     return "Quick jotted notes"
        case .emoji:       return "Emoji keyboard"
        case .calculator:  return "Arithmetic calculator"
        }
    }

    /// SF Symbol for the button / picker row. `active` swaps to the filled
    /// variant when the panel is open (matching the old clipboard toggle).
    public func icon(active: Bool) -> String {
        switch self {
        case .clipboard:  return active ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        case .notepad:    return active ? "note.text.badge.plus" : "note.text"
        case .emoji:      return active ? "face.smiling.fill" : "face.smiling"
        case .calculator: return active ? "calculator.fill" : "calculator"
        }
    }
}

/// A pending auto-correction for the word currently being typed: replace `from`
/// (what the user typed) with `to` (the confident fix) when they hit space or
/// punctuation. Surfaced live as a highlighted preview chip, iOS-style.
public struct Autocorrection: Equatable, Sendable {
    public let from: String
    public let to: String
    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// Live, per-session state the keyboard extension feeds into `KeyboardCanvas`
/// while typing — the autocomplete suggestions and the pending auto-correction.
/// Separate from the persisted `KeyboardSettings` because it changes on every
/// keystroke and never needs saving. Observed by SwiftUI so the suggestion bar
/// updates without rebuilding the whole keyboard.
@MainActor
@Observable
public final class KeyboardLiveState {
    /// Up to three autocomplete candidates for the word being typed.
    public var suggestions: [String] = []

    /// The fix that "space completes" — shown as a highlighted preview chip.
    /// nil when the current word looks fine (or correction is off).
    public var autocorrection: Autocorrection?

    /// Emoji matching the word being typed (e.g. "dog" → 🐶), shown as plain
    /// non-primary chips in the suggestion bar. Never applied by space — only a
    /// deliberate tap inserts one, replacing the typed word.
    public var emojiSuggestions: [String] = []

    /// The return key's label, following the host field's `returnKeyType`
    /// (e.g. "Go", "Search", "Send", "Done"), or "return" by default.
    public var returnKeyTitle: String = "return"

    /// When non-nil, the return key renders this SF Symbol instead of its title
    /// — the system keyboard uses a ⏎ glyph for a plain return (and an arrow for
    /// "continue"), rather than the word.
    public var returnKeySymbol: String? = "return.left"

    /// Whether the return key should render prominent (accent-filled), as iOS
    /// does for action keys like Go / Search / Send / Done.
    public var returnKeyProminent: Bool = false

    /// The action panel currently open (clipboard / notepad), or nil while the
    /// user is just typing. Replaces the old `clipboardMode` flag now that more
    /// than one panel can live behind the top-left button.
    public var activePanel: ActionPanel? = nil

    public init(suggestions: [String] = [], autocorrection: Autocorrection? = nil) {
        self.suggestions = suggestions
        self.autocorrection = autocorrection
    }
}
