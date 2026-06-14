/**
 Layout page. One scrolling page, no tabs: the key-arrangement picker (grouped by
 script), then row options (number row / home-row inset), then the custom-keys
 editor inline.


 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Layout settings — arrangement picker, row options, and custom keys. The
/// Layout tab content of the Keys page; the custom-key editor sheet is hosted by
/// the page root via the `editing` binding.
struct LayoutControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    /// Bound to the Keys page's editor-sheet state — set non-nil to open it.
    @Binding var editing: CustomKeysView.KeyEdit?

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
        layoutTab
        rowsTab(model: model)
        CustomKeysView(editing: $editing)
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
#Preview { KeysView().clinkPreview() }
#endif
