/**
 Root view with a collapsible slide-in sidebar. The sidebar overlays the content
 from the left edge; a scrim tap or row selection closes it. Detail navigation
 (Theme editor, Sound picker, etc.) lives inside the per-destination NavigationStack.
 */
import SwiftUI
import iUXiOS

// MARK: - Theme page background

private struct ResolvedThemeKey: EnvironmentKey {
    static let defaultValue = Theme.default
}

extension EnvironmentValues {
    var resolvedKeyboardTheme: Theme {
        get { self[ResolvedThemeKey.self] }
        set { self[ResolvedThemeKey.self] = newValue }
    }
}

private struct ThemePageBackgroundModifier: ViewModifier {
    @Environment(\.resolvedKeyboardTheme) private var theme
    func body(content: Content) -> some View {
        content.background {
            Group {
                if let grad = theme.backgroundGradient {
                    grad.makeView()
                } else {
                    theme.background.color
                }
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    func themePageBackground() -> some View { modifier(ThemePageBackgroundModifier()) }
}

// Shared sidebar open/close state, injected via @Environment so DetailHost can
// open the sidebar without threading a binding through every content view.
@Observable @MainActor
final class SidebarState {
    var isOpen = false
    /// Incremented when a NavigationLink destination appears; decremented on disappear.
    /// Used to hide the sidebar button when a back button is present.
    var navigationDepth: Int = 0
    /// Jump to a destination from inside a content page (the onboarding "next
    /// step" buttons). Wired up by `RootView`.
    var navigate: ((RootView.SidebarDestination) -> Void)?
}

private struct NavDepthModifier: ViewModifier {
    @Environment(SidebarState.self) private var sidebar
    func body(content: Content) -> some View {
        content
            .onAppear { sidebar.navigationDepth += 1 }
            .onDisappear { sidebar.navigationDepth -= 1 }
    }
}

extension View {
    func tracksNavigationDepth() -> some View { modifier(NavDepthModifier()) }
}

// MARK: - Root

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var sidebar = SidebarState()
    @State private var navBar = NavBarState()
    @State private var destination: SidebarDestination = .clink
    @State private var routedFirstRun = false

    private var resolvedTheme: Theme {
        model.settings.resolvedTheme(dark: colorScheme == .dark)
    }

    @ViewBuilder private var themeBackground: some View {
        if let grad = resolvedTheme.backgroundGradient {
            grad.makeView()
        } else {
            resolvedTheme.background.color
        }
    }

    enum SidebarDestination: Hashable {
        case clink, permissions, localization, layout, theme
        // Customization placeholders (pages to be built out).
        case animation, automation, cursor, keys, sounds, haptics, suggestions, popups
        // Advanced placeholders.
        case hitboxes, overlays, response, performance
        case clipboard, notepad, emoji, calculator
        /// The Python extension SDK — author / manage custom keyboard actions.
        case customActions
        /// Custom panels — author / manage full custom keyboard UIs.
        case customPanels
    }

    private let sidebarWidth: CGFloat = 290
    private let sidebarAnim = Animation.spring(response: 0.32, dampingFraction: 0.86)

    var body: some View {
        ZStack(alignment: .leading) {
            DetailHost(destination: destination)
                .id(destination)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(sidebar)
                .environment(navBar)

            // Scrim
            Color.black
                .ignoresSafeArea()
                .opacity(sidebar.isOpen ? 0.35 : 0)
                .allowsHitTesting(sidebar.isOpen)
                .onTapGesture { withAnimation(sidebarAnim) { sidebar.isOpen = false } }

            // Left-edge grabber: narrow strip that captures a horizontal
            // swipe-in to open, with high priority so the content scroll view
            // can't steal a vertical-leaning drag. Only present while closed.
            if !sidebar.isOpen {
                Color.clear
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 12)
                            .onEnded { v in
                                // Only fire when the drag is clearly horizontal.
                                guard v.translation.width > 40,
                                      v.translation.width > abs(v.translation.height) else { return }
                                withAnimation(sidebarAnim) { sidebar.isOpen = true }
                            }
                    )
                    // Position the 24pt strip at the left edge; the surrounding
                    // area is transparent and passes touches through to content.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }

            // Sidebar panel
            sidebarPanel

            // Always-on liquid-glass strip filling the top safe area.
            topGlassStrip
        }
        .fontDesign(resolvedTheme.keyFontDesign.fontDesign)
        .environment(\.resolvedKeyboardTheme, resolvedTheme)
        .environment(\.cardTint, resolvedTheme.keyFill.color)
        .environment(\.useGlassCards, resolvedTheme.material == .liquidGlass)
        .environment(\.cardCornerRadius, model.settings.keyCornerRadius)
        .environment(\.themeTextColor, resolvedTheme.keyText.color)
        .environment(\.specialKeyTint, resolvedTheme.specialKeyFill.color)
        .environment(\.specialKeyTextColor, resolvedTheme.specialKeyText.color)
        .environment(navBar)
        // Nav buttons: top-aligned overlay occupies only the 44pt nav bar strip,
        // so no full-screen frame that would swallow touches to content below.
        .overlay(alignment: .top) { navButtonLayer }
        .animation(sidebarAnim, value: sidebar.isOpen)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { v in
                    // Swipe left anywhere to dismiss.
                    if sidebar.isOpen && v.translation.width < -50 {
                        withAnimation(sidebarAnim) { sidebar.isOpen = false }
                    }
                }
        )
        .onChange(of: destination) { _, _ in
            // Clear the trailing button before the new destination's onAppear
            // sets its own — prevents the old view's onDisappear (which fires
            // later) from wiping the new view's icon.
            navBar.trailingIcon = nil
            navBar.trailingAction = nil
        }
        .onAppear {
            // Let content pages drive navigation (onboarding step buttons).
            sidebar.navigate = { [destBinding = $destination] in destBinding.wrappedValue = $0 }
            guard !routedFirstRun else { return }
            routedFirstRun = true
            if !model.isKeyboardEnabled { destination = .clink }
        }
    }

