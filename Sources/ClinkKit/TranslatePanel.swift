/**
 `TranslatePanel`: full-keyboard overlay that runs and shows a translation.

 Two backends, chosen by `useAI`:
   • Offline (default) — Apple's `Translation` framework (iOS 18+), fully on
     device, no Apple Intelligence required. Driven by a `.translationTask`
     inside the iOS-18-gated `OfflineTranslateRunner`.
   • AI — `AIEngine` (FoundationModels, iOS 26+), used only when the AI assist
     and the "Use AI for translation" option are both on and the model is
     available; higher quality on capable hardware.

 The panel never blocks: translation runs async and the strip/keys stay
 responsive. On failure or an unsupported OS it shows a clear message rather
 than hanging.


 Module: panels · Target: ClinkKit
 Learn: docs/13-extending-panels.md
 */
import SwiftUI
import UIKit
#if canImport(Translation)
// @preconcurrency: the Translation framework isn't fully Swift-6 concurrency
// annotated — `TranslationSession` is a non-Sendable class with a `nonisolated`
// `translate`, so calling it from the MainActor `.translationTask` closure trips
// a "sending main-actor-isolated value" error. This downgrades that to the
// framework's pre-concurrency contract (the session is only ever used on the
// main actor here anyway).
@preconcurrency import Translation
#endif

/// Full-keyboard overlay showing the source text, the target language, the
/// translation (or a spinner / error), and insert / copy actions.
struct TranslatePanel: View {
    let source: String
    let language: TranslateLanguage
    /// Route through `AIEngine` instead of the offline framework.
    let useAI: Bool
    let theme: Theme
    let cornerRadius: CGFloat
    let onInsert: (String) -> Void
    let onCopy: (String) -> Void
    let onDismiss: () -> Void
    /// Top-left "back" action — returns to the compose strip.
    let onBack: () -> Void

    @State private var phase: TranslatePhase = .translating

    private var result: String? {
        if case let .done(text) = phase { return text }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    sourceCard
                    resultCard
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            actionRow
        }
        // AI path: re-runs whenever the input changes. No-op when offline.
        .task(id: TaskKey(source: source, lang: language.id, ai: useAI)) {
            guard useAI else { return }
            await runAI()
        }
        // Offline path: an invisible iOS-18 runner drives `.translationTask`.
        .background { offlineRunner }
    }

    // MARK: - Backends

    private func runAI() async {
        phase = .translating
        do {
            let text = try await AIEngine.shared.translate(source, to: language.name)
            phase = .done(text)
        } catch {
            phase = .failed("AI translation is unavailable right now.")
        }
    }

    @ViewBuilder private var offlineRunner: some View {
        if !useAI {
            #if canImport(Translation)
            if #available(iOS 18.0, *) {
                OfflineTranslateRunner(source: source, target: language.id) { phase = $0 }
            } else {
                unsupportedHook
            }
            #else
            unsupportedHook
            #endif
        }
    }

    /// Sets the unsupported message once when neither backend can run.
    private var unsupportedHook: some View {
        Color.clear.onAppear {
            phase = .failed("Offline translation needs iOS 18. Turn on AI in Artificial Intelligence to translate on this device.")
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 0) {
            PanelLeadingIcon("character.bubble", theme: theme, onBack: onBack)
            divider
            Text("Translate · \(language.name)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.keyText.color.opacity(0.7))
                .frame(maxWidth: .infinity)
            divider
            headerButton("xmark", action: onDismiss)
        }
        .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)
    }

    private var sourceCard: some View {
        card {
            Text(source.isEmpty ? "Nothing to translate" : source)
                .font(.system(size: 15))
                .foregroundStyle(theme.keyText.color.opacity(source.isEmpty ? 0.35 : 0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var resultCard: some View {
        card {
            switch phase {
            case .translating:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Translating…")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.keyText.color.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case let .done(text):
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.keyText.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            case let .failed(message):
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.keyText.color.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionButton("text.insert", "Insert") { if let r = result { onInsert(r) } }
            divider
            actionButton("doc.on.doc", "Copy") { if let r = result { onCopy(r) } }
        }
        .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)
        .disabled(result == nil)
        .opacity(result == nil ? 0.4 : 1)
    }

    // MARK: - Building blocks

    @ViewBuilder private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                switch theme.material {
                case .liquidGlass:
                    if #available(iOS 26.0, *) {
                        Color.clear.glassEffect(.regular.tint(theme.keyFill.color.opacity(theme.glassTintStrength)), in: shape)
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }
                case .solid:
                    shape.fill(theme.keyFill.color)
                }
            }
    }

    private func actionButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                Text(label).font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(theme.accent.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 52, height: KeyboardCanvas.Metrics.suggestionBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }

    /// Identity for the AI `.task` so it re-runs on any input change.
    private struct TaskKey: Equatable { let source: String; let lang: String; let ai: Bool }
}

