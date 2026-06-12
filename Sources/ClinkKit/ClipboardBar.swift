/**
 `ClipboardBar`: the inline clipboard strip shown in the suggestion bar area
 when the clipboard panel is in bar mode. Horizontally scrollable saved clips
 plus save and clear actions.
 

 Module: panels · Target: ClinkKit
 Learn: EXTENDING.md
 */
import SwiftUI

/// The clipboard-mode content of the suggestion bar: a horizontally scrollable
/// row of saved items on the left, with save and clear buttons pinned right.
/// Save reads the current UIPasteboard and appends to history.
/// Clear wipes the full history.
struct ClipboardBar: View {
    let entries: [ClipboardEntry]
    let theme: Theme
    let onTap: (String) -> Void
    let onSave: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if entries.isEmpty {
                Text("Nothing saved yet")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.keyText.color.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                            if idx > 0 { chipDivider }
                            clipChip(entry.text)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            chipDivider
            iconButton("square.and.arrow.down", action: onSave)
            chipDivider
            iconButton("trash", action: onClear)
        }
    }

    private func clipChip(_ text: String) -> some View {
        Button { onTap(text) } label: {
            Text(text)
                .font(.system(size: 16))
                .lineLimit(1)
                .foregroundStyle(theme.keyText.color)
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chipDivider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}
