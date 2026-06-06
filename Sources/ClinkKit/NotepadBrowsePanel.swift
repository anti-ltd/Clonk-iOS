/**
 `NotepadBrowsePanel`: full-keyboard overlay for the saved-notes archive.
 Swipeable note cards with insert, load-into-buffer, and delete actions.
 */
import SwiftUI

/// Full-keyboard overlay listing the saved notes archive (notes mode). Mirrors
/// `ClipboardPanel`: swipeable cards with insert / load-into-buffer / delete.
/// Tapping a card inserts it into the host document; the load action drops it
/// into the compose buffer for further editing.
struct NotepadBrowsePanel: View {
    let notes: [NotepadNote]
    let theme: Theme
    let cornerRadius: CGFloat
    let onTap: (String) -> Void
    let onLoad: (String) -> Void
    let onDelete: (Int) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var openRow: Int? = nil
    private let scrollSpace = "noteScroll"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "note.text")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.accent.color)
                    .frame(width: KeyboardCanvas.Metrics.suggestionBarHeight)
                divider
                Spacer()
                divider
                headerButton("trash", action: onClear)
                divider
                headerButton("xmark", action: onDismiss)
            }
            .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)

            if notes.isEmpty {
                Text("No saved notes yet")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.keyText.color.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { vp in
                    ScrollView(.vertical, showsIndicators: false) {
                        cardList(viewportHeight: vp.size.height)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.06),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    )
                }
                .coordinateSpace(name: scrollSpace)
            }
        }
    }

    @ViewBuilder private func cardList(viewportHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                SwipeRow(id: index, cornerRadius: cornerRadius, actions: [
                    SwipeAction(icon: "pencil", label: "Load",
                                tint: theme.accent.color) { onLoad(note.text) },
                    SwipeAction(icon: "trash.fill", label: "Delete",
                                tint: .red) { onDelete(index) },
                ], glass: theme.material == .liquidGlass,
                   openID: $openRow, scrollSpace: scrollSpace, viewportHeight: viewportHeight,
                   onTap: { onTap(note.text) },
                   cardBackground: { cardSurface }) {
                    noteText(note)
                }
            }
        }
    }

    private func noteText(_ note: NotepadNote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.keyText.color)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
            Text(note.date.clipboardRelative)
                .font(.system(size: 11))
                .foregroundStyle(theme.keyText.color.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
