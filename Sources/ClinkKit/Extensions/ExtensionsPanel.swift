/**
 `ExtensionsPanel`: full-keyboard overlay listing the user's enabled custom
 actions. Tapping a row asks the host (KeyboardViewController) to gather the
 action's input, run its PyMini script, and insert the result — the panel itself
 never touches the text document.

 Deliberately solid-filled (no per-cell `glassEffect`): a glass layer per row
 OOM-crashes / janks the keyboard extension, same class of bug as the grid cells.
 

 Module: extensions · Target: ClinkKit
 Learn: docs/14-extensions-sdk.md
 */
import SwiftUI

/// Full-keyboard overlay listing enabled custom actions. Tapping a row fires
/// `onRun`; the host gathers input, runs PyMini, and inserts the result.
struct ExtensionsPanel: View {
    /// Actions to show, in user order.
    let extensions: [ClinkExtension]
    let theme: Theme
    let cornerRadius: CGFloat
    /// Fired when a row is tapped — the host runs the action and inserts output.
    let onRun: (ClinkExtension) -> Void
    /// Dismisses the panel (typically closes the action overlay).
    let onDismiss: () -> Void
    /// Top-left "back" action; nil leaves the leading icon decorative.
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if extensions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(extensions) { ext in
                            row(ext)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 0) {
            PanelLeadingIcon("puzzlepiece.extension", theme: theme, onBack: onBack)
            Text("Actions")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.keyText.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(theme.keyText.color.opacity(0.5))
                    .frame(width: 44, height: KeyboardCanvas.Metrics.suggestionBarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)
    }

    private func row(_ ext: ClinkExtension) -> some View {
        Button { onRun(ext) } label: {
            HStack(spacing: 12) {
                Image(systemName: ext.icon.isEmpty ? "wand.and.stars" : ext.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(theme.accent.color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ext.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.keyText.color)
                        .lineLimit(1)
                    if !ext.summary.isEmpty {
                        Text(ext.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.keyText.color.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.keyText.color.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.keyFill.color)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 28))
                .foregroundStyle(theme.keyText.color.opacity(0.4))
            Text("No actions yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.keyText.color.opacity(0.7))
            Text("Create one in Clink → Custom Actions")
                .font(.system(size: 12))
                .foregroundStyle(theme.keyText.color.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
