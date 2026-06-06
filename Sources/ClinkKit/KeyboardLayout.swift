/**
 `KeyboardLayout`: the letter-plane key arrangement for one locale. Ships with
 four built-in presets (QWERTY, AZERTY, QWERTZ, Dvorak) plus the shared
 number-row and symbol-row definitions used by every layout.
 */
import Foundation

/// A keyboard's letter-plane arrangement. Clink lays out the number/symbol
/// planes and the bottom function row itself (shift, mode, space, return) —
/// a layout only needs to describe the three alphabetic rows, which is what
/// actually differs between QWERTY, AZERTY, Dvorak and friends.
public struct KeyboardLayout: Identifiable, Codable, Equatable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// Three rows of lowercase letter keys, top to bottom. The view upcases
    /// them when shift is engaged.
    public var rows: [[String]]

    public init(id: String, name: String, rows: [[String]]) {
        self.id = id; self.name = name; self.rows = rows
    }
}

public extension KeyboardLayout {
    static let presets: [KeyboardLayout] = [
        KeyboardLayout(id: "qwerty", name: "QWERTY", rows: [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
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
        KeyboardLayout(id: "dvorak", name: "Dvorak", rows: [
            ["p", "y", "f", "g", "c", "r", "l"],
            ["a", "o", "e", "u", "i", "d", "h", "t", "n", "s"],
            ["q", "j", "k", "x", "b", "m", "w", "v", "z"],
        ]),
    ]

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

    static func preset(id: String) -> KeyboardLayout {
        presets.first { $0.id == id } ?? .default
    }
}
