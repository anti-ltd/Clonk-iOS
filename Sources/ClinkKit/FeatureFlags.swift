/**
 Runtime feature flags driven by launch arguments.

 Pass `--experimental` in the Xcode scheme (Product → Scheme → Run → Arguments)
 to unlock features that are temporarily hidden from the App Store build.

 This file lives in Sources/ClinkKit so it compiles into both the main app
 (Clink) and the keyboard extension (ClinkKeyboard). In the keyboard extension
 process ProcessInfo never receives --experimental, so experimental is always
 false there — ensuring gated features cannot execute in the extension either.

 Usage:
     if FeatureFlags.experimental { ... }
 */
import Foundation

enum FeatureFlags {
    /// True when launched with `--experimental` (Xcode scheme → Run → Arguments).
    /// Always false in the keyboard extension process.
    static let experimental: Bool =
        ProcessInfo.processInfo.arguments.contains("--experimental")

    /// True when launched with `--motion-hud`: overlays the debug FPS/hitch HUD
    /// (see `MotionHUD`). Launch-arg gated like `experimental`, so it can never
    /// run in the keyboard extension process — profile the extension with
    /// Instruments via `MotionDiagnostics` signposts instead.
    static let motionHUD: Bool =
        ProcessInfo.processInfo.arguments.contains("--motion-hud")
}
