/**
 Deep green canopy with a vivid spring-green accent.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
extension Theme {
    /// Deep forest green with pale foliage text and a bright spring-green accent.
    static let forest = Theme(
        id: "forest", name: "Forest",
        background: RGBA(hex: 0x12241B),
        keyFill: RGBA(hex: 0x1F4332),
        keyText: RGBA(hex: 0xEAF6EE),
        specialKeyFill: RGBA(hex: 0x18301F),
        specialKeyText: RGBA(hex: 0xBFE3CC),
        accent: RGBA(hex: 0x55D98C),
        isDark: true
    )
}
