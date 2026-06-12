/**
 Warm off-white background with cream keys and a terracotta accent.
 

 Module: theme · Target: ClinkKit
 Learn: THEMING.md
 */
extension Theme {
    /// Warm parchment tones with a burnt-orange accent.
    static let paper = Theme(
        id: "paper", name: "Paper",
        background: RGBA(hex: 0xE8E2D4),
        keyFill: RGBA(hex: 0xFBF7EE),
        keyText: RGBA(hex: 0x3A352B),
        specialKeyFill: RGBA(hex: 0xC9C1AE),
        specialKeyText: RGBA(hex: 0x3A352B),
        accent: RGBA(hex: 0xC2683A),
        isDark: false
    )
}
