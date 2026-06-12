/**
 Dark warm near-black with serif key labels and a coral-red accent. Dark twin to Coral.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
extension Theme {
    /// Warm near-black with serif lettering and a coral-red accent.
    static let cinder = Theme(
        id: "cinder", name: "Cinder",
        background: RGBA(hex: 0x1A1512),
        keyFill: RGBA(hex: 0x2E2521),
        keyText: RGBA(hex: 0xF2EDE4),
        specialKeyFill: RGBA(hex: 0x231B17),
        specialKeyText: RGBA(hex: 0xC4B8AE),
        accent: RGBA(hex: 0xD4614A),
        isDark: true,
        keyFontDesign: .serif
    )
}
