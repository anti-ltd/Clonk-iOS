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
@MainActor
final class SoundPlayer {
    /// Pre-loaded players keyed by sample filename, so playback never touches
    /// the disk on the main thread mid-typing.
    private var players: [String: AVAudioPlayer] = [:]
    private var rotation = 0
    private var sessionActivated = false

    private let haptics = UIImpactFeedbackGenerator(style: .light)

    /// Play feedback for one keypress.
    func play(settings: KeyboardSettings, hasFullAccess: Bool) {
        guard settings.soundEnabled || settings.hapticsEnabled else { return }

        if settings.hapticsEnabled, hasFullAccess {
            haptics.impactOccurred(intensity: 0.6)
            // Re-prime immediately: the generator's engine spins back down after
            // ~1–2s idle, so without this the *next* tap in a fast burst has
            // noticeably higher latency. Keeping it warm makes every keystroke's
            // haptic land with the same crispness.
            haptics.prepare()
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
        if settings.hapticsEnabled, hasFullAccess { haptics.prepare() }
        guard settings.soundEnabled, hasFullAccess, settings.soundPack.needsFullAccess else { return }
        for name in settings.soundPack.sampleNames where players[name] == nil {
            guard let url = Bundle.main.url(
                forResource: name, withExtension: settings.soundPack.fileExtension, subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: name, withExtension: settings.soundPack.fileExtension)
            else { continue }
            players[name] = try? AVAudioPlayer(contentsOf: url)
            players[name]?.prepareToPlay()
        }
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
