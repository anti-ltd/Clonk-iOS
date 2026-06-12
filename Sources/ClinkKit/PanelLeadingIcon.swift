/**
 `PanelLeadingIcon`: the leading icon in a panel overlay's header. When given an
 `onBack` handler it renders a tappable back chevron (return to the panel picker,
 or the main keyboard when there's no picker to fall back to); with no handler it
 stays the panel's decorative glyph. Shared so every panel header behaves alike.
 

 Module: panels · Target: ClinkKit
 Learn: EXTENDING.md
 */
import SwiftUI

struct PanelLeadingIcon: View {
    private let symbol: String
    private let theme: Theme
    private let onBack: (() -> Void)?

    init(_ symbol: String, theme: Theme, onBack: (() -> Void)?) {
        self.symbol = symbol
        self.theme = theme
        self.onBack = onBack
    }

    var body: some View {
        if let onBack {
            Button(action: onBack) { icon(systemName: "chevron.left") }
                .buttonStyle(.plain)
        } else {
            icon(systemName: symbol)
        }
    }

    private func icon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: onBack == nil ? .regular : .semibold))
            .foregroundStyle(theme.accent.color)
            .frame(width: KeyboardCanvas.Metrics.suggestionBarHeight,
                   height: KeyboardCanvas.Metrics.suggestionBarHeight)
            .contentShape(Rectangle())
    }
}
