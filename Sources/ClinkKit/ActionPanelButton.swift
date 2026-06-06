/**
 `ActionPanelButton`: the top-left icon in the suggestion bar that opens the
 active action panel (clipboard, notepad, or the panel picker). Also defines
 `barDivider`, the thin vertical rule between the icon and the bar content.
 */
import SwiftUI

// Shared thin vertical rule used between the clipboard icon and bar content.
func barDivider(theme: Theme) -> some View {
    Rectangle()
        .fill(theme.keyText.color.opacity(0.15))
        .frame(width: 0.5)
        .padding(.vertical, 11)
}

/// The top-left action-panel button on the suggestion bar. Renders whatever SF
/// Symbol the canvas resolves (lone panel icon, active panel's filled icon, or a
/// neutral grid when a picker is needed), accent-tinted while a panel is open.
struct ActionPanelButton: View {
    let systemName: String
    let isActive: Bool
    let theme: Theme
    /// Vertical hit-target multiplier — see `KeyboardSettings.panelButtonHitboxScale`.
    var hitboxScale: Double = 1.0
    let onTap: () -> Void

    var body: some View {
        Button { onTap() } label: {
            Image(systemName: systemName)
                .font(.system(size: 16))
                .foregroundStyle(isActive
                    ? theme.accent.color
                    : theme.keyText.color.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .hitboxExpand(hitboxScale, baseHeight: KeyboardCanvas.Metrics.suggestionBarHeight)
        }
        .buttonStyle(.plain)
    }
}
