/**
 Layout page. One scrolling page, no tabs: the key-arrangement picker (grouped by
 script), then row options (number row / home-row inset), then the custom-keys
 editor inline.


 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Layout settings: arrangement picker, row options, and custom keys.
/// `$model.settings` bindings persist via `AppModel.settings` `didSet`.
struct LayoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    /// Non-nil while the custom-key editor sheet is up. Hosted here (the screen
    /// root) so the themed sheet presents full-screen.
    @State private var keyEditing: CustomKeysView.KeyEdit?

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    private var groups: [(title: String, layouts: [KeyboardLayout])] {
        let order: [(String, [String])] = [
            ("Latin", ["qwerty", "spanish", "portuguese", "swedish", "norwegian",
                       "turkish", "azerty", "qwertz", "dvorak"]),
            ("Cyrillic", ["russian", "ukrainian"]),
            ("Greek", ["greek"]),
        ]
        let claimed = Set(order.flatMap { $0.1 })
        var result = order.map { title, ids in
            (title, ids.compactMap { id in KeyboardLayout.presets.first { $0.id == id } })
        }
        let other = KeyboardLayout.presets.filter { !claimed.contains($0.id) }
        if !other.isEmpty { result.append(("Other", other)) }
        return result.filter { !$0.1.isEmpty }
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
            layoutTab
            rowsTab(model: model)
            CustomKeysView(editing: $keyEditing)
        }
        .tint(themeAccent)
        .navigationTitle("Layout")
        .navigationBarTitleDisplayMode(.inline)
        .themedSheet(isPresented: Binding(get: { keyEditing != nil },
                                          set: { if !$0 { keyEditing = nil } }),
                     title: "Custom key") {
            if let edit = keyEditing {
                CustomKeyEditorBody(
                    initial: edit.key,
                    canRemove: edit.index != nil,
                    onSave: { saved in
                        CustomKeysView.commit(model: model, edit: edit, key: saved)
                        keyEditing = nil
                    },
                    onRemove: {
                        CustomKeysView.remove(model: model, edit: edit)
                        keyEditing = nil
                    })
            }
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private var layoutTab: some View {
        ForEach(groups, id: \.title) { group in
            CardSection(group.title) {
                ForEach(Array(group.layouts.enumerated()), id: \.element.id) { idx, layout in
                    if idx > 0 { Divider() }
                    row(layout)
                }
            }
        }
    }

    @ViewBuilder
    private func rowsTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Number row") {
            ToggleRow("Number row",
                      subtitle: "Always show 1–0 above the letters.",
                      isOn: $model.settings.showNumberRow)
            if model.settings.showNumberRow {
                Divider()
                SliderRow("Height", value: $model.settings.numberRowHeightScale,
                          in: 0.5...1.2, step: 0.05) {
                    "\(Int((model.settings.keyHeight * $0).rounded()))pt"
                }
                Divider()
                SliderRow("Text size", value: $model.settings.numberRowFontSize,
                          in: 14...30, step: 1) { "\(Int($0))pt" }
            }
        }

        CardSection("Home row") {
            ToggleRow("Inset home row",
                      subtitle: "Indent the middle letter row, like the system keyboard.",
                      isOn: $model.settings.homeRowInset)
            if model.settings.homeRowInset {
                Divider()
                SliderRow("Inset amount", value: $model.settings.homeRowInsetAmount,
                          in: 0...0.12, step: 0.005) { "\(Int(($0 * 100).rounded()))%" }
            }
        }
    }

    @ViewBuilder
    private func row(_ layout: KeyboardLayout) -> some View {
        let selected = model.settings.layoutID == layout.id
        Button {
            model.settings.layoutID = layout.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.name).foregroundStyle(.primary)
                    Text(sample(layout)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeAccent)
                }
            }
            .padding(.vertical, UX.rowVPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sample(_ layout: KeyboardLayout) -> String {
        (layout.rows.first ?? []).joined(separator: " ")
    }
}

#if DEBUG
#Preview { LayoutView().clinkPreview() }
#endif
