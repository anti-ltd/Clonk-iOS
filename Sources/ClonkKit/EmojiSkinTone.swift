import Foundation

/// A Fitzpatrick skin-tone choice for an emoji. `none` is the neutral (yellow)
/// base with no modifier; the other five map to the Unicode skin-tone modifiers
/// U+1F3FB…U+1F3FF. `Codable` so it persists in `KeyboardSettings` (both the
/// global default and the per-emoji map).
public enum SkinTone: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, light, mediumLight, medium, mediumDark, dark

    public var id: String { rawValue }

    /// The Unicode modifier scalar appended after a modifier-base scalar; `nil`
    /// for `.none` (the neutral base carries no modifier).
    public var modifier: Unicode.Scalar? {
        switch self {
        case .none:       return nil
        case .light:      return Unicode.Scalar(0x1F3FB)
        case .mediumLight: return Unicode.Scalar(0x1F3FC)
        case .medium:     return Unicode.Scalar(0x1F3FD)
        case .mediumDark: return Unicode.Scalar(0x1F3FE)
        case .dark:       return Unicode.Scalar(0x1F3FF)
        }
    }

    /// A glyph shown in the picker: a raised hand wearing this tone (the neutral
    /// hand for `.none`), so the swatches read as actual skin tones.
    public var swatch: String {
        EmojiSkinTone.applied(self, to: "✋")
    }

    public var label: String {
        switch self {
        case .none:       return "Default"
        case .light:      return "Light"
        case .mediumLight: return "Medium-Light"
        case .medium:     return "Medium"
        case .mediumDark: return "Medium-Dark"
        case .dark:       return "Dark"
        }
    }
}

/// Applying and detecting emoji skin tones. Capability is read straight from
/// Unicode properties (no keyword table), matching `EmojiData`'s name-based
/// search.
public enum EmojiSkinTone {
    /// The five skin-tone modifier scalars, used to strip existing tones.
    private static let modifierRange: ClosedRange<UInt32> = 0x1F3FB...0x1F3FF
    private static let variationSelector: Unicode.Scalar = Unicode.Scalar(0xFE0F)!

    /// True if any scalar of `emoji` is an emoji modifier base — i.e. it can
    /// carry a skin tone (hands, people, body parts, …). False for animals,
    /// flags, symbols, etc.
    public static func supportsSkinTone(_ emoji: String) -> Bool {
        emoji.unicodeScalars.contains { $0.properties.isEmojiModifierBase }
    }

    /// Return `base` with `tone` applied. For `.none` (or an emoji that can't
    /// take a tone) this strips any existing modifier and returns the neutral
    /// form. Otherwise the tone modifier is inserted after **every**
    /// modifier-base scalar (single tone applied uniformly), and a redundant
    /// U+FE0F variation selector immediately following a base is dropped — the
    /// modifier already forces emoji presentation (e.g. ☝️ U+261D U+FE0F →
    /// ☝🏽 U+261D U+1F3FD).
    public static func applied(_ tone: SkinTone, to base: String) -> String {
        var out = String.UnicodeScalarView()
        let scalars = Array(base.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            // Drop any skin-tone modifier already present (re-toning a glyph).
            if modifierRange.contains(s.value) { i += 1; continue }
            out.append(s)
            if s.properties.isEmojiModifierBase, let mod = tone.modifier {
                // Skip a variation selector that trails the base — the tone
                // modifier supersedes it.
                if i + 1 < scalars.count, scalars[i + 1] == variationSelector { i += 1 }
                out.append(mod)
            }
            i += 1
        }
        return String(out)
    }
}
