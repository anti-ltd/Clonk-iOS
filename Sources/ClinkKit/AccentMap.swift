/**
 `AccentMap`: the long-press accent/diacritic variants for a base letter, à la
 the system keyboard's hold-to-reveal accent row (hold "e" → è é ê ë …). Latin
 only — Cyrillic/Greek layouts have no entries here and simply show no accent
 popup. Keys are lowercase base letters; the keyboard applies the current shift
 case to each variant before display.
 

 Module: touch · Target: ClinkKit
 Learn: docs/03-touch-and-input.md
 */
import Foundation

enum AccentMap {
    /// Accent variants for a lowercase base letter, in the order the system
    /// keyboard offers them. Empty for letters with no common accents.
    static let variants: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
        "c": ["ç", "ć", "č"],
        "d": ["ð"],
        "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
        "g": ["ğ"],
        "i": ["î", "ï", "í", "ī", "į", "ì"],
        "l": ["ł"],
        "n": ["ñ", "ń"],
        "o": ["ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"],
        "s": ["ß", "ś", "š"],
        "u": ["û", "ü", "ù", "ú", "ū"],
        "y": ["ÿ", "ý"],
        "z": ["ž", "ź", "ż"],
    ]

    /// The full ordered option list for an already-cased base glyph: the base
    /// itself first (so releasing without sliding keeps what was typed), then its
    /// accent variants in the same case. Returns an empty array when the base has
    /// no accents — the caller then shows no popup.
    ///
    /// `glyph` is the base as it appears on the key (already upper/lower per
    /// shift); case is propagated to every variant so a shifted "E" yields
    /// "È É Ê …".
    static func options(forCasedGlyph glyph: String) -> [String] {
        let lower = glyph.lowercased()
        guard let vars = variants[lower], !vars.isEmpty else { return [] }
        let uppercased = glyph != lower            // the key is shifted
        let cased = uppercased ? vars.map { $0.uppercased() } : vars
        return [glyph] + cased
    }
}
