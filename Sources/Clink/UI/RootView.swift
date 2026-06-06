/**
 Root tab container. Four tabs — Style, Typing, Feel, Setup — each hosting a
 self-contained navigation stack for its settings group.
 */
import SwiftUI
import iUXiOS

/// The app's home. A four-tab structure replaces the old single flat list: each
/// tab is one clear mental bucket — how the keyboard *looks* (Style), what it
/// does with *text* (Typing), how it *feels* to touch (Feel), and getting it
/// running / managing it (Setup). Every leaf screen is reached from exactly one
/// tab, so testers stop scanning seven look-alike rows to find a control.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .style
    /// One-shot: a first-run user (keyboard not yet enabled) lands on Setup.
    @State private var routedFirstRun = false

    enum Tab: Hashable { case style, typing, feel, setup }

    var body: some View {
        TabView(selection: $tab) {
            StyleHub(tab: $tab)
                .tabItem { Label("Style", systemImage: "paintbrush") }
                .tag(Tab.style)

            TypingHub()
                .tabItem { Label("Typing", systemImage: "text.cursor") }
                .tag(Tab.typing)

            FeelHub()
                .tabItem { Label("Feel", systemImage: "hand.tap") }
                .tag(Tab.feel)

            SetupHub()
                .tabItem { Label("Setup", systemImage: "gearshape") }
                .tag(Tab.setup)
        }
        .onAppear {
            if !routedFirstRun {
                routedFirstRun = true
                if !model.isKeyboardEnabled { tab = .setup }
            }
        }
    }
}

// MARK: - Style

/// Everything about how the keyboard looks, over a live preview.
private struct StyleHub: View {
    @Environment(AppModel.self) private var model
    @Binding var tab: RootView.Tab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    if !model.isKeyboardEnabled {
                        enableBanner
                    }

                    KeyboardPreview(settings: model.settings)
                        .padding(.top, 4)

