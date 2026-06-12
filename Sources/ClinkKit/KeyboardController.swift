/**
 `KeyboardController`: observable transient state for one keyboard session.
 Tracks which symbol plane and shift state are shown, the currently pressed key
 ID, and the emoji mode toggle. Also provides key-ID resolution helpers.
 

 Module: keyboard-core · Target: ClinkKit
 Learn: docs/02-keyboard-core.md
 */
import SwiftUI

/// The keyboard's transient UI state — which symbol plane is showing, the shift
/// state, and (for the showcase) which key is being "pressed" by a simulator.
///
/// `KeyboardCanvas` reads its plane/shift from here and renders the matching
/// key as pressed when `pressedKeyID` names it. Normally the canvas creates its
/// own private controller and drives it from finger gestures, so behaviour is
/// unchanged. The device-showcase typing simulator injects a *shared* controller
/// instead, so it can switch planes, toggle shift, and flash keys in lockstep
/// with the text appearing in the bubble — the keyboard looks like it's being
/// typed on by a real hand.
@MainActor
@Observable
public final class KeyboardController {
    public enum Plane: Equatable, Sendable { case letters, numbers, symbols }
    public enum Shift: Equatable, Sendable { case off, on, locked }

    public var plane: Plane = .letters
    public var shift: Shift = .on   // iOS starts a sentence capitalized

    /// The key the simulator is currently pressing (canvas keyID, e.g. "r1-3").
    /// nil when nothing is being driven externally — finger taps use the key's
    /// own local press state, not this.
    public var pressedKeyID: String?

    // MARK: - Emoji keyboard (showcase)

    /// When true, the showcase swaps the letter keyboard for the emoji keyboard
    /// — exactly like tapping the 🙂 key. Driven by the typing simulator when an
    /// emoji is next in the script.
    public var showEmoji = false
    /// The selected emoji category tab.
    public var emojiCategory = 0
    /// The emoji the simulator is currently pressing (so the cell blooms).
    public var pressedEmoji: String?

    public init() {}

    /// The category index that contains a given emoji, or nil if it isn't in the
    /// curated set (the simulator then just inserts it without switching keyboards).
    public func emojiCategoryIndex(for ch: Character) -> Int? {
        let s = String(ch)
        return EmojiData.categories.firstIndex { $0.emoji.contains(s) }
    }

    // MARK: - Character → key resolution
    //
    // Mirrors exactly how `KeyboardCanvas` assigns keyIDs ("\(rowID)-\(index)"),
    // so the simulator can name the precise key that produces a given character.

    /// Where a character lives on the keyboard: the plane it's on, whether shift
    /// must be engaged (uppercase letters), and the keyID to flash.
    public struct KeyHit: Sendable {
        public let plane: Plane
        public let needsShift: Bool
        public let id: String
    }

    /// Resolve a character to the key that types it, or nil if it isn't on any
    /// plane (e.g. an emoji — the simulator inserts those without a keypress).
    public func locate(_ ch: Character, settings: KeyboardSettings) -> KeyHit? {
        let rows = settings.layout.rows

        if ch.isLetter {
            let lower = ch.lowercased()
            for (r, row) in rows.enumerated() {
                if let c = row.firstIndex(of: lower) {
                    let isLast = r == rows.count - 1
                    let idx = isLast ? c + 1 : c   // shift occupies index 0 of the last row
                    return KeyHit(plane: .letters, needsShift: ch.isUppercase, id: "r\(r)-\(idx)")
                }
            }
        }

        let s = String(ch)

        // Digits are reachable on the letter plane when the number row is shown.
        if settings.showNumberRow, let c = KeyboardLayout.numberRows[0].firstIndex(of: s) {
            return KeyHit(plane: .letters, needsShift: false, id: "num-\(c)")
        }

        if let hit = search(KeyboardLayout.numberRows, plane: .numbers, char: s) { return hit }
        if let hit = search(KeyboardLayout.symbolRows, plane: .symbols, char: s) { return hit }
        return nil
    }

    private func search(_ source: [[String]], plane: Plane, char: String) -> KeyHit? {
        for (r, row) in source.enumerated() {
            if let c = row.firstIndex(of: char) {
                let isLast = r == source.count - 1
                let idx = isLast ? c + 1 : c   // plane-switch key occupies index 0 of the last row
                return KeyHit(plane: plane, needsShift: false, id: "r\(r)-\(idx)")
            }
        }
        return nil
    }

    // MARK: - Special-key IDs (no globe — the showcase keyboard hides it)

    public var spaceID: String { "bottom-1" }
    public var returnID: String { "bottom-2" }
    /// The 123 / ABC key that toggles between letters and the number plane.
    public var planeToggleID: String { "bottom-0" }
    /// The #+= / 123 key on the symbol planes (last row, leading slot).
    public var symbolPageToggleID: String { "r\(KeyboardLayout.numberRows.count - 1)-0" }

    public func shiftID(settings: KeyboardSettings) -> String {
        "r\(settings.layout.rows.count - 1)-0"
    }

    public func backspaceID(settings: KeyboardSettings) -> String {
        switch plane {
        case .letters:
            let rows = settings.layout.rows
            return "r\(rows.count - 1)-\(1 + rows[rows.count - 1].count)"
        case .numbers:
            let rows = KeyboardLayout.numberRows
            return "r\(rows.count - 1)-\(1 + rows[rows.count - 1].count)"
        case .symbols:
            let rows = KeyboardLayout.symbolRows
            return "r\(rows.count - 1)-\(1 + rows[rows.count - 1].count)"
        }
    }
}
