/**
 Near-black slate with blue-grey keys. The default dark preset.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
extension Theme {
    /// Near-black slate with blue-grey keys and a system-blue accent.
    static let graphite = Theme(
        id: "graphite", name: "Graphite",
        background: RGBA(hex: 0x1C1C1E),
        keyFill: RGBA(hex: 0x3A3A3C),
        keyText: RGBA(hex: 0xFFFFFF),
        specialKeyFill: RGBA(hex: 0x2C2C2E),
        specialKeyText: RGBA(hex: 0xEBEBF0),
        accent: RGBA(hex: 0x0A84FF),
        isDark: true
    )
}