    @ViewBuilder
    private var sidebarPanel: some View {
        SidebarPanel(sidebar: sidebar, destination: $destination)
            .frame(width: sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(alignment: .trailing) {
                // Square the bottom-trailing corner; the leading corners bleed off
                // the left screen edge so their radius is moot.
                let r = model.settings.keyCornerRadius
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: r, bottomLeadingRadius: r,
                    bottomTrailingRadius: 0, topTrailingRadius: r, style: .continuous)
                Group {
                    if resolvedTheme.material == .liquidGlass, #available(iOS 26.0, *) {
                        Color.clear.glassEffect(.regular, in: shape)
                    } else {
                        shape.fill(resolvedTheme.keyFill.color)
                    }
                }
                // Wider + trailing-aligned so the glass rim (and left rounded
                // corners) bleed off the left screen edge — only the right
                // corners show. Bottom bleeds well past the screen edge (negative
                // padding) so the bottom rim is off-screen too — no visible edge;
                // the top stays inside the safe area, below the status-bar strip.
                .frame(width: sidebarWidth + 40)
                .padding(.bottom, -60)
                .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .trailing) {
                let r = model.settings.keyCornerRadius
                UnevenRoundedRectangle(
                    topLeadingRadius: r, bottomLeadingRadius: r,
                    bottomTrailingRadius: 0, topTrailingRadius: r, style: .continuous)
                    .strokeBorder(resolvedTheme.accent.color.opacity(0.5), lineWidth: 1)
                    .frame(width: sidebarWidth + 40)
                    .padding(.bottom, -60)
                    .ignoresSafeArea(edges: .bottom)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(sidebar.isOpen ? 0.08 : 0), radius: 20, x: 5, y: 0)
            .offset(x: sidebar.isOpen ? 0 : -sidebarWidth)
    }

    private var topGlassStrip: some View {
        VStack(spacing: 0) {
            Group {
                if #available(iOS 26.0, *) {
                    Color.clear.glassEffect(.regular, in: Rectangle())
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
            .frame(height: 0)            // zero-height; ignoresSafeArea fills the inset
            .ignoresSafeArea(edges: .top)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    private var navButtonLayer: some View {
        HStack(spacing: 0) {
            ThemeNavButton(systemName: "sidebar.left") {
                withAnimation(sidebarAnim) { sidebar.isOpen.toggle() }
            }
            .opacity(sidebar.navigationDepth > 0 ? 0 : 1)
            .allowsHitTesting(sidebar.navigationDepth == 0)
            Spacer(minLength: 0).allowsHitTesting(false)
            if let icon = navBar.trailingIcon, let action = navBar.trailingAction {
                ThemeNavButton(systemName: icon, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.horizontal, 16)
        .opacity(sidebar.isOpen ? 0 : 1)
        .allowsHitTesting(!sidebar.isOpen)
        // Overlay content doesn't inherit environment from the modifier chain,
        // so explicitly supply the values ThemeNavButton reads.
        .environment(\.resolvedKeyboardTheme, resolvedTheme)
        .environment(\.useGlassCards, resolvedTheme.material == .liquidGlass)
        .environment(\.cardCornerRadius, model.settings.keyCornerRadius)
        .environment(\.specialKeyTint, resolvedTheme.specialKeyFill.color)
    }
}

// MARK: - Detail host

private struct DetailHost: View {
    @Environment(AppModel.self) private var model
    @Environment(SidebarState.self) private var sidebar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeTextColor) private var themeTextColor
    let destination: RootView.SidebarDestination

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        NavigationStack {
            destinationView
                .navigationBarTitleDisplayMode(.inline)
        }
        .tint(themeAccent)
        .foregroundColor(themeTextColor)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination {
        case .clink:        ClinkContent()
        case .permissions:  PermissionsView()
        case .localization: LocalizationView()
        case .layout:       LayoutView()
        case .theme:        ThemeEditorView()
        case .clipboard:  ClipboardHistoryView()
        case .notepad:    NotepadView()
        case .emoji:      EmojiSettingsView()
        case .calculator: CalculatorSettingsView()
        case .customActions: ExtensionsView()
        case .customPanels: PanelsView()
        // Placeholder pages — content to be built out.
        case .animation:   AnimationView()
        case .automation:  AutomationView()
        case .cursor:      CursorView()
        case .keys:        KeysView()
        case .sounds:      SoundsView()
        case .haptics:     HapticsView()
        case .suggestions: SuggestionsView()
        case .popups:      PopupsView()
        case .hitboxes:     HitboxView()
        case .overlays:     OverlaysView()
        case .performance:  PerformanceView()
        case .response:     ResponseView()
        }
    }
}

// MARK: - Placeholder page

/// A stand-in page for a settings area that's scaffolded but not yet built out.
private struct PlaceholderView: View {
    let title: String
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.largeTitle).foregroundStyle(.secondary)
                Text("\(title) settings are coming soon.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            .padding(UX.screenPadding)
        }
        .navigationTitle(title)
        .themePageBackground()
    }
}