/// Panel-style Translate: a full-keyboard takeover (like the trackpad/calculator)
/// with the source text, target language, translate action, and result all in one
/// reachable surface. The keys are hidden, so input is via Paste (plus anything
/// already in the shared compose buffer). Shares the same AI / offline backends as
/// the inline `TranslatePanel`.
struct TranslateFullPanel: View {
    @Bindable var manager: TranslateManager
    let languages: [TranslateLanguage]
    let useAI: Bool
    /// Whether the Paste button is offered (needs Full Access for the pasteboard).
    let canPaste: Bool
    let theme: Theme
    let cornerRadius: CGFloat
    let onInsert: (String) -> Void
    let onCopy: (String) -> Void
    let onDismiss: () -> Void
    /// Tapping the source asks the host to bring the keys back so the user can
    /// type into the compose buffer (the panel can't host its own text field).
    let onEditSource: () -> Void
    /// Run the translation as soon as the panel appears (set when the user hit
    /// Translate from the compose strip).
    let autoTranslate: Bool
    let onConsumeAutoTranslate: () -> Void

    /// The source actually submitted for translation ("" = not run yet).
    @State private var submitted = ""
    @State private var phase: TranslatePhase = .translating

    private var result: String? {
        if case let .done(text) = phase { return text }
        return nil
    }
    private var language: TranslateLanguage { manager.targetLanguage }
    private var canTranslate: Bool {
        !manager.compose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        // No outer scroll — everything fits the keyboard height. The source and
        // result cards are the flexible regions (they split the leftover space and
        // scroll internally only when their text is long); the header, language
        // row, and Translate button are fixed.
        VStack(spacing: 6) {
            header
            languageRow.padding(.horizontal, 8)
            sourceCard.padding(.horizontal, 8)
            if !submitted.isEmpty { resultCard.padding(.horizontal, 8) }
            translateButton.padding(.horizontal, 8).padding(.bottom, 8)
        }
        // AI path re-runs when the submitted text or target language changes.
        .task(id: TaskKey(source: submitted, lang: language.id, ai: useAI)) {
            guard useAI, !submitted.isEmpty else { return }
            await runAI()
        }
        .background { offlineRunner }
        // Returning from the compose strip with Translate tapped: run it now.
        .onAppear {
            if autoTranslate {
                onConsumeAutoTranslate()
                runTranslate()
            }
        }
    }

    // MARK: - Trigger & backends

    private func runTranslate() {
        let trimmed = manager.compose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .translating
        submitted = trimmed
    }

    private func runAI() async {
        phase = .translating
        do {
            let text = try await AIEngine.shared.translate(submitted, to: language.name)
            phase = .done(text)
        } catch {
            phase = .failed("AI translation is unavailable right now.")
        }
    }

