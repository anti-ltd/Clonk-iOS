/**
 Canonical dark Liquid Glass preset. Translucent tinted keys refract any background.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
extension Theme {
    // Colors act as tints; translucent backdrop so the keys refract the system keyboard background.
    /// Dark glass preset: barely-there translucent keys with a system-blue accent.
    static let liquidDark = Theme(
        id: "liquid-dark", name: "Liquid Dark",
        background: RGBA(hex: 0x1C1C1E, a: 0.28),
        keyFill: RGBA(hex: 0xFFFFFF, a: 0.10),
        keyText: RGBA(hex: 0xFFFFFF),
        specialKeyFill: RGBA(hex: 0xFFFFFF, a: 0.06),
        specialKeyText: RGBA(hex: 0xF2F2F7),
        accent: RGBA(hex: 0x0A84FF),
        isDark: true, material: .liquidGlass
    )
}
