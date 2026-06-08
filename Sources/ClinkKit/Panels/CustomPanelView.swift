/**
 `CustomPanelView` renders a `PanelRuntime`'s node tree natively in SwiftUI and
 drives the MVU loop: a button `insert`s text and/or `set`s state (re-rendering);
 a `field` writes into state. `CustomPanelsContainer` is the keyboard chrome — a
 list of the user's panels that pushes into the selected panel's UI.

 Solid-filled, no per-cell `glassEffect` (that OOM-crashes the keyboard).
 */
import SwiftUI

public struct CustomPanelView: View {
    private let theme: Theme
    private let cornerRadius: CGFloat
    private let onInsert: (String) -> Void
    @State private var runtime: PanelRuntime
    /// Bumped after each state change to force a re-render (re-running `view`).
    @State private var tick = 0

    public init(source: String, theme: Theme, cornerRadius: CGFloat, onInsert: @escaping (String) -> Void) {
        self.theme = theme
        self.cornerRadius = cornerRadius
        self.onInsert = onInsert
        _runtime = State(initialValue: PanelRuntime(source: source))
    }

    public var body: some View {
        let result = renderUsing(tick)
        ScrollView {
            if let error = result.error {
                errorView(error)
            } else if let node = result.node {
                render(node).padding(10)
            }
        }
    }

    /// `tick` is read so SwiftUI re-evaluates `body` (and thus re-renders the
    /// panel) whenever state changes.
    private func renderUsing(_ tick: Int) -> PanelRender {
        _ = tick
        return runtime.render()
    }

    // Returns `AnyView` because the node tree is recursive (a vstack renders its
    // children via `render`), and a recursive `some View` would define the opaque
    // type in terms of itself.
    private func render(_ node: PanelNode) -> AnyView {
        switch node {
        case .text(let s, let size, let weight, let colorName):
            return AnyView(Text(s)
                .font(.system(size: size, weight: fontWeight(weight)))
                .foregroundStyle(color(colorName) ?? theme.keyText.color)
                .frame(maxWidth: .infinity, alignment: .leading))

        case .button(let label, let insert, let set, let style):
            return AnyView(Button {
                if let insert { onInsert(insert) }
                if runtime.apply(set: set) { tick &+= 1 }
            } label: {
                Text(label)
                    .font(.system(size: 16, weight: style == "primary" ? .semibold : .regular))
                    .foregroundStyle(style == "primary" ? Color.white : theme.keyText.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(style == "primary" ? theme.accent.color : theme.keyFill.color)
                    )
            }
            .buttonStyle(.plain))

        case .field(let key, let placeholder, _):
            return AnyView(TextField(placeholder, text: Binding(
                get: { runtime.value(forField: key) },
                set: { runtime.setField(key, $0); tick &+= 1 }))
                .textFieldStyle(.plain)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(theme.keyFill.color))
                .foregroundStyle(theme.keyText.color))

        case .vstack(let children, let spacing):
            return AnyView(VStack(spacing: spacing) { ForEach(indexed(children), id: \.0) { render($0.1) } })

        case .hstack(let children, let spacing):
            return AnyView(HStack(spacing: spacing) { ForEach(indexed(children), id: \.0) { render($0.1) } })

        case .grid(let children, let columns, let spacing):
            let cols = Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, columns))
            return AnyView(LazyVGrid(columns: cols, spacing: spacing) {
                ForEach(indexed(children), id: \.0) { render($0.1) }
            })

        case .spacer:
            return AnyView(Spacer(minLength: 8))

        case .divider:
            return AnyView(Rectangle().fill(theme.keyText.color.opacity(0.15)).frame(height: 0.5))
        }
    }

    private func indexed(_ nodes: [PanelNode]) -> [(Int, PanelNode)] {
        Array(nodes.enumerated())
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24)).foregroundStyle(.orange)
            Text("This panel has an error")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.keyText.color)
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.keyText.color.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private func fontWeight(_ s: String) -> Font.Weight {
        switch s {
        case "bold":     return .bold
        case "heavy":    return .heavy
        case "semibold": return .semibold
        case "medium":   return .medium
        case "light":    return .light
        case "thin":     return .thin
        default:         return .regular
        }
    }

    private func color(_ s: String) -> Color? {
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("#") { return hexColor(s) }
        switch s.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey": return .gray
        case "black": return .black
        case "white": return .white
        default: return nil
        }
    }

    private func hexColor(_ s: String) -> Color? {
        var hex = s; hex.removeFirst()
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

/// Keyboard chrome: lists the user's enabled panels; tapping one opens its UI.
/// When `standalone` is set, it skips the list and shows just that panel (used
/// when a custom panel has its own top-level picker entry).
struct CustomPanelsContainer: View {
    let panels: [ClinkPanel]
    let standalone: ClinkPanel?
    let theme: Theme
    let cornerRadius: CGFloat
    let onInsert: (String) -> Void
    let onDismiss: () -> Void
    /// Top-left "back" action at the panel root; nil leaves the icon decorative.
    /// (Inside a sub-panel the leading chevron always returns to the list first.)
    var onBack: (() -> Void)? = nil

    @State private var selected: ClinkPanel?

    /// The panel to show, if any: the fixed standalone one, or a list selection.
    private var shown: ClinkPanel? { standalone ?? selected }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let shown {
                CustomPanelView(source: shown.source, theme: theme,
                                cornerRadius: cornerRadius, onInsert: onInsert)
            } else {
                list
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            // Show a back chevron only when there's a list to return to.
            if selected != nil && standalone == nil {
                Button { selected = nil } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent.color)
                        .frame(width: KeyboardCanvas.Metrics.suggestionBarHeight)
                }
                .buttonStyle(.plain)
            } else {
                PanelLeadingIcon("square.grid.2x2", theme: theme, onBack: onBack)
            }
            Text(shown?.name ?? "Panels")
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

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(panels) { panel in
                    Button { selected = panel } label: {
                        HStack(spacing: 12) {
                            Image(systemName: panel.icon.isEmpty ? "square.grid.2x2" : panel.icon)
                                .font(.system(size: 18)).foregroundStyle(theme.accent.color).frame(width: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(panel.name).font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(theme.keyText.color)
                                if !panel.summary.isEmpty {
                                    Text(panel.summary).font(.system(size: 12))
                                        .foregroundStyle(theme.keyText.color.opacity(0.55)).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.keyText.color.opacity(0.3))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(theme.keyFill.color))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }
}
