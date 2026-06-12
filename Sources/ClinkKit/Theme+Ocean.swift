/**
 Deep ocean teal with aquamarine keys and a vivid cyan accent.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
extension Theme {
    /// Dark teal background with aquamarine keys and a bright cyan accent.
    static let ocean = Theme(
        id: "ocean", name: "Ocean",
        background: RGBA(hex: 0x0A1F2B),
        keyFill: RGBA(hex: 0x123C4A),
        keyText: RGBA(hex: 0xE0F7FA),
        specialKeyFill: RGBA(hex: 0x0C2D38),
        specialKeyText: RGBA(hex: 0xA7DDE6),
        accent: RGBA(hex: 0x21D4C6),
        isDark: true
    )
}
