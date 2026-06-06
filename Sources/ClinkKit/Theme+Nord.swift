/**
 Arctic blue-grey palette based on the Nord color scheme.
 */
extension Theme {
    /// Arctic blue-grey with a muted teal accent, following the Nord palette.
    static let nord = Theme(
        id: "nord", name: "Nord",
        background: RGBA(hex: 0x2E3440),
        keyFill: RGBA(hex: 0x3B4252),
        keyText: RGBA(hex: 0xECEFF4),
        specialKeyFill: RGBA(hex: 0x272C36),
        specialKeyText: RGBA(hex: 0xD8DEE9),
        accent: RGBA(hex: 0x88C0D0),
        isDark: true
    )
}
