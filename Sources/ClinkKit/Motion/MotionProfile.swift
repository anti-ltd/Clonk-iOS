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
 Learn: docs/12-motion.md
 */
import SwiftUI
import UIKit
import QuartzCore

/// Adaptive resolver every `MotionToken.animation` passes through. In the `.full`
/// tier (default), resolved curves are byte-identical to the raw token; under
/// Reduce Motion, tokens degrade by role — essential touch response is untouched.
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

    /// True when this code runs inside an app extension (the keyboard), whose
    /// memory ceiling is a few tens of MB and where GPU compositing is the first
    /// thing to suffer — unlike the host app, which has the whole device. The
    /// extension wires a memory-pressure source (see `KeyboardViewController`)
    /// that the app has no need for.
    static let isAppExtension: Bool = Bundle.main.bundlePath.hasSuffix(".appex")

    /// Set by the keyboard extension on system memory pressure. Memory — not
    /// thermal or battery — is the extension's binding constraint, and it chokes
    /// GPU compositing long before `thermalState` climbs, so it gets its own
    /// input into the tier. The call site is responsible for any sticky decay;
    /// here it simply forces `.conserving` while set.
    @ObservationIgnored private var memoryPressure = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// True while the user types fast enough that per-key glass bloom/glow would
    /// steal frames from touch delivery — the next key's `touchesBegan` slips
    /// behind the bloom spring's per-frame lens re-raster, felt as haptic lag.
    /// While set, keys snap (tint flip, no sprung lens deformation) and the press
    /// glow is suppressed, so a burst composites at most one raster per key
    /// instead of a spring's worth. Auto-clears after `burstDecay` of quiet, so a
    /// single tap or relaxed typing keeps the full bloom. Observable: it flips
    /// only on burst ENTER/EXIT (guarded below), never per keystroke.
    private(set) var typingBurst = false
    @ObservationIgnored private var lastKeystroke: CFTimeInterval = 0
    @ObservationIgnored private var burstClear: DispatchWorkItem?
    /// Inter-key gap (s) at or below which typing counts as a burst — ~8 keys/s.
    private static let burstGap: CFTimeInterval = 0.12
    /// Quiet (s) after the last keystroke before the bloom returns.
    private static let burstDecay: CFTimeInterval = 0.16

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
        } else if memoryPressure
                    || ProcessInfo.processInfo.isLowPowerModeEnabled
                    || [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) {
            tier = .conserving
        } else {
            tier = .full
        }
    }

    /// Note a change in memory pressure (keyboard extension only). While set the
    /// tier is forced to `.conserving`, which sheds glass and the expensive
    /// layers; clearing it re-derives the tier from the remaining system state.
    /// No-op if unchanged so we never thrash the observable.
    func setMemoryPressure(_ active: Bool) {
        guard memoryPressure != active else { return }
        memoryPressure = active
        refreshTier()
    }

    /// Record a keystroke. Enters the typing-burst tier when keys arrive within
    /// `burstGap` of each other, and (re)schedules its clearance after
    /// `burstDecay` of quiet. Cheap on the hot path: the observable flips only on
    /// burst ENTER (and once on EXIT via the work item), never on every key.
    func noteKeystroke() {
        let now = CACurrentMediaTime()
        let fast = now - lastKeystroke <= Self.burstGap
        lastKeystroke = now
        if fast, !typingBurst { typingBurst = true }
        guard typingBurst else { return }
        burstClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.typingBurst = false }
        burstClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.burstDecay, execute: work)
    }

    /// Gate for GPU-expensive effect layers — the additive `.plusLighter`
    /// flashes and glass droplets that historically dropped frames on older
    /// GPUs. Consulted where those layers mount, not in `resolve` (they're
    /// extra view content, not a curve). Also drops during a typing burst, when
    /// every spare frame belongs to touch delivery, not glow.
    var allowsExpensiveEffects: Bool { tier == .full && !typingBurst }

    /// While set, key presses snap (instant tint, no sprung glass deformation)
    /// so a fast burst never queues a per-frame lens re-raster ahead of the next
    /// key's touch delivery. Read by `KeyView` for both the bloom warp and the
    /// press animation. Single taps / relaxed typing are never in a burst, so the
    /// full bloom is unaffected.
    var prefersInstantKeyPress: Bool { typingBurst }

    /// Gate for the liquid-glass surface render — `GlassEffectContainer` plus the
    /// per-key glass lenses, the single heaviest thing the keyboard composites.
    /// Glass is a user *preference*; fluid typing is a *requirement*, so under a
    /// conserving state (Low Power, thermal, or — in the extension — memory
    /// pressure) the surfaces fall back to a solid render until the pressure
    /// clears (see `Theme.effective`). `.reduced` keeps glass: Reduce Motion is
    /// about movement, not fill, and a static lens costs nothing in motion terms.
    var prefersSolidSurfaces: Bool { tier == .conserving }

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
