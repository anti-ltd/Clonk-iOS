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
                    }

                    CardSection("Keyboard") {
                        NavRow("Setup & Full Access", systemImage: "gearshape") {
                            EnableFlowView()
                        }
                    }

                    footer
                }
                .padding(UX.screenPadding)
            }
            .navigationTitle("Clonk")
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
                    Text("Turn on Clonk").font(.headline)
                    Text("Add Clonk in Settings to start typing with it.")
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

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Clonk").font(.footnote.weight(.semibold))
            Text("A fully customizable keyboard. Offline. No accounts. Private by default.")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let version = appVersion {
                Text(version)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var appVersion: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return nil }
        if let build = info?["CFBundleVersion"] as? String, build != short {
            return "Version \(short) (\(build))"
        }
        return "Version \(short)"
    }
}
