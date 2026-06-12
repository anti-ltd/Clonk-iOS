/**
 Near-black background with phosphor green text. Terminal console aesthetic.
 

 Module: theme · Target: ClinkKit
 Learn: THEMING.md
 */
extension Theme {
    /// Pure black with phosphor-green key labels and a bright green accent.
    static let matrix = Theme(
        id: "matrix", name: "Matrix",
        background: RGBA(hex: 0x000A00),
        keyFill: RGBA(hex: 0x062E06),
        keyText: RGBA(hex: 0x4DFF4D),
        specialKeyFill: RGBA(hex: 0x031B03),
        specialKeyText: RGBA(hex: 0x2ECC40),
        accent: RGBA(hex: 0x00FF41),
        isDark: true
    )
}