// MARK: - Sidebar panel

private struct SidebarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeTextColor) private var themeTextColor
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.specialKeyTint) private var specialKeyTint
    @Environment(\.specialKeyTextColor) private var specialKeyTextColor
    let sidebar: SidebarState
    @Binding var destination: RootView.SidebarDestination
    @State private var showExtensionPicker = false
    @State private var showBackupSheet = false
    /// Whether the sidebar can scroll further up / down — drives the edge fades
    /// and the scroll-affordance carets.
    @State private var canScrollUp = false
    @State private var canScrollDown = false

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    private func isEnabled(_ d: RootView.SidebarDestination) -> Bool {
        switch d {
        case .calculator: return model.settings.calculatorEnabled
        case .clipboard:  return model.settings.clipboardEnabled
        case .emoji:      return model.settings.emojiEnabled
        case .notepad:    return model.settings.notepadEnabled
        default:          return false
        }
    }

    private var enabledExtensions: [ExtEntry] {
        model.settings.extensionOrder
            .compactMap { id in allExtensions.first { $0.name.lowercased() == id } }
            .filter { isEnabled($0.id) }
    }

    /// One sidebar navigation entry. Categories are kept alphabetical by sorting
    /// these by `title`.
    private struct NavItem: Identifiable {
        let title: String
        let icon: String
        let dest: RootView.SidebarDestination
        var id: String { title }
    }

    /// Customization pages, alphabetical. (Several are placeholders pending build-out.)
    private var customizationRows: [NavItem] {
        [
            NavItem(title: "Animation",   icon: "wand.and.stars",        dest: .animation),
            NavItem(title: "Automation",  icon: "gearshape.2",           dest: .automation),
            NavItem(title: "Custom Actions", icon: "puzzlepiece.extension", dest: .customActions),
            NavItem(title: "Custom Panels", icon: "square.grid.2x2",      dest: .customPanels),
            NavItem(title: "Cursor",      icon: "cursorarrow",           dest: .cursor),
            NavItem(title: "Haptics",     icon: "hand.tap",                         dest: .haptics),
            NavItem(title: "Keys",        icon: "keyboard",              dest: .keys),
            NavItem(title: "Popups",      icon: "rectangle.portrait.on.rectangle.portrait", dest: .popups),
            NavItem(title: "Sounds",      icon: "speaker.wave.2",        dest: .sounds),
            NavItem(title: "Suggestions", icon: "text.cursor",            dest: .suggestions),
            NavItem(title: "Theme",       icon: "paintpalette",          dest: .theme),
        ].sorted { $0.title < $1.title }
    }

    /// Advanced pages, alphabetical. (Placeholders pending build-out.)
    private var advancedRows: [NavItem] {
        [
            NavItem(title: "Hitboxes",    icon: "square.dashed",       dest: .hitboxes),
            NavItem(title: "Overlays",    icon: "square.stack.3d.up",  dest: .overlays),
            NavItem(title: "Performance", icon: "gauge.with.dots.needle.bottom.50percent", dest: .performance),
            NavItem(title: "Response",    icon: "timer",               dest: .response),
        ].sorted { $0.title < $1.title }
    }

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brandHeader

                sectionLabel("General")
                SidebarRow("Permissions", icon: "lock.shield", selected: destination == .permissions) {
                    select(.permissions)
                }
                SidebarRow("Localization", icon: "globe", selected: destination == .localization) {
                    select(.localization)
                }
                SidebarRow("Layout", icon: "textformat.abc", selected: destination == .layout) {
                    select(.layout)
                }

                sectionLabel("Customization")
                ForEach(customizationRows) { row in
                    SidebarRow(row.title, icon: row.icon, selected: destination == row.dest) {
                        select(row.dest)
                    }
                }

                extensionsSection

                sectionLabel("Advanced")
                ForEach(advancedRows) { row in
                    SidebarRow(row.title, icon: row.icon, selected: destination == row.dest) {
                        select(row.dest)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .modifier(ScrollEdgeTracker(up: $canScrollUp, down: $canScrollDown))
        // Fade the top edge once scrolled (keeps the brand header crisp at rest)
        // and the bottom edge while more is below.
        .mask(fadeMask(canUp: canScrollUp, canDown: canScrollDown))
        // Scroll affordances drawn ON TOP of the mask (so they never fade): a
        // caret top-left to scroll up, bottom-right to scroll down.
        .overlay(alignment: .topTrailing) {
            scrollCaret("chevron.up").opacity(canScrollUp ? 1 : 0)
        }
        .overlay(alignment: .bottomTrailing) {
            scrollCaret("chevron.down").opacity(canScrollDown ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.2), value: canScrollUp)
        .animation(.easeInOut(duration: 0.2), value: canScrollDown)
        .foregroundColor(themeTextColor)
        .themedSheet(isPresented: $showExtensionPicker, title: "Extensions") {
            ExtensionPickerContent()
        }
        .themedSheet(isPresented: $showBackupSheet, title: "Backup & Restore") {
            BackupControls()
        }
    }

    private func fadeMask(canUp: Bool, canDown: Bool) -> LinearGradient {
        // Wide, soft fade bands at each edge so content dissolves rather than
        // cutting off. The edge only goes fully clear when there's actually
        // content beyond it (so the brand header stays solid at rest).
        LinearGradient(stops: [
            .init(color: canUp ? .clear : .black, location: 0),
            .init(color: .black, location: canUp ? 0.14 : 0),
            .init(color: .black, location: canDown ? 0.86 : 1),
            .init(color: canDown ? .clear : .black, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    private func scrollCaret(_ systemName: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        return Image(systemName: systemName)
            .font(.caption.weight(.bold))
            .foregroundStyle(themeAccent)
            .frame(width: 22, height: 22)
            .background(shape.fill(specialKeyTint ?? Color(.systemGray5)))
            .overlay(shape.strokeBorder(themeAccent, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .padding(10)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var extensionsSection: some View {
        HStack(spacing: 8) {
            Text("Extensions")
                .font(.caption).fontWeight(.semibold).foregroundStyle(specialKeyTextColor)
            Rectangle()
                .fill(themeAccent.opacity(0.4))
                .frame(height: 0.5)
            Button { showExtensionPicker = true } label: {
                Image(systemName: "gearshape")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(specialKeyTextColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)

        ForEach(enabledExtensions) { ext in
            SidebarRow(ext.name, icon: ext.icon, selected: destination == ext.id) {
                select(ext.id)
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Button { select(.clink) } label: {
                HStack(spacing: 10) {
                    LogoMark(color: themeAccent,
                             letterColor: model.settings.resolvedTheme(dark: colorScheme == .dark).keyText.color,
                             cornerFraction: model.settings.keyCornerRadius / model.settings.keyHeight)
                        .frame(width: 32, height: 32)
                    Text("Clink").font(.title3.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button { showBackupSheet = true } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -8)   // keep the glyph edge-aligned despite the larger hitbox
            .accessibilityLabel("Backup & Restore")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption).fontWeight(.semibold).foregroundStyle(specialKeyTextColor)
            Rectangle()
                .fill(themeAccent.opacity(0.4))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private func select(_ d: RootView.SidebarDestination) {
        destination = d
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { sidebar.isOpen = false }
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.themeTextColor) private var themeTextColor
    let label: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    init(_ label: String, icon: String, selected: Bool, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.selected = selected; self.action = action
    }

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22, alignment: .center)
                Text(label).fontWeight(selected ? .semibold : .regular)
                Spacer()
            }
            .foregroundStyle(selected ? Color.white : themeTextColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                if selected {
                    if #available(iOS 26.0, *) {
                        Color.clear.glassEffect(
                            .regular.tint(themeAccent).interactive(),
                            in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        )
                    } else {
                        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                            .fill(themeAccent.opacity(0.12))
                    }
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extension data

private struct ExtEntry: Identifiable {
    let id: RootView.SidebarDestination
    let name: String
    let icon: String
}

/// Tracks whether a `ScrollView` can scroll further up / down and writes the
/// result back through bindings — used to drive the sidebar's edge fades and
/// scroll-affordance carets. Uses `onScrollGeometryChange` (iOS 18+); on older
/// systems the flags simply stay false (no fade/carets).
private struct ScrollEdgeTracker: ViewModifier {
    @Binding var up: Bool
    @Binding var down: Bool

    private struct Edges: Equatable { var up: Bool; var down: Bool }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Edges.self) { geo in
                // visibleRect is in content space and folds in the content insets,
                // so the top/bottom checks are unambiguous at the extremes.
                Edges(up: geo.visibleRect.minY > 1,
                      down: geo.visibleRect.maxY < geo.contentSize.height - 1)
            } action: { _, edges in
                up = edges.up
                down = edges.down
            }
        } else {
            content
        }
    }
}

private let allExtensions: [ExtEntry] = [
    ExtEntry(id: .calculator, name: "Calculator", icon: "numbers.rectangle"),
    ExtEntry(id: .clipboard,  name: "Clipboard",  icon: "clipboard"),
    ExtEntry(id: .emoji,      name: "Emoji",      icon: "face.smiling"),
    ExtEntry(id: .notepad,    name: "Notepad",    icon: "note.text"),
]

// MARK: - Extension picker sheet

private struct ExtensionPickerContent: View {
    @Environment(AppModel.self) private var model

    private var enabledPanelCount: Int {
        [model.settings.clipboardEnabled, model.settings.notepadEnabled,
         model.settings.emojiEnabled, model.settings.calculatorEnabled].filter { $0 }.count
    }

    var body: some View {
        @Bindable var m = model
        VStack(spacing: UX.cardSpacing) {
            ExtensionReorderList(order: $m.settings.extensionOrder)

            CardSection("Panel access") {
                Toggle("Top-left icon", isOn: $m.settings.activateWithIcon)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                Toggle("Slide up on 123", isOn: $m.settings.activateWithSlideUp)
                    .padding(.vertical, UX.rowVPadding)
                if enabledPanelCount >= 2 {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Picker style", selection: $m.settings.panelPickerStyle) {
                            ForEach(PanelPickerStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, UX.rowVPadding)
                }
                Text("Open panels from the suggestion bar or by dragging the 123 key upward.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
            }
        }
    }
}

/// Drag-to-reorder list for extension panels. Uses DragGesture on the handle
/// icon — onDrag/onDrop is unreliable inside a List on iOS.
private struct ExtensionReorderList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Binding var order: [String]

    /// GestureState resets automatically when the gesture ends, preventing stuck drag states.
    @GestureState private var drag: (id: String, y: CGFloat)? = nil

    private let rowH: CGFloat = 52

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.element) { idx, extID in
                if let ext = allExtensions.first(where: { $0.name.lowercased() == extID }) {
                    extRow(ext: ext, extID: extID, idx: idx)
                    if idx < order.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func extRow(ext: ExtEntry, extID: String, idx: Int) -> some View {
        let isDragged = drag?.id == extID
        let yOff = visualOffset(for: idx)
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 44)
                .frame(height: rowH)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 4)
                        .updating($drag) { v, state, _ in
                            state = (id: extID, y: v.translation.height)
                        }
                        .onEnded { v in
                            commitDrag(from: extID, dragY: v.translation.height)
                        }
                )
            toggleRow(extID: extID, name: ext.name, icon: ext.icon)
        }
        .frame(height: rowH)
        .background(isDragged ? Color(.tertiarySystemGroupedBackground) : Color.clear)
        .shadow(color: isDragged ? .black.opacity(0.12) : .clear, radius: 6, y: 3)
        .offset(y: yOff)
        .zIndex(isDragged ? 1 : 0)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: yOff)
    }

    private func visualOffset(for idx: Int) -> CGFloat {
        guard let drag, let fromIdx = order.firstIndex(of: drag.id) else { return 0 }
        let toIdx = clamped(fromIdx + Int((drag.y / rowH).rounded()))
        if order[idx] == drag.id  { return drag.y }
        if fromIdx < toIdx, idx > fromIdx, idx <= toIdx { return -rowH }
        if fromIdx > toIdx, idx >= toIdx, idx < fromIdx { return  rowH }
        return 0
    }

    private func clamped(_ idx: Int) -> Int { max(0, min(order.count - 1, idx)) }

    private func commitDrag(from extID: String, dragY: CGFloat) {
        guard let fromIdx = order.firstIndex(of: extID) else { return }
        let toIdx = clamped(fromIdx + Int((dragY / rowH).rounded()))
        guard fromIdx != toIdx else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            order.move(fromOffsets: IndexSet(integer: fromIdx),
                       toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        }
    }

    @ViewBuilder
    private func toggleRow(extID: String, name: String, icon: String) -> some View {
        let s = Bindable(model).settings
        let binding: Binding<Bool> = {
            switch extID {
            case "calculator": return s.calculatorEnabled
            case "clipboard":  return s.clipboardEnabled
            case "emoji":      return s.emojiEnabled
            case "notepad":    return s.notepadEnabled
            default:           return .constant(false)
            }
        }()
        Toggle(isOn: binding) {
            Label {
                Text(name)
            } icon: {
                Image(systemName: icon).foregroundStyle(themeAccent)
            }
        }
        .padding(.trailing, 16)
    }
}

// MARK: - Clink (setup)

// MARK: - Permissions (onboarding step 2)

/// The keyboard-enable / Full Access guide as a standalone onboarding page,
/// reusing `EnableFlowView`. Top-right button steps on to Localization.
private struct PermissionsView: View {
    @Environment(SidebarState.self) private var sidebar

    var body: some View {
        EnableFlowView(title: "Permissions")
            .navTrailingButton("globe") { sidebar.navigate?(.localization) }
    }
}

private struct ClinkContent: View {
    @Environment(AppModel.self) private var model
    @Environment(SidebarState.self) private var sidebar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardTint) private var cardTint
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.specialKeyTextColor) private var specialKeyTextColor
    @State private var showExtensionPicker = false
    @State private var showBackupSheet = false

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? "Version \(v)" : "Version \(v) (\(b))"
    }

    private struct DestCard {
        let title: String
        let icon: String
        let description: String
        let dest: RootView.SidebarDestination
    }

    private let generalCards: [DestCard] = [
        DestCard(title: "Permissions", icon: "lock.shield",    description: "Enable the keyboard and grant Full Access", dest: .permissions),
        DestCard(title: "Localization", icon: "globe",         description: "Language and dictionary",                  dest: .localization),
        DestCard(title: "Layout",       icon: "textformat.abc", description: "Key arrangement and row options",         dest: .layout),
    ]

    private let customizationCards: [DestCard] = [
        DestCard(title: "Animation",   icon: "wand.and.stars",                              description: "Spring physics and press timing",       dest: .animation),
        DestCard(title: "Automation",  icon: "gearshape.2",                                 description: "Auto-capitalize and smart punctuation", dest: .automation),
        DestCard(title: "Custom Actions", icon: "puzzlepiece.extension",                     description: "Write keyboard actions in Python",      dest: .customActions),
        DestCard(title: "Custom Panels", icon: "square.grid.2x2",                            description: "Build custom keyboard UIs in Python",   dest: .customPanels),
        DestCard(title: "Cursor",      icon: "cursorarrow",                                 description: "Movement style and feel",               dest: .cursor),
        DestCard(title: "Haptics",     icon: "hand.tap",                                    description: "Key press haptic feedback",             dest: .haptics),
        DestCard(title: "Keys",        icon: "keyboard",                                    description: "Size, shape, and backspace repeat",     dest: .keys),
        DestCard(title: "Popups",      icon: "rectangle.portrait.on.rectangle.portrait",    description: "Popup style and Liquid Glass",          dest: .popups),
        DestCard(title: "Sounds",      icon: "speaker.wave.2",                              description: "Sound pack and volume",                 dest: .sounds),
        DestCard(title: "Suggestions", icon: "text.cursor",                                 description: "Autocorrect and suggestion bar",        dest: .suggestions),
        DestCard(title: "Theme",       icon: "paintpalette",                                description: "Colors, materials, and themes",         dest: .theme),
    ]

    private let advancedCards: [DestCard] = [
        DestCard(title: "Hitboxes",    icon: "square.dashed",                                  description: "Touch target size and presets",      dest: .hitboxes),
        DestCard(title: "Overlays",    icon: "square.stack.3d.up",                             description: "Debug overlays",                     dest: .overlays),
        DestCard(title: "Performance", icon: "gauge.with.dots.needle.bottom.50percent",         description: "Suggestion timing and CPU budget",   dest: .performance),
        DestCard(title: "Response",    icon: "timer",                                          description: "Long-press and slide-up timing",     dest: .response),
    ]

    private var extensionCards: [DestCard] {
        model.settings.extensionOrder.compactMap { id in
            switch id {
            case "calculator": return DestCard(title: "Calculator", icon: "numbers.rectangle", description: "Built-in calculator panel",       dest: .calculator)
            case "clipboard":  return DestCard(title: "Clipboard",  icon: "clipboard",         description: "Recent clipboard history",        dest: .clipboard)
            case "emoji":      return DestCard(title: "Emoji",      icon: "face.smiling",      description: "Emoji picker and skin tones",     dest: .emoji)
            case "notepad":    return DestCard(title: "Notepad",    icon: "note.text",         description: "Scratch pad inside the keyboard", dest: .notepad)
            default:           return nil
            }
        }
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UX.cardSpacing) {
                VStack(spacing: 6) {
                    LogoMark(color: themeAccent,
                             letterColor: model.settings.resolvedTheme(dark: colorScheme == .dark).keyText.color,
                             cornerFraction: model.settings.keyCornerRadius / model.settings.keyHeight)
                        .frame(width: 72, height: 72)
                    Text("Clink")
                        .font(.title.weight(.bold))
                    Text(appVersion)
                        .font(.caption).foregroundStyle(specialKeyTextColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                gridSection("General", cards: generalCards)
                gridSection("Customization", cards: customizationCards)
                gridSection("Extensions", cards: extensionCards, gearAction: { showExtensionPicker = true })
                gridSection("Advanced", cards: advancedCards)
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navTrailingButton("ellipsis.circle") { showBackupSheet = true }
        .themePageBackground()
        .themedSheet(isPresented: $showExtensionPicker, title: "Extensions") { ExtensionPickerContent() }
        .themedSheet(isPresented: $showBackupSheet, title: "Backup & Restore") { BackupControls() }
    }

    @ViewBuilder
    private func gridSection(_ title: String, cards: [DestCard], gearAction: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(specialKeyTextColor)
                Rectangle()
                    .fill(themeAccent.opacity(0.4))
                    .frame(height: 0.5)
                if let gearAction {
                    Button(action: gearAction) {
                        Image(systemName: "gearshape")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(specialKeyTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(cards, id: \.title) { card in
                    destCard(card)
                }
            }
        }
    }

    private func destCard(_ card: DestCard) -> some View {
        Button { sidebar.navigate?(card.dest) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: card.icon)
                    .font(.title2)
                    .foregroundStyle(themeAccent)
                    .frame(height: 28, alignment: .center)
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(card.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .padding(12)
            .background(cardTint ?? Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

}

