import SwiftUI
import UIKit

/// The Clink keyboard extension's principal class. Hosts the shared
/// `KeyboardCanvas` (SwiftUI) inside a `UIInputViewController`, wires its key
/// events to the document proxy, plays sound/haptics on each press, and feeds
/// it offline autocomplete suggestions (via `UITextChecker`).
///
/// `@objc(KeyboardViewController)` makes the bare name in Info.plist's
/// `NSExtensionPrincipalClass` resolve without a module prefix.
@objc(KeyboardViewController)
final class KeyboardViewController: UIInputViewController {

    private let store = SharedStore.shared
    private let sound = SoundPlayer()
    private let live = KeyboardLiveState()
    /// Offline autocomplete + auto-correct. `UITextChecker` is comparatively
    /// slow, so rather than run it on every keystroke (which made fast typing
    /// stutter) we debounce: a burst of keys only triggers ONE compute, once
    /// typing settles. See `scheduleSuggestionUpdate`.
    private let engine = SuggestionEngine()
    /// Coalesces per-keystroke suggestion recomputes (cancelled + rescheduled
    /// on each change) so we run the checker once typing settles, not per key.
    private var suggestionWork: DispatchWorkItem?
    /// A correction the user explicitly rejected (tapped "keep") — suppressed
    /// until they move on to a different word.
    private var rejectedCorrection: String?

    // MARK: - Local text mirror
    //
    // `documentContextBeforeInput` is a cross-process read that also lags one
    // runloop tick behind our own edits, so hitting it on every keystroke is both
    // slow and occasionally stale. Instead we keep a local mirror of the tail of
    // what we've typed and read from that on the hot path, re-seeding from the
    // proxy only when the mirror can't be trusted (cursor moved, external edit,
    // focus change). `isApplyingEdit` marks our own mutations so the change
    // callbacks don't mistake them for external edits.

    /// The trailing characters of the document before the cursor, as far as we've
    /// mirrored them (capped at `tailCap`). Only meaningful when `bufferValid`.
    private var recentTail: String = ""
    /// Whether `recentTail` is currently in sync with the document.
    private var bufferValid: Bool = false
    /// True while we're performing our own proxy edits (so selection/text change
    /// callbacks don't invalidate the mirror for our own work).
    private var isApplyingEdit: Bool = false
    /// How many trailing characters we keep. Comfortably longer than any word so
    /// trailing-word + smart-punctuation lookbehind always have what they need.
    private let tailCap = 16
    private var settings = KeyboardSettings.default
    private var hosting: UIHostingController<AnyView>?
    private var heightConstraint: NSLayoutConstraint?
    private var changeToken: AnyObject?

    /// Sendable weak handle so the @Sendable Darwin-notification closure can
    /// hop back to this (non-Sendable, MainActor) controller.
    private final class WeakBox: @unchecked Sendable {
        weak var value: KeyboardViewController?
        init(_ v: KeyboardViewController) { value = v }
    }

    // MARK: - Input view (conforms to UIInputViewAudioFeedback so the
    // system click plays even WITHOUT Full Access).

