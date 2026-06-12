/**
 `PanelSwitcherPanel`: full-keyboard panel picker shown when
 `panelPickerStyle == .cards` and 2+ panels are enabled. One card per panel —
 icon, label, and one-line summary.
 

 Module: panels · Target: ClinkKit
 Learn: docs/13-extending-panels.md
 */
import SwiftUI

/// Full-keyboard switcher shown when `panelPickerStyle == .cards` and 2+ panels
/// are enabled. One tappable card per panel — icon, label, one-line summary — in
/// the same visual language as the clipboard / notepad card lists. Selecting a
/// card routes through the canvas's `activate(_:)`.
struct PanelSwitcherPanel: View {
    let panels: [ActionPanel]
    let theme: Theme
    let cornerRadius: CGFloat
    let onSelect: (ActionPanel) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Top-left in the cards picker returns to the main keyboard, same
                // as the trailing dismiss.
                Button(action: onDismiss) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.accent.color)
                        .frame(width: KeyboardCanvas.Metrics.suggestionBarHeight,
                               height: KeyboardCanvas.Metrics.suggestionBarHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                divider
                Spacer()
                divider
                headerButton("xmark", action: onDismiss)
            }
            .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)

            GeometryReader { vp in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(panels) { panel in
                            Button { onSelect(panel) } label: { cardRow(panel) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: vp.size.height, alignment: .top)
                }
            }
        }
    }

    // MARK: - Card list

    private func cardRow(_ panel: ActionPanel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: panel.icon(active: false))
                .font(.system(size: 20))
                .foregroundStyle(theme.accent.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(panel.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.keyText.color)
                Text(panel.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.keyText.color.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.keyText.color.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardSurface }
        .contentShape(Rectangle())
    }

    // MARK: - Chrome

    @ViewBuilder private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch theme.material {
        case .liquidGlass:
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(theme.keyFill.color.opacity(theme.glassTintStrength)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(theme.keyFill.color.opacity(theme.glassTintStrength)))
            }
        case .solid:
            shape.fill(theme.keyFill.color)
        }
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 22, height: 22)
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
}
