import SwiftUI
import UIKit

/// The Clonk *emoji* keyboard extension. A second keyboard that renders the
/// shared `EmojiCanvas` (in ClonkKit) from the SAME `KeyboardSettings` as the
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
    private var changeToken: AnyObject?

    /// Sendable weak handle so the @Sendable Darwin-notification closure can hop
    /// back to this (non-Sendable, MainActor) controller.
    private final class WeakBox: @unchecked Sendable {
        weak var value: EmojiKeyboardViewController?
        init(_ v: EmojiKeyboardViewController) { value = v }
    }

    override func loadView() {
        view = ClonkEmojiInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.reportFullAccess(hasFullAccess)
        reloadSettings()

        // Reload instantly if the app saves new settings while we're alive.
        let box = WeakBox(self)
        changeToken = store.observeChanges {
            Task { @MainActor in box.value?.reloadSettings() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.reportFullAccess(hasFullAccess)
        reloadSettings()
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
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            host.didMove(toParent: self)
            hosting = host

            let h = view.heightAnchor.constraint(equalToConstant: EmojiCanvas.preferredHeight(for: new))
            h.priority = .required - 1
            h.isActive = true
            heightConstraint = h
        }
        heightConstraint?.constant = EmojiCanvas.preferredHeight(for: new)

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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Stop iOS's required-priority height constraint from inflating the
        // keyboard mid-transition (the "huge then snaps" flash on switch).
        tameSystemHeightConstraint()
        clearKeyboardBackground()
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
            onRequestHeight: { [weak self] height in self?.setKeyboardHeight(height) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Animate the keyboard to a new height (e.g. entering/leaving emoji search).
    private func setKeyboardHeight(_ height: CGFloat) {
        guard let heightConstraint, heightConstraint.constant != height else { return }
        heightConstraint.constant = height
        UIView.animate(withDuration: 0.28) { self.view.layoutIfNeeded() }
    }

    /// Delete a whole emoji — one grapheme cluster can be several UTF-16 units
    /// (ZWJ sequences, flags), so a single `deleteBackward` would leave shards.
    private func deleteEmoji() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        guard let last = before.last else { textDocumentProxy.deleteBackward(); return }
        for _ in 0..<String(last).utf16.count { textDocumentProxy.deleteBackward() }
    }
}

/// Conforming the input view to `UIInputViewAudioFeedback` lets
/// `UIDevice.playInputClick()` click without Full Access.
private final class ClonkEmojiInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
