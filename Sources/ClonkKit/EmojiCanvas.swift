import SwiftUI

/// The Clonk emoji keyboard — a sibling of `KeyboardCanvas` that reads the very
/// same `KeyboardSettings` (theme, sound) so configuring once styles both. A
/// scrollable emoji grid per category, with a glassy bottom bar (globe, category
/// tabs, backspace) that matches the letter keyboard's keys.
public struct EmojiCanvas: View {
    private let settings: KeyboardSettings
    private let onInsert: (String) -> Void
    private let onBackspace: () -> Void
    private let onAnyTap: () -> Void
    private let onNextKeyboard: (() -> Void)?

    @State private var controller: KeyboardController
    @Environment(\.colorScheme) private var colorScheme

    /// Selected category — proxied onto the controller so an external simulator
    /// can switch tabs. `nonmutating set` works because `controller` is a class.
    private var category: Int {
        get { controller.emojiCategory }
        nonmutating set { controller.emojiCategory = newValue }
    }

    public init(
        settings: KeyboardSettings,
        controller: KeyboardController? = nil,
        onInsert: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onAnyTap: @escaping () -> Void = {},
        onNextKeyboard: (() -> Void)? = nil
    ) {
        self.settings = settings
        _controller = State(initialValue: controller ?? KeyboardController())
        self.onInsert = onInsert
        self.onBackspace = onBackspace
        self.onAnyTap = onAnyTap
        self.onNextKeyboard = onNextKeyboard
    }

    private var theme: Theme { settings.resolvedTheme(dark: colorScheme == .dark) }

    public enum Metrics {
        public static let barHeight: CGFloat = 48
    }

    /// Match the letter keyboard's height so switching keyboards doesn't jump.
    public static func preferredHeight(for settings: KeyboardSettings) -> CGFloat {
        KeyboardCanvas.preferredHeight(for: settings)
    }

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 4)]

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(EmojiData.categories[category].emoji, id: \.self) { e in
                            EmojiCell(emoji: e, simulatedPressed: controller.pressedEmoji == e) {
                                onAnyTap()
                                onInsert(e)
                            }
                            .id(e)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Keep the simulator's target emoji on screen as it's "pressed".
                .onChange(of: controller.pressedEmoji) { _, e in
                    guard let e else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(e, anchor: .center) }
                }
            }

            bottomBar
        }
        .background(Color.clear)
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            if let onNextKeyboard {
                barTile { onNextKeyboard() } label: {
                    Image(systemName: "globe")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(EmojiData.categories.enumerated()), id: \.element.id) { idx, cat in
                        Button {
                            onAnyTap()
                            category = idx
                        } label: {
                            Image(systemName: cat.icon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(idx == category ? Color.white : theme.specialKeyText.color)
                                .frame(width: 36, height: 36)
                                .background {
                                    if idx == category {
                                        Circle().fill(theme.accent.color)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            barTile { onBackspace() } label: {
                Image(systemName: "delete.left")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Metrics.barHeight)
    }

    /// A glassy/solid tile matching the letter keyboard's special keys.
    @ViewBuilder private func barTile<L: View>(action: @escaping () -> Void,
                                               @ViewBuilder label: () -> L) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(CGFloat(settings.keyCornerRadius) - 2, 4),
                                     style: .continuous)
        let content = label()
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(theme.specialKeyText.color)
            .frame(width: 42, height: 36)
        Button { onAnyTap(); action() } label: {
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(theme.specialKeyFill.color), in: shape)
            } else {
                content.background(theme.specialKeyFill.color, in: shape)
            }
        }
        .buttonStyle(.plain)
    }
}

/// One tappable emoji, with a quick press bloom.
private struct EmojiCell: View {
    let emoji: String
    /// Driven by the showcase typing simulator — blooms with no finger on it.
    var simulatedPressed: Bool = false
    let action: () -> Void
    @State private var pressed = false

    private var isPressed: Bool { pressed || simulatedPressed }

    var body: some View {
        Text(emoji)
            .font(.system(size: 30))
            .frame(maxWidth: .infinity, minHeight: 40)
            .scaleEffect(isPressed ? 1.3 : 1)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.6), value: isPressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true } }
                    .onEnded { _ in pressed = false; action() }
            )
    }
}