    @ViewBuilder private var offlineRunner: some View {
        if !useAI, !submitted.isEmpty {
            #if canImport(Translation)
            if #available(iOS 18.0, *) {
                OfflineTranslateRunner(source: submitted, target: language.id) { phase = $0 }
            } else {
                unsupportedHook
            }
            #else
            unsupportedHook
            #endif
        }
    }

    private var unsupportedHook: some View {
        Color.clear.onAppear {
            phase = .failed("Offline translation needs iOS 18. Turn on AI in Artificial Intelligence to translate on this device.")
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 0) {
            PanelLeadingIcon("character.bubble", theme: theme, onBack: nil)
            divider
            Text("Translate")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.keyText.color.opacity(0.7))
                .frame(maxWidth: .infinity)
            divider
            headerButton("xmark", action: onDismiss)
        }
        .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)
    }

    private var languageRow: some View {
        HStack(spacing: 8) {
            languagePill("Auto", menu: false) {}
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.keyText.color.opacity(0.4))
            languageMenu
            Spacer()
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(languages) { lang in
                Button { manager.targetLanguageID = lang.id } label: {
                    if lang.id == language.id { Label(lang.name, systemImage: "checkmark") }
                    else { Text(lang.name) }
                }
            }
        } label: {
            languagePill(language.name, menu: true) {}
        }
    }

    private func languagePill(_ text: String, menu: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 14, weight: .medium))
            if menu {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(theme.keyText.color.opacity(menu ? 0.85 : 0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.keyFill.color.opacity(menu ? theme.glassTintStrength + 0.1 : 0.0),
                    in: Capsule())
        .overlay(menu ? AnyView(Capsule().strokeBorder(theme.keyText.color.opacity(0.12), lineWidth: 0.5)) : AnyView(EmptyView()))
    }

    private var sourceCard: some View {
        flexCard {
            VStack(alignment: .leading, spacing: 6) {
                // Tapping the text brings the keys back to type (see `onEditSource`).
                ScrollView(.vertical, showsIndicators: false) {
                    Text(manager.compose.isEmpty ? "Tap to type, or paste" : manager.compose)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.keyText.color.opacity(manager.compose.isEmpty ? 0.35 : 0.85))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .contentShape(Rectangle())
                .onTapGesture { onEditSource() }
                HStack(spacing: 12) {
                    smallButton("keyboard", "Type") { onEditSource() }
                    if canPaste {
                        smallButton("doc.on.clipboard", "Paste") {
                            if let s = UIPasteboard.general.string { manager.compose = s }
                        }
                    }
                    Spacer()
                    if !manager.compose.isEmpty {
                        smallButton("xmark.circle", "Clear") {
                            manager.compose = ""; submitted = ""
                        }
                    }
                }
            }
        }
    }

    private var translateButton: some View {
        Button(action: runTranslate) {
            HStack(spacing: 6) {
                Image(systemName: "character.bubble.fill").font(.system(size: 15, weight: .semibold))
                Text("Translate").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(theme.accent.color.opacity(canTranslate ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canTranslate)
    }

    @ViewBuilder private var resultCard: some View {
        flexCard {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.vertical, showsIndicators: false) {
                    switch phase {
                    case .translating:
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Translating…")
                                .font(.system(size: 15))
                                .foregroundStyle(theme.keyText.color.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    case let .done(text):
                        Text(text)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(theme.keyText.color)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                    case let .failed(message):
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.keyText.color.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                if result != nil {
                    HStack(spacing: 8) {
                        smallButton("text.insert", "Insert") { if let r = result { onInsert(r) } }
                        Spacer()
                        smallButton("doc.on.doc", "Copy") { if let r = result { onCopy(r) } }
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    /// A flexible card that fills the slack height the body gives it (so source
    /// and result split the space) and top-aligns its content.
    @ViewBuilder private func flexCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                switch theme.material {
                case .liquidGlass:
                    if #available(iOS 26.0, *) {
                        Color.clear.glassEffect(.regular.tint(theme.keyFill.color.opacity(theme.glassTintStrength)), in: shape)
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }
                case .solid:
                    shape.fill(theme.keyFill.color)
                }
            }
    }

    private func smallButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                Text(label).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(theme.accent.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 52, height: KeyboardCanvas.Metrics.suggestionBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }

    private struct TaskKey: Equatable { let source: String; let lang: String; let ai: Bool }
}

#if canImport(Translation)
/// Invisible driver for the offline `Translation` framework. Owns the
/// `.translationTask`; reports the outcome back through `onResult`. Isolated in
/// its own `@available(iOS 18)` view so no iOS-18 type leaks into `TranslatePanel`
/// (which must compile against the lower deployment floor).
@available(iOS 18.0, *)
private struct OfflineTranslateRunner: View {
    let source: String
    let target: String
    let onResult: (TranslatePhase) -> Void

    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .translationTask(config) { session in
                do {
                    let response = try await session.translate(source)
                    onResult(.done(response.targetText))
                } catch {
                    onResult(.failed("Couldn't translate. The \(target) language pack may need downloading in Settings."))
                }
            }
            .onChange(of: identity, initial: true) {
                // Source nil ⇒ the framework auto-detects the input language.
                onResult(.translating)
                config = .init(target: Locale.Language(identifier: target))
            }
    }

    /// Re-trigger when the text or target changes.
    private var identity: String { "\(target)\u{1}\(source)" }
}
#endif
