/**
 Solarized Dark: deep teal base with warm grey text, following the Solarized palette.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
extension Theme {
    /// Deep teal background with the canonical Solarized warm-grey text and cyan accent.
    static let solarizedDark = Theme(
        id: "solarized-dark", name: "Solarized Dark",
        background: RGBA(hex: 0x002B36),
        keyFill: RGBA(hex: 0x073642),
        keyText: RGBA(hex: 0xD3CBB7),
        specialKeyFill: RGBA(hex: 0x00252E),
        specialKeyText: RGBA(hex: 0x93A1A1),
        accent: RGBA(hex: 0x2AA198),
        isDark: true
    )
}
