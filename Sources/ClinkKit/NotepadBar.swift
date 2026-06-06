import SwiftUI

/// The notepad's inline compose strip — the keys type into `text` while this is
/// shown. Displays the buffer (tail-truncated so the caret end stays visible)
/// with trailing actions: browse saved notes + save (notes mode only), insert
/// the buffer into the host document, and clear.
struct NotepadBar: View {
    let text: String
    let mode: NotepadMode
    let theme: Theme
    let onInsert: () -> Void
    let onSave: () -> Void
    let onBrowse: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(text.isEmpty ? "Type to jot a note…" : text)
                .font(.system(size: 16))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(text.isEmpty
                    ? theme.keyText.color.opacity(0.35)
                    : theme.keyText.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            if mode == .notes {
                chipDivider
                iconButton("tray.full", action: onBrowse)
                chipDivider
                iconButton("plus", action: onSave)
            }
            chipDivider
            iconButton("text.insert", action: onInsert)
            chipDivider
            iconButton("xmark", action: onClear)
        }
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