    override func loadView() {
        view = ClinkInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Tell the container app whether we actually have Full Access, so its
        // setup screen can reflect reality.
        store.reportFullAccess(hasFullAccess)
        reloadSettings()
        loadLexicon()
        updateSuggestions()
        updateReturnKey()

        // Reload instantly if the app saves new settings while we're alive.
        let box = WeakBox(self)
        // Held by `changeToken`; releasing it (on deinit) auto-unregisters.
        changeToken = store.observeChanges {
            Task { @MainActor in box.value?.reloadSettings() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Pick up any theme/layout/sound changes the user made in the app
        // while we weren't on screen.
        store.reportFullAccess(hasFullAccess)
        reloadSettings()
        // loadLexicon()  // TEMP: disabled to isolate the launch crash.
        // We may be attaching to a different text field than last time — the mirror
        // can't be trusted across that, so re-seed on the next read.
        invalidateMirror()
        updateSuggestions()
        updateReturnKey()
    }

    /// Pull in the user's supplementary lexicon — Contacts names plus the text
    /// replacements they've set in Settings → General → Keyboard. This is the one
    /// slice of the native suggestion machinery Apple exposes to a third-party
    /// keyboard, so we feed it into the engine's bar + autocorrect.
    private func loadLexicon() {
        // `requestSupplementaryLexicon`'s completion is delivered on a *background*
        // queue (`com.apple.TextInput.lexicon-request`), NOT the main thread. A
        // closure that captured this MainActor controller directly would be
        // inferred MainActor-isolated, so Swift 6 inserts an executor check at its
        // entry — which traps (EXC_BREAKPOINT) the moment it runs off-main. So
        // make the completion a non-isolated `@Sendable` closure, pull out plain
        // data there, and hop to the main actor (via WeakBox, like
        // `observeChanges` below) before touching `self`.
        let box = WeakBox(self)
        requestSupplementaryLexicon { @Sendable lexicon in
            let entries = lexicon.entries.map { ($0.userInput, $0.documentText) }
            Task { @MainActor in
                guard let self = box.value else { return }
                self.engine.setLexicon(entries)
                self.updateSuggestions()
            }
        }
    }

    /// Fired by the system whenever the document text changes (including our
    /// own edits) — keep the suggestion bar in sync.
    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        // A change we didn't make (host cleared the field, autofill, another input
        // view) means our mirror no longer matches the document.
        if !isApplyingEdit { invalidateMirror() }
        scheduleSuggestionUpdate()
        updateReturnKey()
    }

    /// The cursor/selection moved. If it wasn't our own edit, the mirror's tail no
    /// longer sits immediately before the cursor — re-seed on the next read.
    override func selectionWillChange(_ textInput: (any UITextInput)?) {
        super.selectionWillChange(textInput)
        if !isApplyingEdit { invalidateMirror() }
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        if !isApplyingEdit { invalidateMirror() }
    }

    /// Mirror the host field's `returnKeyType` onto the return key — so it reads
    /// "Go", "Search", "Send", "Done", etc., and goes prominent for action types
    /// exactly like the system keyboard. Cheap; safe to call on every change.
    private func updateReturnKey() {
        let type = textDocumentProxy.returnKeyType
        // Symbol (icon) keys: plain return → ⏎, continue → arrow. Everything
        // else is a worded action key.
        var symbol: String?
        let title: String
        switch type {
        case .go:                     title = "Go"
        case .search, .google, .yahoo: title = "Search"
        case .join:                   title = "Join"
        case .next:                   title = "Next"
        case .route:                  title = "Route"
        case .send:                   title = "Send"
        case .done:                   title = "Done"
        case .continue:               title = "Continue"; symbol = "arrow.right"
        case .emergencyCall:          title = "Emergency"
        case .default:                title = "return";   symbol = "return.left"
        @unknown default:             title = "return";   symbol = "return.left"
        }
        // Plain "return" and "Next" stay neutral; the rest are action keys.
        let prominent = !(type == .default || type == .next)
        if live.returnKeyTitle != title { live.returnKeyTitle = title }
        if live.returnKeySymbol != symbol { live.returnKeySymbol = symbol }
        if live.returnKeyProminent != prominent { live.returnKeyProminent = prominent }
    }

    // MARK: - Building / rebuilding the SwiftUI keyboard

    private func reloadSettings() {
        let new = store.load()
        settings = new
        sound.prepare(for: new, hasFullAccess: hasFullAccess)

        let root = AnyView(makeCanvas(for: new))
        if let hosting {
            hosting.rootView = root
        } else {
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            // Pin all four edges so the SwiftUI content FILLS the input view.
            // iOS enforces a minimum keyboard height; rather than fight it with
            // a fixed-size (which then got centered, leaving a gap above the
            // suggestion bar), we let the canvas fill — bar at the top, keys
            // expanding to fill the rest.
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            host.didMove(toParent: self)
            hosting = host

            // A custom keyboard has no intrinsic height — without this constraint
            // the system hands the view an enormous height and the rows collapse.
            // We pin it to our content height; the canvas (pinned to all edges +
            // filling) then lays the rows out within it.
            let h = view.heightAnchor.constraint(equalToConstant: KeyboardCanvas.preferredHeight(for: new))
            h.priority = .required - 1
            h.isActive = true
            heightConstraint = h
        }
        heightConstraint?.constant = KeyboardCanvas.preferredHeight(for: new)

        // When matching the system, let the host's appearance flow through so
        // `KeyboardCanvas` flips its light/dark theme live. With a fixed theme,
        // force the matching chrome so the system bar + corners look right.
        overrideUserInterfaceStyle = new.matchSystemAppearance
            ? .unspecified
            : (new.theme.isDark ? .dark : .light)

        clearKeyboardBackground()
    }

    /// Make the entire keyboard backdrop transparent so it blends with iOS.
    ///
    /// iOS 26 doesn't hand a custom keyboard the whole keyboard region: it wraps
    /// our input view in a system container and reserves a bottom
    /// `UIKeyboardDockView` (the globe / dictation bar) plus a thin top inset.
    /// Those system-owned views sit *around* our `view` and render in iOS's
    /// default light keyboard colour — showing as gray bands above and below the
    /// keys. Rather than fight to paint them a matching colour, we clear the
    /// whole chain so iOS's own keyboard backdrop shows through uniformly and the
    /// keys (which keep their own fills) float on it, exactly like the system
    /// keyboard. The chain lives inside the *extension's own* `UIWindow`, so
    /// clearing it never affects the host app.
    private func clearKeyboardBackground() {
        view.backgroundColor = .clear
        var ancestor = view.superview
        while let v = ancestor {
            v.backgroundColor = .clear
            ancestor = v.superview
        }
    }

    /// The system tray/dock views aren't in our hierarchy until the keyboard is
    /// laid out, so re-apply here (cheap; just sets background colours).
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Stop iOS's required-priority height constraint from inflating the
        // keyboard mid-transition (the "huge then snaps" flash on switch).
        tameSystemHeightConstraint()
        clearKeyboardBackground()
    }

