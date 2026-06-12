/**
 Clean off-white with serif key labels and a coral-red accent. Light twin to Cinder.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
extension Theme {
    /// Off-white with serif lettering and a coral-red accent.
    static let coral = Theme(
        id: "coral", name: "Coral",
        background: RGBA(hex: 0xF9F5EF),
        keyFill: RGBA(hex: 0xFFFFFF),
        keyText: RGBA(hex: 0x2A1F1A),
        specialKeyFill: RGBA(hex: 0xEDE4D8),
        specialKeyText: RGBA(hex: 0x2A1F1A),
        accent: RGBA(hex: 0xD4614A),
        isDark: false,
        keyFontDesign: .serif
    )
}
