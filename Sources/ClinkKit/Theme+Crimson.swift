/**
 Near-black burgundy with rose text and a vivid red accent.
 

 Module: theme · Target: ClinkKit
 Learn: THEMING.md
 */
extension Theme {
    /// Near-black burgundy with pale rose text and a vivid red accent.
    static let crimson = Theme(
        id: "crimson", name: "Crimson",
        background: RGBA(hex: 0x1F0A0D),
        keyFill: RGBA(hex: 0x3D161B),
        keyText: RGBA(hex: 0xFFE8EC),
        specialKeyFill: RGBA(hex: 0x2C0F13),
        specialKeyText: RGBA(hex: 0xE9A8B2),
        accent: RGBA(hex: 0xFF2D55),
        isDark: true
    )
}
