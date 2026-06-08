/**
 Themed bottom-sheet system. Opens at content's natural height, slides in/out,
 drag handle to dismiss.

 Two-pass render approach:
  • An invisible fixedSize overlay measures content's natural height immediately.
  • The visible panel starts off-screen and slides in once height is known.
  • The overlay owns its open/close animation so the parent just toggles isPresented.
 */
import SwiftUI
import iUXiOS

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Public modifier

extension View {
    func themedSheet<Content: View>(
        isPresented: Binding<Bool>,
        title: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(ThemedSheetModifier(isPresented: isPresented, title: title, sheetContent: content))
    }
}

private struct ThemedSheetModifier<SheetContent: View>: ViewModifier {
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Binding var isPresented: Bool
    let title: String?
    @ViewBuilder let sheetContent: SheetContent

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ThemedSheetOverlay(
                    cornerRadius: cardCornerRadius,
                    title: title,
                    onDismiss: { isPresented = false }
                ) { sheetContent }
            }
        }
    }
}

// MARK: - Overlay

struct ThemedSheetOverlay<Content: View>: View {
    let cornerRadius: CGFloat
    var title: String? = nil
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.resolvedKeyboardTheme) private var theme

    @GestureState private var dragOffset: CGFloat = 0
    @State private var measuredHeight: CGFloat = 0
    @State private var screenHeight: CGFloat = 0
    /// Drives slide-in / slide-out — set true once content is measured, false on dismiss.
    @State private var isIn = false

    private let headerHeight: CGFloat = 56

    private var panelHeight: CGFloat {
        guard measuredHeight > 0, screenHeight > 0 else { return 300 }
        return min(measuredHeight + headerHeight + 40, screenHeight - 80)
    }

    var body: some View {
        GeometryReader { geo in
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cornerRadius,
                style: .continuous
            )

            ZStack(alignment: .bottom) {
                // Scrim — fades with isIn
                Color.black.opacity(isIn ? 0.35 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .allowsHitTesting(isIn)

                // Visible panel — starts below screen, slides up when isIn becomes true
                VStack(spacing: 0) {
                    handleBar
                    Divider().opacity(0.3)
                    ScrollView {
                        content.padding(20)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: panelHeight)
                .background { panelBackground(shape) }
                .clipShape(shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
                .offset(y: isIn ? max(0, dragOffset) : panelHeight + 60)

                // Invisible measurement pass — renders content at natural height to get real size.
                // fixedSize(vertical:true) gives SwiftUI unbounded vertical space so content
                // reports its ideal height, not the constrained panel height.
                Color.clear
                    .overlay(alignment: .bottom) {
                        content
                            .padding(20)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(0)
                            .allowsHitTesting(false)
                            .background(
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: ContentHeightKey.self,
                                        value: g.size.height
                                    )
                                }
                            )
                    }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.88), value: isIn)
            .onAppear { screenHeight = geo.size.height }
            .onPreferenceChange(ContentHeightKey.self) { h in
                guard h > 0, !isIn else { return }
                measuredHeight = h
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                    isIn = true
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Surface for the floating panel — rendered exactly like the sidebar
    /// (`RootView.sidebarPanel`): real Liquid Glass on glass themes (translucent,
    /// refractive), the key-fill colour on solid themes. This replaces the theme
    /// *page* background, which is clear on glass themes and left these popups
    /// fully transparent.
    @ViewBuilder private func panelBackground(_ shape: some Shape) -> some View {
        if theme.material == .liquidGlass, #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(theme.keyFill.color)
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3)) { isIn = false }
        // Let the slide-out animation complete before removing the overlay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onDismiss() }
    }

    private var handleBar: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack {
                if let title { Text(title).font(.headline) }
                Spacer()
                Button("Done", action: dismiss).fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 80 { dismiss() }
                }
        )
    }
}
