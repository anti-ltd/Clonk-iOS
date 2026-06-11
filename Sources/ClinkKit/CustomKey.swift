/**
 `CustomKey` / `CustomRow`: user-defined keys placed on the letters plane — the
 data behind the Layout → Custom tab. Users build keys that insert text (with
 optional Gboard-style long-press alternates) or act as function keys, and drop
 them either beside the space bar or in whole custom rows above/below the letters.

 Codable + shared between the container app (writes) and the keyboard extension
 (reads) via the App Group, exactly like `KeyboardSettings`.
 */
import Foundation

/// What a custom key does when tapped.
///
/// `insert` types a string; the rest mirror behaviours the canvas already has
/// wired (cursor nudge, plane switch, emoji panel, backspace). Long-press
/// alternates are only meaningful on a single-character `insert` key — see
/// `KeyboardCanvas.customKeySpec` for why.
public enum CustomKeyAction: Codable, Equatable, Sendable, Hashable {
    case insert(String)
    case cursorLeft
    case cursorRight
    case tab
    case numbersPlane
    case emoji
    case backspace
}

/// A single user-defined key.
public struct CustomKey: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// What's drawn on the cap: a literal string, or an SF Symbol name when
    /// `isSymbol` is true.
    public var glyph: String
    /// Render `glyph` as an SF Symbol rather than literal text.
    public var isSymbol: Bool
    public var action: CustomKeyAction
    /// Long-press insert options (display == inserted text). Only honoured for a
    /// single-character `insert` action; the editor enforces this.
    public var alternates: [String]
    /// Key weight in the proportional row layout (a standard letter is 1.0).
    public var width: Double

    public init(id: UUID = UUID(), glyph: String, isSymbol: Bool = false,
                action: CustomKeyAction, alternates: [String] = [], width: Double = 1.0) {
        self.id = id; self.glyph = glyph; self.isSymbol = isSymbol
        self.action = action; self.alternates = alternates; self.width = width
    }

    /// True when this key's `alternates` are eligible for the long-press bar:
    /// an `insert` action whose payload is exactly one character.
    public var supportsAlternates: Bool {
        if case let .insert(s) = action { return s.count == 1 }
        return false
    }
}

/// Where a custom row sits relative to the three letter rows.
public enum CustomRowPosition: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Above the top letter row (and below the number row, if shown).
    case aboveLetters
    /// Below the bottom letter row, above the space/function row.
    case belowLetters

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .aboveLetters: return "Above letters"
        case .belowLetters: return "Below letters"
        }
    }
}

/// A whole row of custom keys placed on the letters plane.
public struct CustomRow: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var keys: [CustomKey]
    public var position: CustomRowPosition

    public init(id: UUID = UUID(), keys: [CustomKey] = [], position: CustomRowPosition = .belowLetters) {
        self.id = id; self.keys = keys; self.position = position
    }
}