    private func makeCanvas(for settings: KeyboardSettings) -> some View {
        KeyboardCanvas(
            settings: settings,
            live: live,
            onInsert: { [weak self] text in
                guard let self else { return }
                self.isApplyingEdit = true
                defer { self.isApplyingEdit = false; self.scheduleSuggestionUpdate() }
                // Apply the pending correction when a terminator commits the word
                // — "space completes" it. Computed synchronously from the mirror
                // here (not read off the debounced bar), so it fires reliably even
                // when the user spaces within the debounce window.
                if Self.wordTerminators.contains(text) {
                    self.applyPendingAutocorrect()
                }
                // Smart punctuation (curly quotes, em-dash, double-space → ". ")
                // rides the same auto-punctuation switch as contractions. Runs
                // after any pending correction so it sees the committed word.
                if self.settings.autoPunctuationEnabled,
                   let edit = SmartPunctuation.edit(for: text, before: self.contextBeforeCursor()) {
                    self.deleteBackwardMirrored(edit.deleteBackward)
                    self.insertMirrored(edit.insert)
                } else {
                    self.insertMirrored(text)
                }
            },
            onBackspace: { [weak self] in
                guard let self else { return }
                self.isApplyingEdit = true
                self.deleteBackwardMirrored(1)
                self.isApplyingEdit = false
                self.scheduleSuggestionUpdate()
            },
            onAnyTap: { [weak self] in
                guard let self else { return }
                self.sound.play(settings: self.settings, hasFullAccess: self.hasFullAccess)
            },
            // The globe key — only the extension can advance input modes.
            onNextKeyboard: needsInputModeSwitchKey
                ? { [weak self] in self?.advanceToNextInputMode() }
                : nil,
            onSuggestion: { [weak self] word in
                self?.applySuggestion(word)
            },
            onEmojiSuggestion: { [weak self] emoji in
                self?.applyEmojiSuggestion(emoji)
            },
            // Tapped the quoted literal → keep what they typed, drop the fix.
            onCancelAutocorrect: { [weak self] in
                guard let self else { return }
                self.rejectedCorrection = self.live.autocorrection?.from
                self.live.autocorrection = nil
            },
            // Space-bar trackpad: slide the cursor by whole characters. The cursor
            // jumps off our typed tail, so the mirror no longer describes what's
            // before it — drop trust and re-seed on the next read.
            onCursorMove: { [weak self] delta in
                guard let self else { return }
                self.textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
                self.invalidateMirror()
            }
        )
        // Fill the host (which fills the input view) so the bar pins to the top
        // and the keys expand — no centred gap.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Offline autocomplete (UITextChecker — on-device, no network)

    /// The partial word immediately before the cursor (trailing letters, plus
    /// apostrophes so contractions like "don't" stay whole).
    private var currentPartialWord: String {
        SmartPunctuation.trailingPartialWord(in: contextBeforeCursor())
    }

    // MARK: - Local text mirror (avoids per-keystroke proxy reads)

    /// The text just before the cursor, served from the local mirror when it's in
    /// sync and re-seeded from the document proxy otherwise. Only the trailing
    /// `tailCap` characters are guaranteed — enough for trailing-word detection
    /// and smart-punctuation lookbehind, never for whole-document context.
    private func contextBeforeCursor() -> String {
        if bufferValid { return recentTail }
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        recentTail = String(ctx.suffix(tailCap))
        bufferValid = true
        return recentTail
    }

    /// Insert text into the document and keep the mirror in step.
    private func insertMirrored(_ text: String) {
        textDocumentProxy.insertText(text)
        if bufferValid { recentTail = String((recentTail + text).suffix(tailCap)) }
    }

    /// Delete `n` characters backward and keep the mirror in step. If we'd delete
    /// past what the mirror holds, drop trust rather than guess.
    private func deleteBackwardMirrored(_ n: Int) {
        guard n > 0 else { return }
        for _ in 0..<n { textDocumentProxy.deleteBackward() }
        if bufferValid {
            if recentTail.count >= n { recentTail.removeLast(n) }
            else { bufferValid = false }
        }
    }

    /// Mark the mirror stale; the next `contextBeforeCursor()` re-seeds from the
    /// proxy. Cheap, and self-healing — worst case is one extra proxy read.
    private func invalidateMirror() { bufferValid = false }

    /// Debounce. Each keystroke cancels the previous pending compute and
    /// reschedules ~80ms out, so a fast burst collapses to a SINGLE
    /// `UITextChecker` run once typing settles — the keyboard stays smooth
    /// mid-burst instead of running the (slow) checker per key. The short delay
    /// also lets `documentContextBeforeInput` reflect the latest edit (it
    /// updates a runloop tick after insert/delete).
    private func scheduleSuggestionUpdate() {
        suggestionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateSuggestions() }
        suggestionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func updateSuggestions() {
        guard settings.suggestionsEnabled else {
            if !live.suggestions.isEmpty { live.suggestions = [] }
            if live.autocorrection != nil { live.autocorrection = nil }
            if !live.emojiSuggestions.isEmpty { live.emojiSuggestions = [] }
            return
        }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let partial = SmartPunctuation.trailingPartialWord(in: before)

        // Off a word → let corrections fire again for the next word.
        if partial.isEmpty { rejectedCorrection = nil }

        // When there's no partial word, predict the NEXT word so the bar is
        // never blank (sentence starters at a sentence start, otherwise words
        // that commonly follow the previous one) — like the native keyboard.
        let result = engine.compute(
            partial: partial,
            previousWord: previousWord(before: before, partial: partial),
            sentenceStart: isSentenceStart(before: before, partial: partial),
            autocorrect: settings.autocorrectEnabled,
            autoPunctuation: settings.autoPunctuationEnabled,
            rejected: rejectedCorrection)
        live.suggestions = result.predictions
        live.autocorrection = result.correction
        live.emojiSuggestions = result.emoji
    }

    /// The completed word before the cursor (when no partial is being typed),
    /// used to predict the next word. nil at a sentence start.
    private func previousWord(before: String, partial: String) -> String? {
        guard partial.isEmpty else { return nil }
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".!?".contains(last) else { return nil }
        let word = SmartPunctuation.trailingPartialWord(in: trimmed)
        return word.isEmpty ? nil : word
    }

    /// True when the cursor sits at the start of a new sentence (empty context
    /// or right after `.`/`!`/`?`) — so we suggest capitalised sentence openers.
    private func isSentenceStart(before: String, partial: String) -> Bool {
        guard partial.isEmpty else { return false }
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if let last = trimmed.last, ".!?".contains(last) { return true }
        return false
    }

    /// Characters that end a word — typing one applies the pending correction.
    private static let wordTerminators: Set<String> = [" ", "\n", ".", ",", "!", "?", ";", ":"]

    /// Commit a correction for the just-finished word when a terminator ends it.
    ///
    /// This is computed *synchronously here*, from the just-typed word, rather than
    /// read off `live.autocorrection`. The bar's value is produced on an 80ms
    /// debounce that resets on every keystroke — so a fast typist who hits space
    /// within that window would find it stale or nil and lose the fix entirely.
    /// Computing on the spot (one `UITextChecker` run per *word*, during the
    /// natural micro-pause of pressing space) makes the correction fire reliably
    /// no matter how fast the word was typed.
    ///
    /// Must be called inside an `isApplyingEdit` window, before the terminator is
    /// inserted, so `contextBeforeCursor()` still ends at the finished word.
    private func applyPendingAutocorrect() {
        guard settings.autocorrectEnabled || settings.autoPunctuationEnabled else { return }
        let word = currentPartialWord
        guard !word.isEmpty else { return }
        // Lean correction-only path: no predictions, no emoji scan, no pool
        // building — just the fix, computed (or cache-hit) cheaply, because this
        // runs synchronously on the space keypress while the user is mid-burst.
        let correction = engine.correction(
            for: word,
            autocorrect: settings.autocorrectEnabled,
            autoPunctuation: settings.autoPunctuationEnabled,
            rejected: rejectedCorrection)
        guard let c = correction, c.from == word else { return }
        deleteBackwardMirrored(word.count)
        insertMirrored(c.to)
        live.autocorrection = nil
    }

    /// Replace the current partial word with the chosen suggestion + a space.
    private func applySuggestion(_ word: String) {
        isApplyingEdit = true
        let partial = currentPartialWord
        deleteBackwardMirrored(partial.count)
        insertMirrored(word + " ")
        isApplyingEdit = false
        live.autocorrection = nil
        sound.play(settings: settings, hasFullAccess: hasFullAccess)
        scheduleSuggestionUpdate()
    }

    /// Swap the word being typed for the tapped emoji — no trailing space (so you
    /// can keep going), and no autocorrect side effects. Mirrors iOS QuickType's
    /// emoji-replaces-word behaviour.
    private func applyEmojiSuggestion(_ emoji: String) {
        isApplyingEdit = true
        let partial = currentPartialWord
        deleteBackwardMirrored(partial.count)
        insertMirrored(emoji)
        isApplyingEdit = false
        live.autocorrection = nil
        sound.play(settings: settings, hasFullAccess: hasFullAccess)
        scheduleSuggestionUpdate()
    }
}


/// Conforming the input view to `UIInputViewAudioFeedback` is what lets
/// `UIDevice.playInputClick()` actually click without Full Access.
private final class ClinkInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
