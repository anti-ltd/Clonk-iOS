/**
 Root view with a collapsible slide-in sidebar. The sidebar overlays the content
 from the left edge; a scrim tap or row selection closes it. Detail navigation
 (Theme editor, Sound picker, etc.) lives inside the per-destination NavigationStack.
 */
import SwiftUI
import iUXiOS

// Shared sidebar open/close state, injected via @Environment so DetailHost can
// open the sidebar without threading a binding through every content view.
@Observable @MainActor
final class SidebarState {
    var isOpen = false
}

// MARK: - Root

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var sidebar = SidebarState()
    @State private var destination: SidebarDestination = .clink
    @State private var routedFirstRun = false

    enum SidebarDestination: Hashable {
        case clink, localization, style, typing, feel
        case clipboard, notepad, emoji, calculator
    }

    private let sidebarWidth: CGFloat = 290
    private let sidebarAnim = Animation.spring(response: 0.32, dampingFraction: 0.86)

    var body: some View {
        ZStack(alignment: .leading) {
            DetailHost(destination: destination)
                .id(destination)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(sidebar)

            // Scrim
            Color.black
                .ignoresSafeArea()
                .opacity(sidebar.isOpen ? 0.35 : 0)
                .allowsHitTesting(sidebar.isOpen)
                .onTapGesture { withAnimation(sidebarAnim) { sidebar.isOpen = false } }

            // Left-edge grabber: narrow strip that captures a horizontal
            // swipe-in to open, with high priority so the content scroll view
            // can't steal a vertical-leaning drag. Only present while closed.
            if !sidebar.isOpen {
                Color.clear
                    .frame(width: 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 12)
                            .onEnded { v in
                                // Only fire when the drag is clearly horizontal.
                                guard v.translation.width > 40,
                                      v.translation.width > abs(v.translation.height) else { return }
                                withAnimation(sidebarAnim) { sidebar.isOpen = true }
                            }
                    )
            }

            // Sidebar panel
            sidebarPanel

            // Always-on liquid-glass strip filling the top safe area.
            topGlassStrip
        }
        .animation(sidebarAnim, value: sidebar.isOpen)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { v in
                    // Swipe left anywhere to dismiss.
                    if sidebar.isOpen && v.translation.width < -50 {
                        withAnimation(sidebarAnim) { sidebar.isOpen = false }
                    }
                }
        )
        .onAppear {
            guard !routedFirstRun else { return }
            routedFirstRun = true
            if !model.isKeyboardEnabled { destination = .clink }
        }
    }

    @ViewBuilder
    private var sidebarPanel: some View {
        SidebarPanel(sidebar: sidebar, destination: $destination)
            .frame(width: sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(alignment: .trailing) {
                let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
                Group {
                    if #available(iOS 26.0, *) {
                        Color.clear.glassEffect(.regular, in: shape)
                    } else {
                        shape.fill(.regularMaterial)
                    }
                }
                // Wider + trailing-aligned so the glass rim (and left rounded
                // corners) bleed off the left screen edge — only the right
                // corners show. Bottom bleeds past the safe area; the top stays
                // inside it so the panel sits below the status-bar strip.
                .frame(width: sidebarWidth + 40)
                .ignoresSafeArea(edges: .bottom)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(sidebar.isOpen ? 0.08 : 0), radius: 20, x: 5, y: 0)
            .offset(x: sidebar.isOpen ? 0 : -sidebarWidth)
    }

    private var topGlassStrip: some View {
        VStack(spacing: 0) {
            Group {
                if #available(iOS 26.0, *) {
                    Color.clear.glassEffect(.regular, in: Rectangle())
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
            .frame(height: 0)            // zero-height; ignoresSafeArea fills the inset
            .ignoresSafeArea(edges: .top)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Detail host

private struct DetailHost: View {
    @Environment(SidebarState.self) private var sidebar
    let destination: RootView.SidebarDestination

    var body: some View {
        NavigationStack {
            destinationView
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                sidebar.isOpen = true
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination {
        case .clink:        ClinkContent()
        case .localization: LocalizationView()
        case .style:      StyleContent()
        case .typing:     TypingContent()
        case .feel:       FeelContent()
        case .clipboard:  ClipboardHistoryView()
        case .notepad:    NotepadView()
        case .emoji:      EmojiSettingsView()
        case .calculator: CalculatorSettingsView()
        }
    }
}

// MARK: - Sidebar panel

private struct SidebarPanel: View {
    @Environment(AppModel.self) private var model
    let sidebar: SidebarState
    @Binding var destination: RootView.SidebarDestination
    @State private var showExtensionPicker = false

    private func isEnabled(_ d: RootView.SidebarDestination) -> Bool {
        switch d {
        case .calculator: return model.settings.calculatorEnabled
        case .clipboard:  return model.settings.clipboardEnabled
        case .emoji:      return model.settings.emojiEnabled
        case .notepad:    return model.settings.notepadEnabled
        default:          return false
        }
    }

    private var enabledExtensions: [ExtEntry] {
        allExtensions.filter { isEnabled($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brandHeader

                sectionLabel("Onboarding")
                SidebarRow("Setup", icon: "keyboard", selected: destination == .clink) {
                    select(.clink)
                }
                SidebarRow("Localization", icon: "globe", selected: destination == .localization) {
                    select(.localization)
                }

                sectionLabel("Customization")
                SidebarRow("Style",  icon: "paintbrush",  selected: destination == .style)  { select(.style)  }
                SidebarRow("Typing", icon: "text.cursor", selected: destination == .typing) { select(.typing) }
                SidebarRow("Feel",   icon: "hand.tap",    selected: destination == .feel)   { select(.feel)   }

                extensionsSection
            }
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showExtensionPicker) {
            ExtensionPickerSheet()
        }
    }

    @ViewBuilder
    private var extensionsSection: some View {
        HStack {
            Text("Extensions")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            Spacer()
            Button { showExtensionPicker = true } label: {
                Image(systemName: "gearshape")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -10)   // keep glyph edge-aligned despite the larger hitbox
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)

        ForEach(enabledExtensions) { ext in
            SidebarRow(ext.name, icon: ext.icon, selected: destination == ext.id) {
                select(ext.id)
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Clink").font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }

    private func select(_ d: RootView.SidebarDestination) {
        destination = d
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { sidebar.isOpen = false }
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    let label: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    init(_ label: String, icon: String, selected: Bool, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.selected = selected; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22, alignment: .center)
                Text(label).fontWeight(selected ? .semibold : .regular)
                Spacer()
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                if selected {
                    if #available(iOS 26.0, *) {
                        Color.clear.glassEffect(
                            .regular.tint(Color.accentColor).interactive(),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    }
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extension data

private struct ExtEntry: Identifiable {
    let id: RootView.SidebarDestination
    let name: String
    let icon: String
}

private let allExtensions: [ExtEntry] = [
    ExtEntry(id: .calculator, name: "Calculator", icon: "numbers.rectangle"),
    ExtEntry(id: .clipboard,  name: "Clipboard",  icon: "clipboard"),
    ExtEntry(id: .emoji,      name: "Emoji",      icon: "face.smiling"),
    ExtEntry(id: .notepad,    name: "Notepad",    icon: "note.text"),
]

// MARK: - Extension picker sheet

private struct ExtensionPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var m = model
        NavigationStack {
            List {
                Toggle(isOn: $m.settings.calculatorEnabled) { Label("Calculator", systemImage: "numbers.rectangle") }
                Toggle(isOn: $m.settings.clipboardEnabled)  { Label("Clipboard",  systemImage: "clipboard")  }
                Toggle(isOn: $m.settings.emojiEnabled)      { Label("Emoji",      systemImage: "face.smiling") }
                Toggle(isOn: $m.settings.notepadEnabled)    { Label("Notepad",    systemImage: "note.text")   }
            }
            .navigationTitle("Extensions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Clink (setup)

private struct ClinkContent: View {
    @Environment(AppModel.self) private var model

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? "Version \(v)" : "Version \(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                statusCard
                CardSection("Get started") {
                    NavRow("Enable Clink",
                           subtitle: "Add the keyboard, use emoji, and Full Access",
                           systemImage: "keyboard.badge.ellipsis") { EnableFlowView() }
                }
                CardSection("Manage") {
                    NavRow("Backup & Restore",
                           subtitle: "Save, share, import, or reset your setup",
                           systemImage: "arrow.up.arrow.down.square") { BackupView() }
                }
                Text(appVersion)
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("Clink")
        .background(Color(.systemGroupedBackground))
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
                if !ok, let offText { Text(offText).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(.vertical, UX.rowVPadding)
    }
}

// MARK: - Style

private struct StyleContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                KeyboardPreview(settings: model.settings).padding(.top, 4)
                CardSection("Appearance") {
                    NavRow("Theme",
                           subtitle: "Colors, glass, and custom themes",
                           systemImage: "paintpalette",
                           value: model.settings.matchSystemAppearance ? "Auto" : model.settings.theme.name) {
                        ThemeEditorView()
                    }
                    Divider()
                    NavRow("Layout & Keys",
                           subtitle: "Size, spacing, popups, and look",
                           systemImage: "keyboard",
                           value: model.settings.layout.name) {
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

// MARK: - Typing

private struct TypingContent: View {
    @Environment(AppModel.self) private var model

    private var enabledPanelCount: Int {
        [model.settings.clipboardEnabled, model.settings.notepadEnabled,
         model.settings.emojiEnabled, model.settings.calculatorEnabled].filter { $0 }.count
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Text") {
                    NavRow("Autocorrect & Suggestions",
                           subtitle: "Predictions, corrections, punctuation",
                           systemImage: "text.cursor",
                           value: (model.settings.suggestionsEnabled || model.settings.autocorrectEnabled) ? "On" : "Off") {
                        TypingView()
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
                                .padding(.horizontal, 14).padding(.top, 10)
                            Picker("Picker style", selection: $model.settings.panelPickerStyle) {
                                ForEach(PanelPickerStyle.allCases) { style in
                                    Text(style.label).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 14)
                            Text("How the button / slide-up lets you choose when more than one panel is on.")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 14).padding(.bottom, 10)
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

// MARK: - Feel

private struct FeelContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Output") {
                    NavRow("Sound & Haptics",
                           subtitle: "Sounds, volume, and haptics",
                           systemImage: "speaker.wave.2",
                           value: model.settings.soundEnabled ? model.settings.soundPack.name : "Off") {
                        SoundPickerView()
                    }
                }
                CardSection("Touch") {
                    NavRow("Touch & Feel",
                           subtitle: "Hitbox, cursor scroll, and precision tuning",
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
