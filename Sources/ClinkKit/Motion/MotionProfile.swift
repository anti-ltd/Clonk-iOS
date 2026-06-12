/**
 `MotionProfile`: the adaptive resolver every `MotionToken` passes through.

 One chokepoint between the motion vocabulary (`Motion`) and the `Animation`
 values SwiftUI runs, so system conditions the app previously ignored —
 Reduce Motion, Low Power Mode, thermal pressure — can soften or skip effects
 WITHOUT touching any of the ~80 call sites.

 Safety property: in the `.full` tier, `resolve` returns exactly
 `token.curve.animation` — byte-identical to the literal the call site used to
 build. `.full` is the tier for every user today (observers that move the tier
 are wired in Phase 3); the other tiers only activate under system states that
 currently have zero handling, so they can only improve those cases, never
 alter the tuned feel.
 

 Module: motion · Target: ClinkKit
 Learn: MOTION.md
 */
import SwiftUI
import UIKit

@MainActor @Observable
final class MotionProfile {
    static let shared = MotionProfile()

    /// How much motion the current system state wants.
    enum Tier {
        /// Everything as designed. The identity tier — and today, the only one.
        case full
        /// Low Power Mode or serious thermal pressure: curves stay (springs are
        /// CPU-cheap; changing them buys nothing) but GPU-expensive layers and
        /// ambient loops stop — see `allowsExpensiveEffects` / `allowsAmbientMotion`.
        case conserving
        /// Reduce Motion (accessibility): feedback loses overshoot, transitions
        /// shorten and flatten, ambience stops. Essential touch response is
        /// untouched — degrading it reads as broken, not calmer.
        case reduced
    }

    private(set) var tier: Tier = .full

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        refreshTier()
        // All three inputs are extension-safe notification reads — no polling,
        // no display link, nothing resident beyond three tokens.
        let center = NotificationCenter.default
        let refresh: @Sendable (Notification) -> Void = { _ in
            Task { @MainActor in MotionProfile.shared.refreshTier() }
        }
        observers = [
            center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                               object: nil, queue: .main, using: refresh),
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                               object: nil, queue: nil, using: refresh),
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                               object: nil, queue: nil, using: refresh),
        ]
    }

    /// Recompute the tier from system state. Reduce Motion is the user's
    /// explicit ask and wins; power/thermal pressure conserves; otherwise full.
    private func refreshTier() {
        if UIAccessibility.isReduceMotionEnabled {
            tier = .reduced
        } else if ProcessInfo.processInfo.isLowPowerModeEnabled
                    || [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) {
            tier = .conserving
        } else {
            tier = .full
        }
    }

    /// Gate for GPU-expensive effect layers — the additive `.plusLighter`
    /// flashes and glass droplets that historically dropped frames on older
    /// GPUs. Consulted where those layers mount, not in `resolve` (they're
    /// extra view content, not a curve).
    var allowsExpensiveEffects: Bool { tier == .full }

    /// Gate for `repeatForever` ambience. Call sites looping a `.decorative`
    /// token MUST check this before starting the loop — `resolve` can't make a
    /// forever-loop safe by shortening its curve (a zero-duration forever loop
    /// would spin hot instead of calming down).
    var allowsAmbientMotion: Bool { tier == .full }

    /// Resolve a token to the animation the call site should run.
    func resolve(_ token: MotionToken) -> Animation {
        Self.resolve(token, tier: tier)
    }

    /// The pure tier→animation mapping, separated so tests can pin every tier's
    /// behavior without faking system state.
    static func resolve(_ token: MotionToken, tier: Tier) -> Animation {
        switch tier {
        case .full, .conserving:
            // Identity. Conserving's levers are the two gates above; the
            // curves themselves cost nothing worth saving.
            return token.curve.animation
        case .reduced:
            switch token.role {
            case .essential:
                return token.curve.animation
            case .feedback:
                // Keep the confirmation, drop the overshoot.
                return .easeOut(duration: token.uiDuration)
            case .transition:
                // Short, flat, no travel theatrics.
                return .easeInOut(duration: min(token.uiDuration, 0.15))
            case .decorative:
                // Effectively instant. Looping call sites are additionally
                // gated on `allowsAmbientMotion` (see above).
                return .linear(duration: 0)
            }
        }
    }
}
