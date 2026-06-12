/**
 Liquid Glass over a mint-tinted backdrop with a teal accent.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
extension Theme {
    /// Glass preset tinted mint-green with a teal accent.
    static let liquidMint = Theme(
        id: "liquid-mint", name: "Liquid Mint",
        background: RGBA(hex: 0xD6EFE2, a: 0.20),
        keyFill: RGBA(hex: 0xFFFFFF, a: 0.30),
        keyText: RGBA(hex: 0x143324),
        specialKeyFill: RGBA(hex: 0x000000, a: 0.05),
        specialKeyText: RGBA(hex: 0x143324),
        accent: RGBA(hex: 0x12B886),
        isDark: false, material: .liquidGlass
    )
}
