import SwiftUI
import UIKit

/// The Clink *emoji* keyboard extension. A second keyboard that renders the
/// shared `EmojiCanvas` (in ClinkKit) from the SAME `KeyboardSettings` as the
/// letter keyboard — so the user configures once and both keyboards match. iOS's
/// globe key switches between them (and any other enabled keyboards).
///
/// `@objc(EmojiKeyboardViewController)` makes the bare name in Info.plist's
/// `NSExtensionPrincipalClass` resolve without a module prefix.
@objc(EmojiKeyboardViewController)
final class EmojiKeyboardViewController: UIInputViewController {

    private let store = SharedStore.shared
    private let sound = SoundPlayer()
    private var settings = KeyboardSettings.default
    private var hosting: UIHostingController<AnyView>?
    private var heightConstraint: NSLayoutConstraint?
    /// Fixed height of the SwiftUI content, anchored to the *bottom* of our view.
    /// The system animates our view's frame from full-screen down to `target` on
    /// every appearance/switch; pinning the content to all edges made it track
    /// that animation (the visible jump). Anchoring it bottom-aligned at a fixed
    /// height keeps the content in its final position from the first frame — only
    /// the transparent overhang above collapses, which is invisible.
    private var hostContentHeight: NSLayoutConstraint?
    private var changeToken: AnyObject?
    /// True from creation until the appearance frame first settles to `target` —
    /// see the letter keyboard for the full rationale. The system animates our
    /// view down from ~full-screen on every appearance and no sizing API stops it,
    /// so we hide the content for the descent and reveal it on settle. A fresh VC
    /// per appearance re-arms the `true` default; once cleared it stays clear, so
    /// the intentional emoji-search resize is never masked.
    private var isSettling = true

    /// Sendable weak handle so the @Sendable Darwin-notification closure can hop
    /// back to this (non-Sendable, MainActor) controller.
    private final class WeakBox: @unchecked Sendable {
        weak var value: EmojiKeyboardViewController?
        init(_ v: EmojiKeyboardViewController) { value = v }
    }

