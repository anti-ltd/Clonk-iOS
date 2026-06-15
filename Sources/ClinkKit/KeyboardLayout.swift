/**
 `KeyboardLayout`: the letter-plane key arrangement for one locale. Ships with
 four built-in presets (QWERTY, AZERTY, QWERTZ, Dvorak) plus the shared
 number-row and symbol-row definitions used by every layout.
 

 Module: keyboard-core · Target: ClinkKit
 Learn: docs/02-keyboard-core.md
 */
import Foundation

/// A keyboard's letter-plane arrangement. Clink lays out the number/symbol
/// planes and the bottom function row itself (shift, mode, space, return) —
/// a layout only needs to describe the three alphabetic rows, which is what
/// actually differs between QWERTY, AZERTY, Dvorak and friends.
public struct KeyboardLayout: Identifiable, Codable, Equatable, Sendable, Hashable {
    /// Stable preset identifier (e.g. `"qwerty"`, `"azerty"`).
    public var id: String
    /// Human-readable name shown in the layout picker.
    public var name: String
    /// Three rows of lowercase letter keys, top to bottom. The view upcases
    /// them when shift is engaged.
    public var rows: [[String]]

    /// - Parameters:
    ///   - id: Stable preset identifier.
    ///   - name: Display name in the layout picker.
    ///   - rows: Three lowercase letter rows (top to bottom).
    public init(id: String, name: String, rows: [[String]]) {
        self.id = id; self.name = name; self.rows = rows
    }
}

public extension KeyboardLayout {
    /// Built-in letter-plane presets shipped with Clink.
    static let presets: [KeyboardLayout] = [
        KeyboardLayout(id: "qwerty", name: "QWERTY", rows: [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["z", "x", "c", "v", "b", "n", "m"],
        ]),
        // Spanish QWERTY — adds the dedicated Ñ key after L, like the native
        // Spanish keyboard (11 keys on the home row).
        KeyboardLayout(id: "spanish", name: "Spanish (QWERTY)", rows: [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ñ"],
            ["z", "x", "c", "v", "b", "n", "m"],
        ]),
        // Portuguese QWERTY — dedicated Ç on the home row.
        KeyboardLayout(id: "portuguese", name: "Portuguese (QWERTY)", rows: [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ç"],
            ["z", "x", "c", "v", "b", "n", "m"],
        ]),
        // Turkish Q-keyboard — its own letters (ı ğ ü ş ö ç) in their native slots.
        KeyboardLayout(id: "turkish", name: "Turkish (Q)", rows: [
            ["q", "w", "e", "r", "t", "y", "u", "ı", "o", "p", "ğ", "ü"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ş", "i"],
            ["z", "x", "c", "v", "b", "n", "m", "ö", "ç"],
        ]),
        // Swedish / Finnish — å ö ä on the right edge.
        KeyboardLayout(id: "swedish", name: "Swedish / Finnish", rows: [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "å"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ö", "ä"],
            ["z", "x", "c", "v", "b", "n", "m"],
        ]),
        // Norwegian / Danish — å ø æ on the right edge.
        KeyboardLayout(id: "norwegian", name: "Norwegian / Danish", rows: [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "å"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ø", "æ"],
            ["z", "x", "c", "v", "b", "n", "m"],
        ]),
        KeyboardLayout(id: "azerty", name: "AZERTY", rows: [
            ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
            ["w", "x", "c", "v", "b", "n"],
        ]),
        KeyboardLayout(id: "qwertz", name: "QWERTZ", rows: [
            ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["y", "x", "c", "v", "b", "n", "m"],
        ]),
        // German QWERTZ — dedicated ü on the top row, ö ä on the home row,
        // matching the native German keyboard.
        KeyboardLayout(id: "german", name: "German (QWERTZ)", rows: [
            ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "ü"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ö", "ä"],
            ["y", "x", "c", "v", "b", "n", "m"],
        ]),
        KeyboardLayout(id: "dvorak", name: "Dvorak", rows: [
            ["p", "y", "f", "g", "c", "r", "l"],
            ["a", "o", "e", "u", "i", "d", "h", "t", "n", "s"],
            ["q", "j", "k", "x", "b", "m", "w", "v", "z"],
        ]),
        // Russian ЙЦУКЕН — the standard Cyrillic arrangement. Wider top rows than
        // Latin (12 / 11 keys), which the proportional row renderer handles.
        KeyboardLayout(id: "russian", name: "Russian (ЙЦУКЕН)", rows: [
            ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"],
            ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
            ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"],
        ]),
        // Ukrainian ЙЦУКЕН — its own Cyrillic set (і ї є, no ы/э/ъ).
        KeyboardLayout(id: "ukrainian", name: "Ukrainian (ЙЦУКЕН)", rows: [
            ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ї"],
            ["ф", "і", "в", "а", "п", "р", "о", "л", "д", "ж", "є"],
            ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"],
        ]),
        // Greek — the standard layout mapped onto QWERTY positions.
        KeyboardLayout(id: "greek", name: "Greek", rows: [
            ["ς", "ε", "ρ", "τ", "υ", "θ", "ι", "ο", "π"],
            ["α", "σ", "δ", "φ", "γ", "η", "ξ", "κ", "λ"],
            ["ζ", "χ", "ψ", "ω", "β", "ν", "μ"],
        ]),
    ]

    /// The layout that best matches a `UITextChecker` language identifier
    /// (e.g. "fr_FR" → AZERTY, "ru_RU" → Russian). Used to auto-pair the physical
    /// keys with a newly chosen language; everything Latin-but-unlisted falls back
    /// to QWERTY.
    static func defaultLayoutID(forLanguage identifier: String) -> String {
        let lang = identifier.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init)?.lowercased() ?? identifier.lowercased()
        switch lang {
        case "es":                     return "spanish"
        case "pt":                     return "portuguese"
        case "tr":                     return "turkish"
        case "sv", "fi":               return "swedish"
        case "nb", "nn", "no", "da":   return "norwegian"
        case "fr":                     return "azerty"
        case "de":                     return "german"
        case "uk":                     return "ukrainian"
        case "ru", "be", "bg":         return "russian"
        case "el":                     return "greek"
        default:                       return "qwerty"
        }
    }

    /// The shared number plane (page 1 of the symbol view).
    static let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]

    /// The shared symbol plane (page 2 of the symbol view).
    static let symbolRows: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]

    static let `default`: KeyboardLayout = presets[0]

    /// Returns the preset for `id`, falling back to QWERTY when unknown.
    static func preset(id: String) -> KeyboardLayout {
        presets.first { $0.id == id } ?? .default
    }
}
