/**
 Translate settings — enable the Translate panel, pick the default target
 language, and (when Apple Intelligence is on and available) choose the
 translation engine: offline language packs vs Apple Intelligence. The engine
 choice is the `aiTranslate` setting, also surfaced on the Artificial
 Intelligence page; both bind the same value.


 Module: app-ui · Target: Clink
 Learn: docs/13-extending-panels.md
 */
import SwiftUI
import iUXiOS
#if canImport(Translation)
// @preconcurrency: the Translation framework isn't fully Swift-6 annotated — see
// the note in `TranslatePanel`. We use `LanguageAvailability` / `prepareTranslation`
// here only from the main actor.
@preconcurrency import Translation
#endif

/// Translate panel toggle + default target language.
/// `translateEnabled` persists via `AppModel.settings` `didSet`; the target
/// language lives in `TranslateManager` (App Group file), shared with the
/// keyboard extension.
struct TranslateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Whether Apple Intelligence is actually usable — the engine choice only
    /// appears when AI is both available and switched on (otherwise translation
    /// always uses the offline language packs, so there's nothing to choose).
    @State private var aiAvailable = false

    /// True when the user can pick between engines.
    private var canChooseEngine: Bool { aiAvailable && model.settings.aiEnabled }

    var body: some View {
        @Bindable var model = model
        @Bindable var translate = model.translate
        ScrollView {
            VStack(alignment: .leading, spacing: UX.cardSpacing) {
                CardSection("Translate") {
                    ToggleRow("Translate panel",
                              subtitle: "Translate typed or pasted text into another language, right inside the keyboard. Adds a translate panel to the panel button.",
                              isOn: $model.settings.translateEnabled)
                }

                if model.settings.translateEnabled {
                    CardSection("Style") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Style", selection: $model.settings.translateStyle) {
                                Text("Inline").tag(TranslateStyle.inline)
                                Text("Panel").tag(TranslateStyle.panel)
                            }
                            .pickerStyle(.segmented)
                            Text(model.settings.translateStyle == .panel
                                 ? "Panel replaces the keyboard with a full translator — paste text, pick a language, read and insert the result. Big and easy to reach."
                                 : "Inline composes on the suggestion bar while the keys stay up — type to translate, then the result drops in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, UX.rowVPadding)
                    }
                }

                if model.settings.translateEnabled && canChooseEngine {
                    CardSection("Engine") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Engine", selection: $model.settings.aiTranslate) {
                                Text("Language pack").tag(false)
                                Text("Apple Intelligence").tag(true)
                            }
                            .pickerStyle(.segmented)
                            Text(model.settings.aiTranslate
                                 ? "Apple Intelligence translates for higher-quality, more idiomatic results. On-device; nothing uploaded."
                                 : "Apple's on-device language packs translate offline. Fast and wide device support; a pack may download on first use.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, UX.rowVPadding)
                    }
                }

                if model.settings.translateEnabled {
                    CardSection("Default language") {
                        HStack {
                            Text("Translate into")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("Translate into", selection: $translate.targetLanguageID) {
                                ForEach(TranslateLanguage.common) { lang in
                                    Text(lang.name).tag(lang.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, UX.rowVPadding)
                    }
                }

                if model.settings.translateEnabled {
                    if #available(iOS 18.0, *) {
                        CardSection("Language packs") {
                            LanguagePackList(languages: TranslateLanguage.common)
                        }
                    }
                }

                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("Translate")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
        .onAppear { aiAvailable = AIAvailability.current() == .available }
        // Re-probe after returning from Settings (AI may have been turned on) or
        // once a pending model download finishes.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { aiAvailable = AIAvailability.current() == .available }
        }
    }

    private var footer: String {
        if canChooseEngine {
            return "Translation runs entirely on this device — nothing is uploaded either way. Pick the engine above; language packs may download on first use."
        }
        return "Translation works offline using Apple's on-device language packs (no account, nothing uploaded). The first time you use a language it may download a pack. To choose Apple Intelligence as the engine on supported devices, turn on AI under Artificial Intelligence."
    }
}

#if canImport(Translation)
/// In-app language-pack manager. Lists the common languages with their on-device
/// install status and lets the user download a pack right here — so offline
/// translation is ready before they ever open the keyboard (where the only other
/// trigger is the system download prompt). iOS 18+, app target (downloads belong
/// in the host app, not the extension).
@available(iOS 18.0, *)
private struct LanguagePackList: View {
    let languages: [TranslateLanguage]

    @State private var statuses: [String: LanguageAvailability.Status] = [:]
    @State private var preparing: String? = nil
    @State private var config: TranslationSession.Configuration? = nil
    @State private var loaded = false

    /// Packs cover translating between a language and the device language.
    private let deviceLanguage = Locale.current.language

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(languages.enumerated()), id: \.element.id) { idx, lang in
                if idx > 0 { Divider() }
                row(lang)
            }
        }
        .task { await refresh() }
        // Setting `config` runs this once: the system prepares (downloads) the
        // pack for that pair, then we re-query so the row flips to "Installed".
        .translationTask(config) { session in
            try? await session.prepareTranslation()
            preparing = nil
            config = nil
            await refresh()
        }
    }

    @ViewBuilder private func row(_ lang: TranslateLanguage) -> some View {
        HStack {
            Text(lang.name)
            Spacer()
            trailing(lang)
        }
        .padding(.vertical, UX.rowVPadding)
    }

    @ViewBuilder private func trailing(_ lang: TranslateLanguage) -> some View {
        if preparing == lang.id {
            ProgressView()
        } else if isDeviceLanguage(lang) {
            Text("Default").font(.subheadline).foregroundStyle(.secondary)
        } else {
            switch statuses[lang.id] {
            case .installed:
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            case .supported:
                Button("Download") { startDownload(lang) }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderless)
            case .unsupported:
                Text("Unavailable").font(.subheadline).foregroundStyle(.tertiary)
            case .none:
                if loaded {
                    Text("—").foregroundStyle(.tertiary)
                } else {
                    ProgressView()
                }
            @unknown default:
                // Future Translation status the SDK adds — treat as a downloadable.
                Button("Download") { startDownload(lang) }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderless)
            }
        }
    }

    private func isDeviceLanguage(_ lang: TranslateLanguage) -> Bool {
        deviceLanguage.languageCode?.identifier
            == Locale.Language(identifier: lang.id).languageCode?.identifier
    }

    private func startDownload(_ lang: TranslateLanguage) {
        preparing = lang.id
        config = .init(source: deviceLanguage, target: Locale.Language(identifier: lang.id))
    }

    /// Re-query the install status of every listed language.
    private func refresh() async {
        let availability = LanguageAvailability()
        var result: [String: LanguageAvailability.Status] = [:]
        for lang in languages {
            result[lang.id] = await availability.status(
                from: deviceLanguage,
                to: Locale.Language(identifier: lang.id))
        }
        statuses = result
        loaded = true
    }
}
#endif

#if DEBUG
#Preview { TranslateView().clinkPreview() }
#endif
