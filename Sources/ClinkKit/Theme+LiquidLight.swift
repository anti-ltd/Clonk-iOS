/**
 Canonical light Liquid Glass preset. Frosted white keys refract any background.
 */
extension Theme {
    /// Light glass preset: frosted near-white keys with a system-blue accent.
    static let liquidLight = Theme(
        id: "liquid-light", name: "Liquid Light",
        background: RGBA(hex: 0xF5F5F7, a: 0.22),
        keyFill: RGBA(hex: 0xFFFFFF, a: 0.32),
        keyText: RGBA(hex: 0x1C1C1E),
        specialKeyFill: RGBA(hex: 0x000000, a: 0.06),
        specialKeyText: RGBA(hex: 0x1C1C1E),
        accent: RGBA(hex: 0x007AFF),
        isDark: false, material: .liquidGlass
    )
}
