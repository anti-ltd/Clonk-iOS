/**
 Supporting types for `Theme`: gradient model (`ThemeGradient`, `GradientStop`,
 `GradientType`), font options (`ThemeFontDesign`, `ThemeFontWeight`), key
 material (`KeyMaterial`), and glass variant (`GlassVariant`).
 

 Module: theme · Target: ClinkKit
 Learn: THEMING.md
 */
import SwiftUI

// MARK: - Gradient types

public enum GradientType: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case linear, radial, angular
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .linear:  return "Linear"
        case .radial:  return "Radial"
        case .angular: return "Angular"
        }
    }
}

/// One color stop in a `ThemeGradient`. The `id` is ephemeral (not persisted)
/// so ForEach can track stops without requiring stable encoded identifiers.
public struct GradientStop: Sendable, Equatable, Hashable, Identifiable {
    public var id = UUID()
    public var color: RGBA
    public var position: Double  // 0…1

    public init(color: RGBA, position: Double) {
        self.color = color; self.position = position
    }
}

extension GradientStop: Codable {
    private enum CodingKeys: String, CodingKey { case color, position }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decode(RGBA.self, forKey: .color)
        position = try c.decode(Double.self, forKey: .position)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(color, forKey: .color)
        try c.encode(position, forKey: .position)
    }
}

public struct ThemeGradient: Codable, Sendable, Equatable, Hashable {
    public var type: GradientType
    /// Rotation in degrees (0–360). Used by linear and angular; ignored by radial.
    public var rotation: Double
    public var stops: [GradientStop]

    public init(type: GradientType = .linear, rotation: Double = 180, stops: [GradientStop]) {
        self.type = type; self.rotation = rotation; self.stops = stops
    }

    /// A two-stop gradient seeded from `color`, lightened toward the second stop.
    public static func seed(from color: RGBA) -> ThemeGradient {
        let lighter = RGBA(min(color.r + 0.25, 1), min(color.g + 0.25, 1), min(color.b + 0.25, 1), color.a)
        return ThemeGradient(stops: [
            GradientStop(color: color, position: 0),
            GradientStop(color: lighter, position: 1),
        ])
    }
}

public extension ThemeGradient {
    private var swiftGradient: Gradient {
        let sorted = stops.sorted { $0.position < $1.position }
        return Gradient(stops: sorted.map { .init(color: $0.color.color, location: $0.position) })
    }

    @ViewBuilder func makeView() -> some View {
        let g = swiftGradient
        switch type {
        case .linear:
            LinearGradient(gradient: g, startPoint: linearStart, endPoint: linearEnd)
        case .radial:
            RadialGradient(gradient: g, center: .center, startRadius: 0, endRadius: 800)
        case .angular:
            AngularGradient(gradient: g, center: .center, angle: .degrees(rotation))
        }
    }

    private var linearStart: UnitPoint {
        let rad = (rotation - 90) * .pi / 180
        return UnitPoint(x: 0.5 - cos(rad) * 0.5, y: 0.5 - sin(rad) * 0.5)
    }
    private var linearEnd: UnitPoint {
        let rad = (rotation - 90) * .pi / 180
        return UnitPoint(x: 0.5 + cos(rad) * 0.5, y: 0.5 + sin(rad) * 0.5)
    }
}

// MARK: - Font design / weight

public enum ThemeFontDesign: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case `default`, rounded, serif, monospaced
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .default:    return "Default"
        case .rounded:    return "Rounded"
        case .serif:      return "Serif"
        case .monospaced: return "Mono"
        }
    }
    public var fontDesign: Font.Design {
        switch self {
        case .default:    return .default
        case .rounded:    return .rounded
        case .serif:      return .serif
        case .monospaced: return .monospaced
        }
    }
}

public enum ThemeFontWeight: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case thin, ultraLight, light, regular, medium, semibold, bold, heavy, black
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .thin:       return "Thin"
        case .ultraLight: return "Ultra Light"
        case .light:      return "Light"
        case .regular:    return "Regular"
        case .medium:     return "Medium"
        case .semibold:   return "Semibold"
        case .bold:       return "Bold"
        case .heavy:      return "Heavy"
        case .black:      return "Black"
        }
    }
    public var fontWeight: Font.Weight {
        switch self {
        case .thin:       return .thin
        case .ultraLight: return .ultraLight
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        }
    }
}

// MARK: - Key material

/// How a theme's keys are rendered.
public enum KeyMaterial: String, Codable, Sendable, Hashable {
    /// Opaque key faces filled with the theme's colors.
    case solid
    /// Apple's Liquid Glass — translucent, refractive keys (iOS 26+, with an
    /// `.ultraThinMaterial` fallback below that). The theme's colors become
    /// tints and text colors; the background goes translucent so the keys
    /// refract the system keyboard backdrop.
    case liquidGlass
}

/// Which Liquid Glass variant the keys use. `regular` is the frostier, more
/// material look; `clear` is thinner and far more see-through — it refracts the
/// backdrop more strongly. Maps to SwiftUI's `Glass.regular` / `Glass.clear`.
public enum GlassVariant: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case regular
    case clear

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .regular: return "Regular"
        case .clear:   return "Clear"
        }
    }
}
