import SwiftUI
import iUXiOS

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    if !model.isKeyboardEnabled {
                        enableBanner
                    }

                    KeyboardPreview(settings: model.settings)
                        .padding(.top, 4)

                    CardSection("Customize") {
                        NavRow("Theme", subtitle: "Colors, glass, and custom themes",
                               systemImage: "paintpalette",
                               value: model.settings.matchSystemAppearance ? "Auto" : model.settings.theme.name) {
                            ThemeEditorView()
                        }
                        Divider()
                        NavRow("Layout & Keys", subtitle: "Size, spacing, popups, and feel",
                               systemImage: "keyboard", value: model.settings.layout.name) {
                            LayoutPickerView()
                        }
                        Divider()
                        NavRow("Typing", subtitle: "Autocorrect, suggestions, punctuation",
                               systemImage: "text.cursor", value: typingSummary) {
                            TypingView()
                        }
                        Divider()
                        NavRow("Clipboard", subtitle: "History, re-paste, and management",
                               systemImage: "clipboard",
                               value: model.settings.clipboardEnabled
                                   ? (model.clipboard.history.isEmpty ? "On" : "\(model.clipboard.history.count) saved")
                                   : "Off") {
                            ClipboardHistoryView()
                        }
                        Divider()
                        NavRow("Emoji", subtitle: "Default skin tone for emoji",
                               systemImage: "face.smiling", value: model.settings.defaultSkinTone.label) {
                            EmojiSettingsView()
                        }
                        Divider()
                        NavRow("Sound & Feel", subtitle: "Sounds, volume, and haptics",
                               systemImage: "speaker.wave.2",
                               value: model.settings.soundEnabled ? model.settings.soundPack.name : "Off") {
                            SoundPickerView()
                        }
                        Divider()
                        NavRow("Advanced", subtitle: "Hitbox, cursor scroll, and precision tuning",
                               systemImage: "slider.horizontal.3") {
                            AdvancedSettingsView()
                        }
                    }

                    CardSection("Keyboard") {
                        NavRow("Setup & Full Access", systemImage: "gearshape") {
                            EnableFlowView()
                        }
                    }
                }
                .padding(UX.screenPadding)
            }
            .navigationTitle("Clink")
            .background(Color(.systemGroupedBackground))
        }
    }

    /// Short at-a-glance state for the Typing row: "On" when the keyboard is
    /// actively predicting or correcting, otherwise "Off".
    private var typingSummary: String {
        (model.settings.suggestionsEnabled || model.settings.autocorrectEnabled) ? "On" : "Off"
    }

    private var enableBanner: some View {
        NavigationLink {
            EnableFlowView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn on Clink").font(.headline)
                    Text("Add Clink in Settings to start typing with it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

}
