/**
 Classic Dracula palette: charcoal background, lavender function keys, pink accent.
 */
extension Theme {
    /// Charcoal-purple background with lavender function-key text and hot-pink accent.
    static let dracula = Theme(
        id: "dracula", name: "Dracula",
        background: RGBA(hex: 0x282A36),
        keyFill: RGBA(hex: 0x44475A),
        keyText: RGBA(hex: 0xF8F8F2),
        specialKeyFill: RGBA(hex: 0x21222C),
        specialKeyText: RGBA(hex: 0xBD93F9),
        accent: RGBA(hex: 0xFF79C6),
        isDark: true
    )
}