                    CardSection("Appearance") {
                        NavRow("Theme", subtitle: "Colors, glass, and custom themes",
                               systemImage: "paintpalette",
                               value: model.settings.matchSystemAppearance ? "Auto" : model.settings.theme.name) {
                            ThemeEditorView()
                        }
                        Divider()
                        NavRow("Layout & Keys", subtitle: "Size, spacing, popups, and look",
                               systemImage: "keyboard", value: model.settings.layout.name) {
                            LayoutPickerView()
                        }
                    }
                }
                .padding(UX.screenPadding)
            }
            .navigationTitle("Style")
            .background(Color(.systemGroupedBackground))
        }
    }

    /// Shown until the keyboard is enabled — taps straight to the Setup tab
    /// rather than burying the most important first step.
    private var enableBanner: some View {
        Button {
            tab = .setup
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

// MARK: - Typing

/// What the keyboard does with text: prediction/correction, emoji, clipboard.
private struct TypingHub: View {
    @Environment(AppModel.self) private var model

    /// Panels currently switched on (clipboard / notepad / emoji) — used to show
    /// the picker-style control only when a choice is actually needed.
    private var enabledPanelCount: Int {
        [model.settings.clipboardEnabled,
         model.settings.notepadEnabled,
         model.settings.emojiEnabled,
         model.settings.calculatorEnabled].filter { $0 }.count
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    CardSection("Text") {
                        NavRow("Autocorrect & Suggestions",
                               subtitle: "Predictions, corrections, punctuation",
                               systemImage: "text.cursor", value: typingSummary) {
                            TypingView()
                        }
                    }

                    CardSection("Action panels") {
                        NavRow("Clipboard", subtitle: "History, re-paste, and management",
                               systemImage: "clipboard",
                               value: model.settings.clipboardEnabled
                                   ? (model.clipboard.history.isEmpty ? "On" : "\(model.clipboard.history.count) saved")
                                   : "Off") {
                            ClipboardHistoryView()
                        }
                        Divider()
                        NavRow("Notepad", subtitle: "Quick jots you can drop anywhere",
                               systemImage: "note.text",
                               value: model.settings.notepadEnabled
                                   ? (model.settings.notepadMode == .notes && !model.notepad.notes.isEmpty
                                       ? "\(model.notepad.notes.count) saved" : "On")
                                   : "Off") {
                            NotepadView()
                        }
                        Divider()
                        NavRow("Emoji", subtitle: "Skin tone, recents, on/off",
                               systemImage: "face.smiling",
                               value: model.settings.emojiEnabled ? "On" : "Off") {
                            EmojiSettingsView()
                        }
                        Divider()
                        NavRow("Calculator", subtitle: "Arithmetic results you can insert anywhere",
                               systemImage: "calculator",
                               value: model.settings.calculatorEnabled ? "On" : "Off") {
                            CalculatorSettingsView()
                        }
                    }

                    CardSection("Panel access") {
                        ToggleRow("Top-left icon",
                                  subtitle: "Open panels from a button on the suggestion bar.",
                                  isOn: $model.settings.activateWithIcon)
                        Divider()
                        ToggleRow("Slide up on 123",
                                  subtitle: "Drag the 123 key upward to open panels.",
                                  isOn: $model.settings.activateWithSlideUp)
                        if enabledPanelCount >= 2 {
                            Divider()
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Picker style")
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 10)
                                Picker("Picker style", selection: $model.settings.panelPickerStyle) {
                                    ForEach(PanelPickerStyle.allCases) { style in
                                        Text(style.label).tag(style)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 14)
                                Text("How the button / slide-up lets you choose when more than one panel is on.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                }
                .padding(UX.screenPadding)
            }
            .navigationTitle("Typing")
            .background(Color(.systemGroupedBackground))
        }
    }

    /// "On" when the keyboard is actively predicting or correcting, else "Off".
    private var typingSummary: String {
        (model.settings.suggestionsEnabled || model.settings.autocorrectEnabled) ? "On" : "Off"
    }
}

// MARK: - Feel

/// How the keyboard feels: sound/haptics, and the low-level touch tuning.
private struct FeelHub: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    CardSection("Output") {
                        NavRow("Sound & Haptics", subtitle: "Sounds, volume, and haptics",
                               systemImage: "speaker.wave.2",
                               value: model.settings.soundEnabled ? model.settings.soundPack.name : "Off") {
                            SoundPickerView()
                        }
                    }

                    CardSection("Touch") {
                        NavRow("Touch & Feel", subtitle: "Hitbox, cursor scroll, and precision tuning",
                               systemImage: "slider.horizontal.3") {
                            AdvancedSettingsView()
                        }
                    }
                }
                .padding(UX.screenPadding)
            }
            .navigationTitle("Feel")
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Setup

/// Getting Clink running and managing it: enable status + guide, plus backup /
/// restore and reset (promoted out of the old "Advanced" screen).
private struct SetupHub: View {
    @Environment(AppModel.self) private var model

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? "Version \(v)" : "Version \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    statusCard

                    CardSection("Get started") {
                        NavRow("Enable Clink",
                               subtitle: "Add the keyboard, use emoji, and Full Access",
                               systemImage: "keyboard.badge.ellipsis") {
                            EnableFlowView()
                        }
                    }

                    CardSection("Manage") {
                        NavRow("Backup & Restore",
                               subtitle: "Save, share, import, or reset your setup",
                               systemImage: "arrow.up.arrow.down.square") {
                            BackupView()
                        }
                    }

                    Text(appVersion)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(UX.screenPadding)
            }
            .navigationTitle("Setup")
            .background(Color(.systemGroupedBackground))
        }
    }

    private var statusCard: some View {
        CardSection {
            statusRow("Clink keyboard added", ok: model.isKeyboardEnabled,
                      offText: "Not added yet — tap Enable Clink below")
            Divider()
            statusRow("Full Access", ok: model.hasFullAccess,
                      offText: "Off — custom sounds & haptics disabled")
        }
    }

    private func statusRow(_ label: String, ok: Bool, offText: String? = nil) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                if !ok, let offText {
                    Text(offText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, UX.rowVPadding)
    }
}
