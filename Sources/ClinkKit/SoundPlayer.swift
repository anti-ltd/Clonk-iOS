/**
 `SoundPlayer`: plays a key-click audio sample and haptic on each key press.
 Requires Full Access for custom sound packs; falls back to `AudioServicesPlaySystemSound`
 for the standard click when Full Access is absent.
 

 Module: sound · Target: ClinkKit
 Learn: docs/06-sound.md
 */
import AVFoundation
import AudioToolbox
import UIKit

/// Plays a key sound + haptic on each press.
///
/// Two paths, picked at play time:
///  • Custom "clink" pack — bundled samples via `AVAudioPlayer`. Needs Full
///    Access (iOS silences an extension's audio session otherwise), so it's
///    gated on `hasFullAccess`.
///  • System click — `UIDevice.playInputClick()`, which works WITHOUT Full
///    Access as long as the input view conforms to `UIInputViewAudioFeedback`.
///    This is the privacy-first default.
///
/// If a custom pack is selected but its samples aren't bundled yet (v0.1 ships
/// the pipeline ahead of the curated audio), playback falls back to the system
/// click — so the keyboard always feels responsive.
/// Key-click audio + haptic feedback for the keyboard extension.
@MainActor
final class SoundPlayer {
    /// Pre-loaded players keyed by sample filename, so playback never touches
    /// the disk on the main thread mid-typing.
    private var players: [String: AVAudioPlayer] = [:]
    private var rotation = 0
    private var sessionActivated = false

    /// Haptic generator + the style it was built for. Rebuilt lazily whenever the
    /// user changes `hapticStyle` (the style is fixed at construction).
    private var haptics = UIImpactFeedbackGenerator(style: .light)
    private var haptchStyle: HapticStyle = .light

    /// Heartbeat that re-primes the Taptic Engine while the keyboard is on screen.
    /// `impactOccurred`'s re-prime (in `play`) only keeps the engine warm for the
    /// ~1–2s *between keys in a burst*; once typing pauses past that, the engine
    /// spins down and the FIRST key after the pause lands its haptic tens of ms
    /// late. A low-rate prepare keeps it perpetually warm so no press ever hits a
    /// cold engine. Lives only while the keyboard is visible (see start/stop).
    private var keepWarm: Timer?
    /// Latest play/prepare context, so the heartbeat knows whether to fire.
    private var lastSettings: KeyboardSettings?
    private var lastFullAccess = false

    private static func uiStyle(_ s: HapticStyle) -> UIImpactFeedbackGenerator.FeedbackStyle {
        switch s {
        case .light:  return .light
        case .medium: return .medium
        case .heavy:  return .heavy
        case .rigid:  return .rigid
        case .soft:   return .soft
        }
    }

    /// The generator for `style`, rebuilt (and re-primed) if the style changed.
    private func generator(for style: HapticStyle) -> UIImpactFeedbackGenerator {
        if style != haptchStyle {
            haptics = UIImpactFeedbackGenerator(style: Self.uiStyle(style))
            haptchStyle = style
            haptics.prepare()
        }
        return haptics
    }

    /// Play feedback for one keypress.
    func play(settings: KeyboardSettings, hasFullAccess: Bool) {
        lastSettings = settings
        lastFullAccess = hasFullAccess
        guard settings.soundEnabled || settings.hapticsEnabled else { return }

        if settings.hapticsEnabled, hasFullAccess {
            let gen = generator(for: settings.hapticStyle)
            gen.impactOccurred(intensity: settings.hapticIntensity)
            // Re-prime immediately: the generator's engine spins back down after
            // ~1–2s idle, so without this the *next* tap in a fast burst has
            // noticeably higher latency. Keeping it warm makes every keystroke's
            // haptic land with the same crispness.
            gen.prepare()
        }

        guard settings.soundEnabled else { return }

        let pack = settings.soundPack
        if hasFullAccess, pack.needsFullAccess,
           let player = nextPlayer(for: pack) {
            activateSessionIfNeeded()
            player.volume = Float(settings.soundVolume)
            player.currentTime = 0
            player.play()
        } else {
            // Privacy-first fallback — the standard iOS click.
            UIDevice.current.playInputClick()
        }
    }

    /// Warm the haptic engine and decode the pack's samples ahead of typing.
    func prepare(for settings: KeyboardSettings, hasFullAccess: Bool) {
        lastSettings = settings
        lastFullAccess = hasFullAccess
        if settings.hapticsEnabled, hasFullAccess { generator(for: settings.hapticStyle).prepare() }
        guard settings.soundEnabled, hasFullAccess, settings.soundPack.needsFullAccess else { return }
        // Activate the audio session NOW, at keyboard load — `setActive` is a
        // slow cross-process call (tens of ms), and doing it lazily inside
        // `play` made the very first keypress visibly hitch. `play` keeps its
        // lazy call only as a fallback for settings changed mid-session.
        activateSessionIfNeeded()
        for name in settings.soundPack.sampleNames where players[name] == nil {
            guard let url = Bundle.main.url(
                forResource: name, withExtension: settings.soundPack.fileExtension, subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: name, withExtension: settings.soundPack.fileExtension)
            else { continue }
            players[name] = try? AVAudioPlayer(contentsOf: url)
            players[name]?.prepareToPlay()
        }
    }

    /// Start the keep-warm heartbeat. Call when the keyboard appears. Idempotent.
    /// The interval is shorter than the Taptic Engine's ~1–2s spin-down so the
    /// engine is always primed; it's a no-op tick when haptics are off or Full
    /// Access is absent, so it costs nothing in those cases.
    func startKeepWarm() {
        keepWarm?.invalidate()
        let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rePrime() }
        }
        // .common so it keeps firing while the user scrolls/holds a key.
        RunLoop.main.add(timer, forMode: .common)
        keepWarm = timer
    }

    /// Stop the heartbeat. Call when the keyboard disappears — no point heating
    /// the engine (or holding a Timer) while we're off screen.
    func stopKeepWarm() {
        keepWarm?.invalidate()
        keepWarm = nil
    }

    private func rePrime() {
        guard let s = lastSettings, s.hapticsEnabled, lastFullAccess else { return }
        generator(for: s.hapticStyle).prepare()
    }

    private func nextPlayer(for pack: SoundPack) -> AVAudioPlayer? {
        let loaded = pack.sampleNames.compactMap { players[$0] }
        guard !loaded.isEmpty else { return nil }
        defer { rotation += 1 }
        return loaded[rotation % loaded.count]
    }

    private func activateSessionIfNeeded() {
        guard !sessionActivated else { return }
        let session = AVAudioSession.sharedInstance()
        // .ambient + mixWithOthers: clink over the user's music, never duck or
        // stop it. The keyboard is a guest in someone else's app.
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        sessionActivated = true
    }
}
