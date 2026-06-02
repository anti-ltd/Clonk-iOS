import SwiftUI
import iUXiOS

/// Create or edit a custom theme. Presented as a sheet from the theme picker.
/// Every change updates the live `KeyboardPreview` at the top, and Save upserts
/// the theme into `settings.customThemes` (which travels to the extension).
struct ThemeBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Theme

    init(theme: Theme) {
        _draft = State(initialValue: theme)
    }

    /// True once this theme exists in the saved list — i.e. we're editing, not
    /// creating. Gates the Delete button.
    private var isExisting: Bool {
        model.settings.customThemes.contains { $0.id == draft.id }
    }

    /// The user's current settings with the draft theme injected + selected, so
    /// the preview renders exactly what the keyboard will.
    private var previewSettings: KeyboardSettings {
        var s = model.settings
        s.matchSystemAppearance = false
        s.themeID = draft.id
        if let i = s.customThemes.firstIndex(where: { $0.id == draft.id }) {
            s.customThemes[i] = draft
        } else {
            s.customThemes.append(draft)
        }
        return s
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    KeyboardPreview(settings: previewSettings)

                    CardSection("Name") {
                        TextFieldRow(prompt: "Theme name", text: $draft.name)
                    }

                    CardSection("Style") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Material").foregroundStyle(.secondary).font(.subheadline)
                            Picker("Material", selection: $draft.material) {
                                Text("Solid").tag(KeyMaterial.solid)
                                Text("Liquid Glass").tag(KeyMaterial.liquidGlass)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, UX.rowVPadding)
                        Divider()
                        ToggleRow("Dark theme",
                                  subtitle: "Tints the status bar to match and sets the Liquid Glass fallback.",
                                  isOn: $draft.isDark)
                    }

                    CardSection("Colors") {
                        colorRow("Background", \.background)
                        Divider()
                        colorRow("Key fill", \.keyFill)
                        Divider()
                        colorRow("Key text", \.keyText)
                        Divider()
                        colorRow("Function-key fill", \.specialKeyFill)
                        Divider()
                        colorRow("Function-key text", \.specialKeyText)
                        Divider()
                        colorRow("Accent / pressed", \.accent)
                    }

                    if draft.material == .liquidGlass {
                        Text("Liquid Glass uses the fills as translucent tints — lower their opacity so the keys stay glassy.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    if isExisting {
                        Button(role: .destructive) {
                            model.deleteCustomTheme(id: draft.id)
                            dismiss()
                        } label: {
                            Text("Delete Theme").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .padding(.top, 4)
                    }
                }
                .padding(UX.screenPadding)
            }
            .navigationTitle(isExisting ? "Edit Theme" : "New Theme")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func colorRow(_ label: String, _ keyPath: WritableKeyPath<Theme, RGBA>) -> some View {
        ColorPicker(
            label,
            selection: Binding(
                get: { draft[keyPath: keyPath].color },
                set: { draft[keyPath: keyPath] = RGBA($0) }
            ),
            supportsOpacity: true
        )
        .padding(.vertical, 2)
    }

    private func save() {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = "My Theme"
        }
        model.saveCustomTheme(draft)
        // Select the freshly-saved theme so the user sees it take effect.
        if model.settings.matchSystemAppearance {
            if draft.isDark { model.settings.darkThemeID = draft.id }
            else { model.settings.lightThemeID = draft.id }
        } else {
            model.settings.themeID = draft.id
        }
        dismiss()
    }
}
