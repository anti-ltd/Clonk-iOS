import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Codable, value-type color used throughout Clink so a `Theme` can round-trip
/// through the App Group `UserDefaults` as JSON. SwiftUI's `Color` is not
/// reliably Codable across OS versions, so we store raw sRGB components and
/// bridge to `Color` on demand.
public struct RGBA: Codable, Equatable, Sendable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `RGBA(hex: 0x1C1C1E)` — convenient for design tokens.
    public init(hex: UInt32, a: Double = 1) {
        self.r = Double((hex >> 16) & 0xFF) / 255.0
        self.g = Double((hex >> 8) & 0xFF) / 255.0
        self.b = Double(hex & 0xFF) / 255.0
        self.a = a
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    #if canImport(UIKit)
    /// Build from a SwiftUI `Color` (resolved through UIKit) — used by the
    /// in-app theme editor's `ColorPicker`s to capture a chosen colour.
    public init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }
    #endif

    #if canImport(UIKit)
    /// UIKit bridge — lets the keyboard extension tint its `UIInputView` to
    /// match, so any home-indicator safe-area band blends into the keyboard.
    public var uiColor: UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }
    #endif
}
