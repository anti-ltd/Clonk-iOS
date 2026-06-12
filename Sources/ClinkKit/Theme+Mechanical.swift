/**
 Dark warm brown with ivory text and a golden accent — vintage keycap feel.
 

 Module: theme · Target: ClinkKit
 Learn: THEMING.md
 */
extension Theme {
    /// Warm dark brown with ivory lettering and an amber-gold accent.
    static let mechanical = Theme(
        id: "mechanical", name: "Mechanical",
        background: RGBA(hex: 0x2B2622),
        keyFill: RGBA(hex: 0x4A423A),
        keyText: RGBA(hex: 0xF4E9D8),
        specialKeyFill: RGBA(hex: 0x352F29),
        specialKeyText: RGBA(hex: 0xD8C7AE),
        accent: RGBA(hex: 0xE0A458),
        isDark: true
    )
}