    override func loadView() {
        let v = ClinkEmojiInputView(frame: .zero, inputViewStyle: .keyboard)
        // Seed the intrinsic height before the system's first measurement (see the
        // letter keyboard for the full rationale): otherwise targetHeight is 0 on
        // frame one, the system reads the full-screen default and animates down to
        // our target — the visible jump.
        v.targetHeight = EmojiCanvas.preferredHeight(for: store.load())
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.reportFullAccess(hasFullAccess)
        reloadSettings()
        // Hide content until the appearance frame settles (see `isSettling`); a
        // layout pass can fire before viewWillAppear, so arm the mask here.
        hosting?.view.isHidden = true

        // Reload instantly if the app saves new settings while we're alive.
        let box = WeakBox(self)
        changeToken = store.observeChanges {
            Task { @MainActor in box.value?.reloadSettings() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-arm the appearance mask in case this VC is reused across appearances.
        isSettling = true
        hosting?.view.isHidden = true
        store.reportFullAccess(hasFullAccess)
        reloadSettings()
        // On a keyboard *switch* iOS creates us fresh and animates us in at its
        // own inflated default height (target + ~228pt) before re-measuring to our
        // real height. Because the keyboard is bottom-docked, "too tall" pushes our
        // (transparent) top edge up over the host app — which then shows through for
        // the length of that animation. Tame the constraint now and force a layout
        // so the appearance animation starts from our real height, not the balloon.
        tameSystemHeightConstraint()
        view.layoutIfNeeded()
        logHeightState("viewWillAppear")
    }

    /// `viewWillAppear` is often too early on a keyboard *switch*: iOS hasn't yet
    /// installed its `UIView-Encapsulated-Layout-Height` balloon, so taming it
    /// there finds nothing. `viewIsAppearing` fires once the view is in the
    /// hierarchy with settled geometry and that constraint present — but still
    /// before the frame paints. Tame + relayout here so the appearance animation
    /// starts from our real height even on the first switch-in.
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        tameSystemHeightConstraint()
        view.layoutIfNeeded()
        logHeightState("viewIsAppearing")
    }

    /// Hide our content the instant we start leaving (see the letter keyboard):
    /// the outgoing keyboard lingers while the incoming one animates in, so blank
    /// it immediately to avoid stale content stacking under the arriving keyboard.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hosting?.view.isHidden = true
    }

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
            // Bottom-anchored at a fixed height, NOT all four edges — see the
            // letter keyboard for the full rationale: the system animates our view
            // frame from full-screen down to `target` on every appearance, and an
            // all-edges pin made the content track that animation (the visible
            // jump). Bottom-anchored, the content sits in its final place from
            // frame one and only the transparent overhang above it collapses.
            let hostHeight = host.view.heightAnchor.constraint(
                equalToConstant: EmojiCanvas.preferredHeight(for: new))
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hostHeight,
            ])
            hostContentHeight = hostHeight
            host.didMove(toParent: self)
            hosting = host

            let h = view.heightAnchor.constraint(equalToConstant: EmojiCanvas.preferredHeight(for: new))
            h.priority = .required - 1
            h.isActive = true
            heightConstraint = h
        }
        let target = EmojiCanvas.preferredHeight(for: new)
        heightConstraint?.constant = target
        hostContentHeight?.constant = target
        (view as? ClinkEmojiInputView)?.targetHeight = target

        overrideUserInterfaceStyle = new.matchSystemAppearance
            ? .unspecified
            : (new.theme.isDark ? .dark : .light)

        clearKeyboardBackground()
    }

    /// Make the entire keyboard backdrop transparent so it blends with iOS —
    /// same approach as the letter keyboard.
    private func clearKeyboardBackground() {
        view.backgroundColor = .clear
        var ancestor = view.superview
        while let v = ancestor {
            v.backgroundColor = .clear
            ancestor = v.superview
        }
    }

    // Tame the inflated height constraint at every hook that fires before a frame
    // can paint — iOS adds it mid-layout on a fresh keyboard, so the more places we
    // catch it, the fewer (ideally zero) inflated frames reach the screen.
    override func updateViewConstraints() {
        tameSystemHeightConstraint()
        super.updateViewConstraints()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        tameSystemHeightConstraint()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tameSystemHeightConstraint()
        clearKeyboardBackground()
        revealContentWhenSettled()
        logHeightState("viewDidLayoutSubviews")
    }

    /// While the appearance frame is descending from full-screen, keep the content
    /// hidden; reveal it the moment the frame reaches `target`. See `isSettling`.
    private func revealContentWhenSettled() {
        guard isSettling else { return }
        let target = (view as? ClinkEmojiInputView)?.targetHeight ?? 0
        if target > 0, view.bounds.height <= target + 12 {
            isSettling = false
            hosting?.view.isHidden = false
        } else {
            hosting?.view.isHidden = true
        }
    }

    private func makeCanvas(for settings: KeyboardSettings) -> some View {
        EmojiCanvas(
            settings: settings,
            onInsert: { [weak self] emoji in
                self?.textDocumentProxy.insertText(emoji)
            },
            onBackspace: { [weak self] in self?.deleteEmoji() },
            onAnyTap: { [weak self] in
                guard let self else { return }
                self.sound.play(settings: self.settings, hasFullAccess: self.hasFullAccess)
            },
            onNextKeyboard: needsInputModeSwitchKey
                ? { [weak self] in self?.advanceToNextInputMode() }
                : nil,
            // Search mode shows a QWERTY and needs more room — grow the keyboard
            // to whatever height the canvas asks for, animating the resize.
            onRequestHeight: { [weak self] height in self?.setKeyboardHeight(height) },
            // Persist a long-press skin-tone choice into the shared settings so
            // it sticks across sessions and applies on the next plain tap.
            onSetSkinTone: { [weak self] base, tone in self?.saveSkinTone(tone, for: base) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Write a per-emoji skin-tone choice to the shared store. We re-load first
    /// so a concurrent app-side edit isn't clobbered, then save the whole value
    /// (the same JSON the rest of the keyboard reads). `settings` is refreshed so
    /// later taps resolve the new tone even before the change notification lands.
    private func saveSkinTone(_ tone: SkinTone, for base: String) {
        var current = store.load()
        current.setSkinTone(tone, for: base)
        store.save(current)
        settings = current
    }

    /// Animate the keyboard to a new height (e.g. entering/leaving emoji search).
    private func setKeyboardHeight(_ height: CGFloat) {
        guard let heightConstraint, heightConstraint.constant != height else { return }
        heightConstraint.constant = height
        hostContentHeight?.constant = height
        (view as? ClinkEmojiInputView)?.targetHeight = height
        UIView.animate(withDuration: 0.28) { self.view.layoutIfNeeded() }
    }

    /// Delete a whole emoji. `deleteBackward()` already removes one grapheme cluster
    /// at a time — the same primitive the system keyboard's delete key uses, so it
    /// handles multi-scalar emoji (ZWJ sequences, flags, skin tones) correctly. A
    /// single call is exactly one emoji; looping over the UTF-16 unit count deleted
    /// one emoji *per code unit*, so astral-plane glyphs (👍 is a surrogate pair)
    /// vanished two at a time.
    private func deleteEmoji() {
        textDocumentProxy.deleteBackward()
    }
}

/// Conforming the input view to `UIInputViewAudioFeedback` lets
/// `UIDevice.playInputClick()` click without Full Access.
private final class ClinkEmojiInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }

    /// The keyboard's real height, fed by the controller. Exposed as the view's
    /// intrinsic content size so iOS's `systemLayoutSizeFitting` measures *this*
    /// when it presents us — rather than its own inflated default (target + ~228pt)
    /// that becomes the `UIView-Encapsulated-Layout-Height` balloon. Killing the
    /// balloon at the measurement source is more decisive than taming the
    /// constraint after it's already been installed.
    var targetHeight: CGFloat = 0 {
        didSet { if targetHeight != oldValue { invalidateIntrinsicContentSize() } }
    }

    override var intrinsicContentSize: CGSize {
        targetHeight > 0
            ? CGSize(width: UIView.noIntrinsicMetric, height: targetHeight)
            : super.intrinsicContentSize
    }

    /// Earliest layout hook — defuse the balloon before this pass commits, ahead of
    /// the controller's own `viewWillLayoutSubviews`.
    override func layoutSubviews() {
        tameEncapsulatedHeightConstraint()
        super.layoutSubviews()
    }
}
