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

#if DEBUG
#Preview { TranslateView().clinkPreview() }
#endif
