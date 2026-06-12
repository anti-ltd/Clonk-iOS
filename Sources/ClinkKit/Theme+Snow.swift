/**
 Cool light grey background with crisp white keys. The default light preset.
 

 Module: theme · Target: ClinkKit
 Learn: THEMING.md
 */
extension Theme {
    /// Silver-grey background with crisp white keys and a system-blue accent.
    static let snow = Theme(
        id: "snow", name: "Snow",
        background: RGBA(hex: 0xD1D3D9),
        keyFill: RGBA(hex: 0xFFFFFF),
        keyText: RGBA(hex: 0x1C1C1E),
        specialKeyFill: RGBA(hex: 0xACB0BA),
        specialKeyText: RGBA(hex: 0x1C1C1E),
        accent: RGBA(hex: 0x007AFF),
        isDark: false
    )
}
