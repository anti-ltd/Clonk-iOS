/**
 Soft minty green with a teal accent. The solid counterpart to Liquid Mint.
 */
extension Theme {
    /// Minty green background with near-white keys and a teal accent.
    static let mint = Theme(
        id: "mint", name: "Mint",
        background: RGBA(hex: 0xD6EFE2),
        keyFill: RGBA(hex: 0xF4FBF7),
        keyText: RGBA(hex: 0x1E3A2C),
        specialKeyFill: RGBA(hex: 0xB2DCC6),
        specialKeyText: RGBA(hex: 0x1E3A2C),
        accent: RGBA(hex: 0x12B886),
        isDark: false
    )
}
