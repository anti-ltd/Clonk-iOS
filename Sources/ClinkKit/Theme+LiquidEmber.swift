/**
 Liquid Glass over a deep charred-red backdrop with an orange accent.
 

 Module: theme · Target: ClinkKit
 Learn: THEMING.md
 */
extension Theme {
    /// Glass preset tinted deep red with a vivid orange accent.
    static let liquidEmber = Theme(
        id: "liquid-ember", name: "Liquid Ember",
        background: RGBA(hex: 0x2A1410, a: 0.30),
        keyFill: RGBA(hex: 0xFFFFFF, a: 0.10),
        keyText: RGBA(hex: 0xFFF0E8),
        specialKeyFill: RGBA(hex: 0xFFFFFF, a: 0.06),
        specialKeyText: RGBA(hex: 0xFFD9C7),
        accent: RGBA(hex: 0xFF6B35),
        isDark: true, material: .liquidGlass
    )
}
