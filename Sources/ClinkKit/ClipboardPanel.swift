/**
 `ClipboardPanel`: full-keyboard overlay for clipboard history when
 `clipboardStyle == .overlay`. Swipeable entry cards with copy / pin / delete.
 */
import SwiftUI

/// Full-keyboard replacement shown when `clipboardStyle == .overlay` and the
/// user opens the clipboard panel. Takes over the full keyboard frame (bar +
/// keys area). Sets NO background — the keyboard's `backgroundLayer` renders
/// behind it exactly as it does behind the keys.
struct ClipboardPanel: View {
    let entries: [ClipboardEntry]
    let theme: Theme
    let cornerRadius: CGFloat
    /// Lay entries out as a two-column grid of tappable cards (long-press for
    /// actions) instead of the default full-width swipeable card list.
    var gridLayout: Bool = false
    let onTap: (String) -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void
    /// Top-left "back" action (returns to the panel picker / main keyboard); nil
    /// leaves the leading icon decorative.
    var onBack: (() -> Void)? = nil
    let onCopy: (Int) -> Void
    let onTogglePin: (Int) -> Void
    let onDelete: (Int) -> Void
    let onClear: () -> Void

    @State private var openRow: Int? = nil

    private let scrollSpace = "clipScroll"

    var body: some View {
        VStack(spacing: 0) {
            // Header — same height and icon positioning as the suggestion bar.
            HStack(spacing: 0) {
                PanelLeadingIcon("doc.on.clipboard.fill", theme: theme, onBack: onBack)
                divider
                Spacer()
                divider
                headerButton("square.and.arrow.down", action: onSave)
                divider
                headerButton("trash", action: onClear)
                divider
                headerButton("xmark", action: onDismiss)
            }
            .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)

            // Content area
            if entries.isEmpty {
                Text("Nothing saved yet")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.keyText.color.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { vp in
                    ScrollView(.vertical, showsIndicators: false) {
                        Group {
                            if gridLayout {
                                gridContent(viewportHeight: vp.size.height)
                            } else {
                                cardList(viewportHeight: vp.size.height)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    // Soft fade at the scrolling edges, like the emoji grid.
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.06),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    )
                }
                // Name the *non-scrolling* viewport so each row's frame in this
                // space reflects scrolling (on the ScrollView it'd be content
                // space — constant — and rows would never close on scroll).
                .coordinateSpace(name: scrollSpace)
            }
        }
    }

    /// The swipeable cards. The card's glass surface and the action circles share
    /// one per-row `GlassEffectContainer` (see `SwipeRow.glassWrap`) so they morph
    /// into a gooey bridge as the card is dragged; the card text rides above the
    /// glass as a `SwipeRow` overlay so the material never frosts it.
    @ViewBuilder private func cardList(viewportHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                SwipeRow(id: index, cornerRadius: cornerRadius, actions: [
                    SwipeAction(icon: "doc.on.doc.fill", label: "Copy",
                                tint: .gray) { onCopy(index) },
                    SwipeAction(icon: entry.pinned ? "pin.slash.fill" : "pin.fill",
                                label: entry.pinned ? "Unpin" : "Pin",
                                tint: theme.accent.color) { onTogglePin(index) },
                    SwipeAction(icon: "trash.fill", label: "Delete",
                                tint: .red) { onDelete(index) },
                ], glass: theme.material == .liquidGlass,
                   openID: $openRow, scrollSpace: scrollSpace, viewportHeight: viewportHeight,
                   onTap: { onTap(entry.text) },
                   cardBackground: { cardSurface }) {
                    entryText(entry)
                }
            }
        }
    }

    /// Two-column grid of cards. Tap inserts; swipe reveals the same copy / pin /
    /// delete action circles as the list — left-column cards swipe left, right-column
    /// cards swipe right (mirrored), so the actions always open toward the centre.
    private func gridContent(viewportHeight: CGFloat) -> some View {
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                gridCell(index, entry, viewportHeight: viewportHeight)
            }
        }
    }

    private func gridCell(_ index: Int, _ entry: ClipboardEntry, viewportHeight: CGFloat) -> some View {
        // Odd indices are the right column (LazyVGrid fills row-major) → mirror so
        // they swipe right and open their actions toward the centre gutter.
        SwipeRow(id: index, cornerRadius: cornerRadius, actions: [
            SwipeAction(icon: "doc.on.doc.fill", label: "Copy",
                        tint: .gray) { onCopy(index) },
            SwipeAction(icon: entry.pinned ? "pin.slash.fill" : "pin.fill",
                        label: entry.pinned ? "Unpin" : "Pin",
                        tint: theme.accent.color) { onTogglePin(index) },
            SwipeAction(icon: "trash.fill", label: "Delete",
                        tint: .red) { onDelete(index) },
        ], glass: theme.material == .liquidGlass,
           mirror: index % 2 == 1,
           openID: $openRow, scrollSpace: scrollSpace, viewportHeight: viewportHeight,
           onTap: { onTap(entry.text) },
           cardBackground: { cardSurface }) {
            gridCellContent(entry)
        }
    }

    private func gridCellContent(_ entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(entry.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.keyText.color)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if entry.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent.color)
                }
            }
            Spacer(minLength: 0)
            if entry.date != .distantPast {
                Text(entry.date.clipboardRelative)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.keyText.color.opacity(0.45))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78, alignment: .topLeading)
    }

    private func entryText(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 10) {
            if entry.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.accent.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.keyText.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if entry.date != .distantPast {
                    Text(entry.date.clipboardRelative)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.keyText.color.opacity(0.45))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Card surface that tracks the keyboard's material: a theme-tinted liquid
    /// glass lens (so swiped-under action circles refract through it) when the
    /// keyboard is glass, an opaque key-fill otherwise.
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
            // Fixed square glyph box, centered, so every icon shares the same
            // optical center regardless of its intrinsic shape.
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
