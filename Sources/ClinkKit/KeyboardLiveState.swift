import SwiftUI

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

    public init(suggestions: [String] = [], autocorrection: Autocorrection? = nil) {
        self.suggestions = suggestions
        self.autocorrection = autocorrection
    }
}
