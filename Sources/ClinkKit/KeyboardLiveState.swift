/**
 `KeyboardLiveState`: per-keystroke output from the suggestion engine —
 predictions, the pending auto-correction, and emoji suggestions — flowing from
 the extension into the `SuggestionBar` and vice-versa. Also defines `ActionPanel`
 and `Autocorrection`.
 

 Module: keyboard-core · Target: ClinkKit
 Learn: docs/02-keyboard-core.md
 */
import SwiftUI

/// One of the optional "action panels" the keyboard can surface from the
/// top-left button — currently the clipboard history and the quick notepad.
/// Which ones are available is driven by `KeyboardSettings`; when more than one
/// is enabled the button offers a picker, otherwise it toggles the only one
/// directly. The active panel (if any) is held live in `KeyboardLiveState`.
public struct ActionPanel: Hashable, Identifiable, Sendable {
    /// The fixed built-in panels, plus the two custom-SDK panel kinds. A
    /// `.customPanel` carries the backing `ClinkPanel` id so individual custom
    /// panels can appear as their own top-level picker entries; `.customPanels`
    /// is the single grouped "Panels" entry.
    public enum Kind: String, Sendable, Hashable {
        case clipboard, notepad, emoji, calculator, extensions, customPanels, customPanel
    }

    public let kind: Kind
    /// For `.customPanel`, the backing `ClinkPanel` id; nil otherwise.
    public let panelID: String?
    private let customLabel: String?
    private let customIcon: String?

    init(kind: Kind, panelID: String? = nil, customLabel: String? = nil, customIcon: String? = nil) {
        self.kind = kind
        self.panelID = panelID
        self.customLabel = customLabel
        self.customIcon = customIcon
    }

    public static let clipboard = ActionPanel(kind: .clipboard)
    public static let notepad = ActionPanel(kind: .notepad)
    /// The emoji keyboard. Unlike the others it doesn't render inside
    /// `KeyboardCanvas` — selecting it flips the controller's `showEmoji` to swap
    /// in the separate `EmojiCanvas` — but it shares the same activation UI.
    public static let emoji = ActionPanel(kind: .emoji)
    public static let calculator = ActionPanel(kind: .calculator)
    /// User-authored custom actions (the Python extension SDK).
    public static let extensions = ActionPanel(kind: .extensions)
    /// The single grouped entry listing all "grouped" custom panels.
    public static let customPanels = ActionPanel(kind: .customPanels)
    /// A standalone custom panel that gets its own top-level picker entry.
    public static func customPanel(id: String, name: String, icon: String) -> ActionPanel {
        ActionPanel(kind: .customPanel, panelID: id, customLabel: name, customIcon: icon)
    }

    /// Resolve a built-in panel from its stored id (used by `extensionOrder`).
    /// Returns nil for the custom kinds, which never live in `extensionOrder`.
    public init?(rawValue: String) {
        switch rawValue {
        case "clipboard":  self = .clipboard
        case "notepad":    self = .notepad
        case "emoji":      self = .emoji
        case "calculator": self = .calculator
        case "extensions": self = .extensions
        case "customPanels": self = .customPanels
        default: return nil
        }
    }

    public var id: String { panelID.map { "\(kind.rawValue):\($0)" } ?? kind.rawValue }

    // Identity is the `id` only — a custom panel's label/icon can change without
    // changing which panel it is.
    public static func == (lhs: ActionPanel, rhs: ActionPanel) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var label: String {
        switch kind {
        case .clipboard:    return "Clipboard"
        case .notepad:      return "Notepad"
        case .emoji:        return "Emoji"
        case .calculator:   return "Calculator"
        case .extensions:   return "Actions"
        case .customPanels: return "Panels"
        case .customPanel:  return customLabel ?? "Panel"
        }
    }

    /// One-line description shown under the label in the `cards` picker.
    public var summary: String {
        switch kind {
        case .clipboard:    return "Recent copied text"
        case .notepad:      return "Quick jotted notes"
        case .emoji:        return "Emoji keyboard"
        case .calculator:   return "Arithmetic calculator"
        case .extensions:   return "Your custom actions"
        case .customPanels: return "Your custom panels"
        case .customPanel:  return "Custom panel"
        }
    }

    /// SF Symbol for the button / picker row. `active` swaps to the filled
    /// variant when the panel is open (matching the old clipboard toggle).
    public func icon(active: Bool) -> String {
        switch kind {
        case .clipboard:    return active ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        case .notepad:      return active ? "note.text.badge.plus" : "note.text"
        case .emoji:        return active ? "face.smiling.fill" : "face.smiling"
        case .calculator:   return active ? "numbers.rectangle.fill" : "numbers.rectangle"
        case .extensions:   return active ? "puzzlepiece.extension.fill" : "puzzlepiece.extension"
        case .customPanels: return active ? "square.grid.2x2.fill" : "square.grid.2x2"
        case .customPanel:
            if let customIcon, !customIcon.isEmpty { return customIcon }
            return "square.grid.2x2"
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

    /// Incremented each time the keyboard finishes settling into view. Observed
    /// by the canvas to trigger auto-expand behaviours on each appearance.
    public var appearanceCount: Int = 0

    /// Extra height the canvas needs beyond `preferredHeight` — set when an
    /// inline picker opens and no bar was pre-allocated in the static height.
    public var extraBarHeight: CGFloat = 0

    /// Next-letter probability distribution for the word being typed, pushed by
    /// the host after each edit (derived from the lexicon's completion set).
    /// `KeyTouchRouter` prefers this over its built-in English letter tables
    /// when sizing adaptive hitboxes; nil falls back to those tables. Only the
    /// (debug) hitbox overlay observes it — the router reads it via a closure
    /// at touch time, so per-keystroke updates don't re-render the keyboard.
    public var predictedDistribution: [Character: Double]?

    public init(suggestions: [String] = [], autocorrection: Autocorrection? = nil) {
        self.suggestions = suggestions
        self.autocorrection = autocorrection
    }
}
