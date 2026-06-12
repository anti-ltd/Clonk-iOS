/**
 Soft lilac background with near-white keys and a violet accent.
 

 Module: theme · Target: ClinkKit
 Learn: THEMING.md
 */
extension Theme {
    /// Lilac background with near-white keys and a vivid violet accent.
    static let lavender = Theme(
        id: "lavender", name: "Lavender",
        background: RGBA(hex: 0xE5DFF5),
        keyFill: RGBA(hex: 0xF8F5FF),
        keyText: RGBA(hex: 0x352A4A),
        specialKeyFill: RGBA(hex: 0xC9BCE6),
        specialKeyText: RGBA(hex: 0x352A4A),
        accent: RGBA(hex: 0x7C5CFF),
        isDark: false
    )
}
