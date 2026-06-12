/**
 Pure black with near-invisible dark keys and a vivid red accent.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
extension Theme {
    /// Pure black background with near-invisible keys and a vivid red accent.
    static let carbon = Theme(
        id: "carbon", name: "Carbon",
        background: RGBA(hex: 0x000000),
        keyFill: RGBA(hex: 0x141414),
        keyText: RGBA(hex: 0xFFFFFF),
        specialKeyFill: RGBA(hex: 0x0A0A0A),
        specialKeyText: RGBA(hex: 0xBFBFBF),
        accent: RGBA(hex: 0xFF453A),
        isDark: true
    )
}
