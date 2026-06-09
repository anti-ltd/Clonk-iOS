/**
 Themed bottom-sheet system. Opens at content's natural height, slides in/out.
 Handle bar gestures:
  • Swipe up  → expand to full height
  • Swipe down (natural height) → dismiss
  • Swipe down (expanded) → restore to natural height

 Two-pass render approach:
  • An invisible fixedSize overlay measures content's natural height immediately.
  • The visible panel starts off-screen and slides in once height is known.
  • The overlay owns its open/close animation so the parent just toggles isPresented.

 Height stability: panelHeight is @State updated only via explicit withAnimation calls,
 never via computed properties. This prevents re-renders from dragOffset changes
 from accidentally triggering height recalculations.
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
    /// Caps the initial natural height as a fraction of the available sheet height (0–1).
    var maxHeightFraction: CGFloat = 1.0
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.resolvedKeyboardTheme) private var theme

    @State private var dragOffset: CGFloat = 0
    @State private var isGesturing = false
    @State private var screenHeight: CGFloat = 0
    @State private var safeAreaTop: CGFloat = 0
    /// The rendered frame height — set once from measurement, then only changed
    /// via explicit withAnimation when expanding/collapsing. Never recomputed
    /// from dragOffset renders.
    @State private var panelHeight: CGFloat = 300
    /// Locked to naturalHeight after first measurement so expand/collapse can restore it.
    @State private var naturalHeight: CGFloat = 300
    /// Drives slide-in / slide-out — set true once content is measured, false on dismiss.
    @State private var isIn = false
    @State private var isExpanded = false

    private let headerHeight: CGFloat = 56
    /// Max sheet height: leaves room for the 44pt nav button bar + safe area + 8pt gap.
    private var maxSheetHeight: CGFloat {
        screenHeight - safeAreaTop - 44 - 8
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
                        content
                            .padding(20)
                    }
                }
                // Re-inject theme environment so sheets opened from outside
                // the NavigationStack (e.g. SidebarSheetHost) get the correct
                // tint and custom environment keys. Applied to the whole panel
                // so the Done button and content both pick it up.
                .tint(theme.accent.color)
                .environment(\.cardCornerRadius, cornerRadius)
                .environment(\.specialKeyTint, theme.specialKeyFill.color)
                .environment(\.themeTextColor, theme.keyText.color)
                .environment(\.useGlassCards, theme.material == .liquidGlass)
                .frame(maxWidth: .infinity)
                .frame(height: panelHeight)
                .background { panelBackground(shape) }
                .clipShape(shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
                .offset(y: isIn ? dragOffset : panelHeight + 60)
                // Kill animation during live drag so the panel tracks the finger instantly.
                // Spring-back in onEnded uses withAnimation after isGesturing = false,
                // so the spring is preserved for release.
                .transaction(value: dragOffset) { t in
                    if isGesturing { t.animation = nil }
                }

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
            .onAppear {
                screenHeight = geo.size.height
                safeAreaTop = geo.safeAreaInsets.top
            }
            .onPreferenceChange(ContentHeightKey.self) { h in
                guard h > 0, !isIn else { return }
                // Use UIScreen as fallback when preference fires before onAppear sets screenHeight.
                let sh = screenHeight > 0 ? screenHeight : UIScreen.main.bounds.height
                let sat = safeAreaTop > 0 ? safeAreaTop : 0
                let maxH = (sh - sat - 44 - 8) * maxHeightFraction
                let computed = min(h + headerHeight + 40, maxH)
                naturalHeight = computed
                panelHeight = computed
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
        isExpanded = false
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
                .onChanged { value in
                    isGesturing = true
                    let dy = value.translation.height
                    dragOffset = dy < 0
                        ? (isExpanded ? 0 : dy * 0.15)
                        : dy
                }
                .onEnded { value in
                    isGesturing = false
                    let dy = value.translation.height
                    // predictedEndTranslation is in the same coordinate space as translation
                    // (positive = downward), unlike velocity.height whose sign is unreliable.
                    let predicted = value.predictedEndTranslation.height
                    if isExpanded {
                        if dy > 60 || predicted > 150 {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                                isExpanded = false
                                panelHeight = naturalHeight
                                dragOffset = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                dragOffset = 0
                            }
                        }
                    } else {
                        if dy < -60 || predicted < -150 {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                                isExpanded = true
                                panelHeight = maxSheetHeight
                                dragOffset = 0
                            }
                        } else if dy > 80 || predicted > 200 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                dragOffset = 0
                            }
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                dragOffset = 0
                            }
                        }
                    }
                }
        )
    }
}
