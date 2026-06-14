/**
 Root view with a collapsible slide-in sidebar. The sidebar overlays the content
 from the left edge; a scrim tap or row selection closes it. Detail navigation
 (Theme editor, Sound picker, etc.) lives inside the per-destination NavigationStack.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import UIKit
import iUXiOS

// MARK: - Theme page background

private struct ResolvedThemeKey: EnvironmentKey {
    /// Default when no theme is injected — matches keyboard factory default.
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
    /// Paint the page background from `resolvedKeyboardTheme` (gradient or solid).
    func themePageBackground() -> some View { modifier(ThemePageBackgroundModifier()) }
}

/// Shared sidebar open/close state, injected via `@Environment` so `DetailHost` can
/// open the sidebar without threading a binding through every content view.
@Observable @MainActor
final class SidebarState {
    var isOpen = false
    /// Incremented when a NavigationLink destination appears; decremented on disappear.
    /// Used to hide the sidebar button when a back button is present.
    var navigationDepth: Int = 0
    /// Sheets triggered from the sidebar but presented at root level so they
    /// render full-width above everything.
    var showExtensionPicker = false
    var showBackupSheet = false
    /// Jump to a destination from inside a content page (the onboarding "next
    /// step" buttons). Wired up by `RootView`.
    var navigate: ((RootView.SidebarDestination) -> Void)?
    /// Last visible section on the home page — persisted so scroll position
    /// is restored when the user navigates away and returns.
    var homeScrollAnchor: String? = nil
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
    /// Increment/decrement `SidebarState.navigationDepth` for overlay nav-button hiding.
    func tracksNavigationDepth() -> some View { modifier(NavDepthModifier()) }
}

// MARK: - Root

/// Root shell: slide-in sidebar over a single detail pane.
///
/// Navigation pattern:
/// - Sidebar row / home card sets `destination`; `DetailHost` swaps the screen
///   inside one `NavigationStack` (push/pop stays per-destination).
/// - Overlay nav buttons (sidebar / home / trailing) sit above content; they
///   hide when `sidebar.navigationDepth > 0` (a pushed screen owns the back chevron).
/// - `sidebar.navigate` lets onboarding step buttons jump destinations without
///   opening the sidebar.
/// - Theme-aware sheets attach inside the ZStack via `SidebarSheetHost` so they
///   inherit `resolvedKeyboardTheme` — outermost modifiers would read WindowGroup defaults.
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

    /// Every screen the sidebar and home card grid can route to.
    enum SidebarDestination: Hashable {
        case clink, permissions, localization, theme, artificialIntelligence
        // Customization placeholders (pages to be built out).
        // Simple-mode merged pages.
        case typing, keys, feel, text
        // Advanced-mode granular pages (same content, one feature each).
        case animation, popups, cursor, gestures, sounds, haptics
        case suggestions, automation, adaptation, keyGeometry, hitboxes, layout
        // Advanced placeholders.
        case overlays, response, performance
        case clipboard, notepad, translate, emoji, calculator
        /// Full-page extension manager (same content as the gear-icon sheet).
        case manageExtensions
        /// The Python extension SDK — author / manage custom keyboard actions.
        case customActions
        /// Custom panels — author / manage full custom keyboard UIs.
        case customPanels
    }

    private let sidebarWidth: CGFloat = 290
    private var sidebarAnim: Animation { Motion.sidebar.animation }

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

            // Sheets triggered from the sidebar live here — inside the ZStack so
            // they inherit the theme environment — rather than as outermost modifiers
            // where @Environment reads come from the parent (WindowGroup), not from
            // the ZStack's .environment(…) chain.
            SidebarSheetHost(sidebar: sidebar)
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
        #if DEBUG
        // Frame-rate meter for hand-tuning animations (`--motion-hud` launch arg).
        .overlay(alignment: .topTrailing) {
            if FeatureFlags.motionHUD { MotionHUD().padding(.trailing, 12) }
        }
        #endif
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

    /// Overlay nav strip: sidebar toggle on home, house icon elsewhere, plus any
    /// destination-specific trailing button from `NavBarState`. Hidden while the
    /// sidebar is open or while a pushed screen owns the back chevron.
    private var navButtonLayer: some View {
        HStack(spacing: 0) {
            Group {
                if destination == .clink {
                    ThemeNavButton(systemName: "sidebar.left") {
                        let dismissedKeyboard = UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        if !dismissedKeyboard {
                            withAnimation(sidebarAnim) { sidebar.isOpen.toggle() }
                        }
                    }
                } else {
                    ThemeNavButton(systemName: "house") {
                        destination = .clink
                    }
                }
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

/// Wraps the active sidebar destination in a `NavigationStack` and injects the
/// resolved keyboard theme into the environment. When `themeApp` is off the app
/// chrome falls back to Liquid Light/Dark defaults instead of the selected theme.
private struct DetailHost: View {
    @Environment(AppModel.self) private var model
    @Environment(SidebarState.self) private var sidebar
    @Environment(\.colorScheme) private var colorScheme
    let destination: RootView.SidebarDestination

    private var resolvedTheme: Theme {
        guard model.settings.themeApp else {
            return colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
        }
        return model.settings.resolvedTheme(dark: colorScheme == .dark)
    }

    /// Standard corner radius used when `themeApp` is off — matches the default
    /// key radius so the app looks consistent with Liquid Light / Dark.
    private var appCornerRadius: Double {
        model.settings.themeApp ? model.settings.keyCornerRadius : 13.0
    }

    var body: some View {
        NavigationStack {
            destinationView
                .navigationBarTitleDisplayMode(.inline)
                .tint(resolvedTheme.accent.color)
                .environment(\.resolvedKeyboardTheme, resolvedTheme)
                .environment(\.cardCornerRadius, appCornerRadius)
                .environment(\.specialKeyTint, resolvedTheme.specialKeyFill.color)
                .environment(\.themeTextColor, resolvedTheme.keyText.color)
                .environment(\.useGlassCards, resolvedTheme.material == .liquidGlass)
                .environment(\.cardTint, resolvedTheme.keyFill.color)
                .environment(\.specialKeyTextColor, resolvedTheme.specialKeyText.color)
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination {
        case .clink:        ClinkContent()
        case .permissions:  PermissionsView()
        case .localization: LocalizationView()
        case .theme:        ThemeEditorView()
        case .artificialIntelligence: ArtificialIntelligenceView()
        case .clipboard:  ClipboardHistoryView()
        case .notepad:    NotepadView()
        case .translate:  TranslateView()
        case .emoji:      EmojiSettingsView()
        case .calculator: CalculatorSettingsView()
        case .manageExtensions: ExtensionManagerPage()
        case .customActions: if FeatureFlags.experimental { ExtensionsView() }
        case .customPanels: if FeatureFlags.experimental { PanelsView() }
        // Placeholder pages — content to be built out.
        case .typing:      TypingView()
        case .keys:        KeysView()
        case .feel:        FeelView()
        case .text:        TextView()
        // Advanced-mode granular pages.
        case .animation:   AnimationPage()
        case .popups:      PopupsPage()
        case .cursor:      CursorPage()
        case .gestures:    GesturesPage()
        case .sounds:      SoundsPage()
        case .haptics:     HapticsPage()
        case .suggestions: SuggestionsPage()
        case .automation:  AutomationPage()
        case .adaptation:  AdaptationPage()
        case .keyGeometry: KeyGeometryPage()
        case .hitboxes:    HitboxesPage()
        case .layout:      LayoutPage()
        case .overlays:     OverlaysView()
        case .performance:  PerformanceView()
        case .response:     ResponseView()
        }
    }
}

// MARK: - Sidebar sheet host

/// Transparent full-screen view placed *inside* the root ZStack so it inherits
/// the theme environment. Sheets attached here get proper theming; the same sheets
/// as outermost modifiers on the ZStack would read from the WindowGroup parent,
/// which has no custom theme environment keys.
private struct SidebarSheetHost: View {
    let sidebar: SidebarState
    @Environment(AppModel.self) private var model

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .themedSheet(isPresented: Binding(get: { sidebar.showExtensionPicker },
                                              set: { sidebar.showExtensionPicker = $0 }),
                         title: "Extensions") {
                ExtensionPickerContent()
            }
            .themedSheet(isPresented: Binding(get: { sidebar.showBackupSheet },
                                              set: { sidebar.showBackupSheet = $0 }),
                         title: "Backup & Restore") {
                BackupControls()
            }
            .themedSheet(isPresented: Binding(get: { model.pendingThemeImport != nil },
                                              set: { if !$0 { model.pendingThemeImport = nil } }),
                         title: "New Theme") {
                if let theme = model.pendingThemeImport {
                    ThemeImportContent(theme: theme)
                }
            }
            .confirmationDialog(
                "Replace your settings with the imported file?",
                isPresented: Binding(get: { model.pendingConfigImport != nil },
                                     set: { if !$0 { model.pendingConfigImport = nil } }),
                titleVisibility: .visible
            ) {
                Button("Replace settings", role: .destructive) { model.confirmConfigImport() }
                Button("Cancel", role: .cancel) { model.pendingConfigImport = nil }
            } message: {
                Text("This will overwrite all your current settings. Your themes are kept.")
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

/// Left drawer: brand header, grouped nav rows, and dynamic extension section.
/// Row tap sets `destination` and closes the sidebar with `Motion.sidebar`.
private struct SidebarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeTextColor) private var themeTextColor
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.specialKeyTint) private var specialKeyTint
    @Environment(\.specialKeyTextColor) private var specialKeyTextColor
    let sidebar: SidebarState
    @Binding var destination: RootView.SidebarDestination
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
        case .translate:  return model.settings.translateEnabled
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
        // Simple = merged tabbed pages; Advanced = one row per feature.
        var rows: [NavItem] = model.settings.advancedSettings
            ? [
                NavItem(title: "Adaptation",  icon: "brain.head.profile",    dest: .adaptation),
                NavItem(title: "Animation",   icon: "wand.and.stars",        dest: .animation),
                NavItem(title: "Automation",  icon: "gearshape.2",           dest: .automation),
                NavItem(title: "Cursor",      icon: "cursorarrow",           dest: .cursor),
                NavItem(title: "Gestures",    icon: "hand.draw",             dest: .gestures),
                NavItem(title: "Haptics",     icon: "hand.tap",              dest: .haptics),
                NavItem(title: "Keys",        icon: "keyboard",              dest: .keyGeometry),
                NavItem(title: "Popups",      icon: "rectangle.portrait.on.rectangle.portrait", dest: .popups),
                NavItem(title: "Sounds",      icon: "speaker.wave.2",        dest: .sounds),
                NavItem(title: "Suggestions", icon: "text.cursor",           dest: .suggestions),
                NavItem(title: "Theme",       icon: "paintpalette",          dest: .theme),
              ]
            : [
                NavItem(title: "Feel",        icon: "hand.tap",              dest: .feel),
                NavItem(title: "Keys",        icon: "keyboard",              dest: .keys),
                NavItem(title: "Text",        icon: "text.cursor",           dest: .text),
                NavItem(title: "Theme",       icon: "paintpalette",          dest: .theme),
                NavItem(title: "Typing",      icon: "wand.and.stars",        dest: .typing),
              ]
        if FeatureFlags.experimental {
            rows += [
                NavItem(title: "Custom Actions", icon: "puzzlepiece.extension", dest: .customActions),
                NavItem(title: "Custom Panels",  icon: "square.grid.2x2",       dest: .customPanels),
            ]
        }
        return rows.sorted { $0.title < $1.title }
    }

    /// Advanced pages, alphabetical. (Placeholders pending build-out.)
    private var advancedRows: [NavItem] {
        // Advanced-only: Hitboxes + the debug Overlays page. Performance +
        // Response are retired from the UI (settings still apply at their stored
        // values). Empty in Simple → the section header is skipped.
        guard model.settings.advancedSettings else { return [] }
        return [
            NavItem(title: "Hitboxes", icon: "square.dashed",      dest: .hitboxes),
            NavItem(title: "Overlays", icon: "square.stack.3d.up", dest: .overlays),
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
                if model.settings.advancedSettings {
                    SidebarRow("Layout", icon: "textformat.abc", selected: destination == .layout) {
                        select(.layout)
                    }
                }
                SidebarRow("Artificial Intelligence", icon: "sparkles", selected: destination == .artificialIntelligence) {
                    select(.artificialIntelligence)
                }

                sectionLabel("Customization")
                ForEach(customizationRows) { row in
                    SidebarRow(row.title, icon: row.icon, selected: destination == row.dest) {
                        select(row.dest)
                    }
                }

                extensionsSection

                if !advancedRows.isEmpty {
                    sectionLabel("Advanced")
                    ForEach(advancedRows) { row in
                        SidebarRow(row.title, icon: row.icon, selected: destination == row.dest) {
                            select(row.dest)
                        }
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
        .animation(Motion.scrollHintFade.animation, value: canScrollUp)
        .animation(Motion.scrollHintFade.animation, value: canScrollDown)
        .foregroundColor(themeTextColor)
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
            Button { sidebar.showExtensionPicker = true } label: {
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
        SidebarRow("Manage", icon: "gearshape", selected: destination == .manageExtensions) {
            select(.manageExtensions)
        }
        .opacity(0.5)
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
            Button { sidebar.showBackupSheet = true } label: {
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
        withAnimation(Motion.sidebar.animation) { sidebar.isOpen = false }
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

private struct DestCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private let allExtensions: [ExtEntry] = [
    ExtEntry(id: .calculator, name: "Calculator", icon: "numbers.rectangle"),
    ExtEntry(id: .clipboard,  name: "Clipboard",  icon: "clipboard"),
    ExtEntry(id: .emoji,      name: "Emoji",      icon: "face.smiling"),
    ExtEntry(id: .notepad,    name: "Notepad",    icon: "note.text"),
    ExtEntry(id: .translate,  name: "Translate",  icon: "character.bubble"),
]

// MARK: - Extension picker sheet

// MARK: - Extension manager page

/// Full-page wrapper around `ExtensionPickerContent` — reached from the
/// "Manage" ghost card/row. The gear-icon sheet continues to work unchanged.
private struct ExtensionManagerPage: View {
    var body: some View {
        ScrollView {
            ExtensionPickerContent()
                .padding(UX.screenPadding)
        }
        .navigationTitle("Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
    }
}

private struct ExtensionPickerContent: View {
    @Environment(AppModel.self) private var model

    private var enabledPanelCount: Int {
        [model.settings.clipboardEnabled, model.settings.notepadEnabled,
         model.settings.emojiEnabled, model.settings.calculatorEnabled].filter { $0 }.count
    }

    var body: some View {
        @Bindable var m = model
        VStack(spacing: UX.cardSpacing) {
            CardSection("Panels") {
                ExtensionReorderList(order: $m.settings.extensionOrder)
            }

            CardSection("Panel access") {
                // Pinned icons stand in for the suggestion bar and never collapse,
                // so the icon-button / show-on-open / animate controls don't apply —
                // hide them to avoid presenting dead options.
                let pinned = m.settings.pinPanelIcons
                    && !m.settings.suggestionsEnabled && enabledPanelCount >= 1
                if !m.settings.suggestionsEnabled && enabledPanelCount >= 1 {
                    ToggleRow("Pin panel icons",
                              subtitle: "Keep the panel icons in the bar permanently, in place of the suggestion bar. Stays put while you type.",
                              isOn: $m.settings.pinPanelIcons)
                    Divider()
                }
                if !pinned {
                    ToggleRow("Top-left icon",
                              subtitle: "Show a panel button in the top-left corner of the keyboard.",
                              isOn: $m.settings.activateWithIcon)
                    if m.settings.activateWithIcon && enabledPanelCount >= 2 {
                        Divider()
                        HStack {
                            Text("Icon picker style")
                            Spacer()
                            Picker("Icon picker style", selection: $m.settings.iconPickerStyle) {
                                ForEach(PanelPickerStyle.allCases) { style in
                                    Text(style.label).tag(style)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, UX.rowVPadding)
                    }
                    if enabledPanelCount >= 2 {
                        Divider()
                        ToggleRow("Show icons on open",
                                  subtitle: "Expand the panel icons automatically when the keyboard appears, until you start typing.",
                                  isOn: $m.settings.autoShowPanelIcons)
                        if m.settings.autoShowPanelIcons {
                            Divider()
                            ToggleRow("Animate icon bar",
                                      subtitle: "Sweep the keyboard height as the icons grow in and collapse. Off snaps instantly so it reads as if nothing moved.",
                                      isOn: $m.settings.animatePanelBarResize)
                        }
                    }
                    Divider()
                }
                ToggleRow("Slide up on 123",
                          subtitle: "Drag up on the 123 key to open the panel picker.",
                          isOn: $m.settings.activateWithSlideUp)
                if m.settings.activateWithSlideUp && enabledPanelCount >= 2 {
                    Divider()
                    HStack {
                        Text("Slide-up picker style")
                        Spacer()
                        Picker("Slide-up picker style", selection: $m.settings.slideUpPickerStyle) {
                            ForEach(PanelPickerStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, UX.rowVPadding)
                }
            }
        }
        // Built-in panels added after a user's `extensionOrder` was first saved
        // aren't in their stored order, so the reorder list above would silently
        // omit them. Append any missing built-ins on appear so every panel is
        // listed and toggleable.
        .onAppear {
            let known = allExtensions.map { $0.name.lowercased() }
            let missing = known.filter { !model.settings.extensionOrder.contains($0) }
            if !missing.isEmpty { model.settings.extensionOrder.append(contentsOf: missing) }
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
        .background(isDragged ? Color(.systemFill) : Color.clear)
        .shadow(color: isDragged ? .black.opacity(0.12) : .clear, radius: 6, y: 3)
        .offset(y: yOff)
        .zIndex(isDragged ? 1 : 0)
        .animation(Motion.dragSnap.animation, value: yOff)
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
        withAnimation(Motion.cardSpring.animation) {
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
            case "translate":  return s.translateEnabled
            default:           return .constant(false)
            }
        }()
        HStack {
            Label {
                Text(name)
            } icon: {
                Image(systemName: icon).foregroundStyle(themeAccent)
            }
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(ThemedToggleStyle())
        }
        .padding(.trailing, 16)
    }
}

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

// MARK: - Clink (setup)

/// Home grid: destination cards, live keyboard preview, and onboarding entry.
/// Card taps set `destination` (same routing as the sidebar). Scroll position is
/// restored via `sidebar.homeScrollAnchor` when returning from a detail screen.
private struct ClinkContent: View {
    @Environment(AppModel.self) private var model
    @Environment(SidebarState.self) private var sidebar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardTint) private var cardTint
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.specialKeyTextColor) private var specialKeyTextColor
    @State private var showExtensionPicker = false
    @State private var showBackupSheet = false
    @State private var showChangelog = false

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
        /// Renders the card with ghost styling (dashed border, no fill).
        var ghost: Bool = false
        /// When set, calls this closure instead of navigating to `dest`.
        var action: (() -> Void)? = nil
    }

    private var generalCards: [DestCard] {
        var cards = [
            DestCard(title: "Permissions", icon: "lock.shield",    description: "Enable the keyboard and grant Full Access", dest: .permissions),
            DestCard(title: "Localization", icon: "globe",         description: "Language and dictionary",                  dest: .localization),
        ]
        // Advanced mode breaks Layout back out into its own page; Simple folds it
        // into the Keys page.
        if model.settings.advancedSettings {
            cards.append(DestCard(title: "Layout", icon: "textformat.abc", description: "Key arrangement and row options", dest: .layout))
        }
        cards.append(DestCard(title: "Artificial Intelligence", icon: "sparkles", description: "On-device Apple Intelligence", dest: .artificialIntelligence))
        return cards
    }

    private var customizationCards: [DestCard] {
        // Simple mode = the merged tabbed pages; Advanced = one card per feature.
        var cards: [DestCard] = model.settings.advancedSettings
            ? [
                DestCard(title: "Adaptation",  icon: "brain.head.profile",                       description: "On-device learning from your typing",   dest: .adaptation),
                DestCard(title: "Animation",   icon: "wand.and.stars",                           description: "Spring physics and press timing",       dest: .animation),
                DestCard(title: "Automation",  icon: "gearshape.2",                              description: "Auto-capitalize and smart punctuation", dest: .automation),
                DestCard(title: "Cursor",      icon: "cursorarrow",                              description: "Movement style and feel",               dest: .cursor),
                DestCard(title: "Gestures",    icon: "hand.draw",                                description: "Swipe typing and the glide trail",      dest: .gestures),
                DestCard(title: "Haptics",     icon: "hand.tap",                                 description: "Key press haptic feedback",             dest: .haptics),
                DestCard(title: "Keys",        icon: "keyboard",                                 description: "Size, shape, and spacing",              dest: .keyGeometry),
                DestCard(title: "Popups",      icon: "rectangle.portrait.on.rectangle.portrait", description: "Popup style and Liquid Glass",         dest: .popups),
                DestCard(title: "Sounds",      icon: "speaker.wave.2",                           description: "Sound pack and volume",                 dest: .sounds),
                DestCard(title: "Suggestions", icon: "text.cursor",                              description: "Autocorrect and suggestion bar",        dest: .suggestions),
                DestCard(title: "Theme",       icon: "paintpalette",                             description: "Colors, materials, and themes",         dest: .theme),
              ]
            : [
                DestCard(title: "Feel",        icon: "hand.tap",                                    description: "Sounds and haptics",                    dest: .feel),
                DestCard(title: "Keys",        icon: "keyboard",                                    description: "Geometry, hitboxes, and layout",        dest: .keys),
                DestCard(title: "Text",        icon: "text.cursor",                                 description: "Suggestions, automation, learning",     dest: .text),
                DestCard(title: "Theme",       icon: "paintpalette",                                description: "Colors, materials, and themes",         dest: .theme),
                DestCard(title: "Typing",      icon: "wand.and.stars",                              description: "Animation, popups, cursor, gestures",   dest: .typing),
              ]
        if FeatureFlags.experimental {
            cards += [
                DestCard(title: "Custom Actions", icon: "puzzlepiece.extension", description: "Write keyboard actions in Python", dest: .customActions),
                DestCard(title: "Custom Panels",  icon: "square.grid.2x2",       description: "Build custom keyboard UIs in Python", dest: .customPanels),
            ]
        }
        return cards
    }

    private var advancedCards: [DestCard] {
        // Advanced-only pages: Hitboxes (folded into Keys in Simple) and the
        // debug Overlays page. Performance + Response are retired from the UI —
        // their settings still drive the keyboard at their stored values, there's
        // just no editing page. Empty in Simple → the section is hidden (see body).
        guard model.settings.advancedSettings else { return [] }
        return [
            DestCard(title: "Hitboxes", icon: "square.dashed",       description: "Touch target size and presets", dest: .hitboxes),
            DestCard(title: "Overlays", icon: "square.stack.3d.up",  description: "Debug overlays",                 dest: .overlays),
        ]
    }

    private var extensionCards: [DestCard] {
        // Only surface extensions the user has actually enabled — a disabled one
        // has nothing to show on its page. (Manage, below, is always present so
        // they can re-enable.)
        let s = model.settings
        var cards = model.settings.extensionOrder.compactMap { id -> DestCard? in
            switch id {
            case "calculator": return s.calculatorEnabled ? DestCard(title: "Calculator", icon: "numbers.rectangle", description: "Built-in calculator panel",       dest: .calculator) : nil
            case "clipboard":  return s.clipboardEnabled  ? DestCard(title: "Clipboard",  icon: "clipboard",         description: "Recent clipboard history",        dest: .clipboard)  : nil
            case "emoji":      return s.emojiEnabled      ? DestCard(title: "Emoji",      icon: "face.smiling",      description: "Emoji picker and skin tones",     dest: .emoji)      : nil
            case "notepad":    return s.notepadEnabled    ? DestCard(title: "Notepad",    icon: "note.text",         description: "Scratch pad inside the keyboard", dest: .notepad)    : nil
            case "translate":  return s.translateEnabled  ? DestCard(title: "Translate",  icon: "character.bubble",   description: "Translate text in the keyboard",   dest: .translate)  : nil
            default:           return nil
            }
        }
        cards.append(DestCard(title: "Manage", icon: "gearshape",
                              description: "Add, remove, and reorder extensions",
                              dest: .manageExtensions, ghost: true))
        return cards
    }

    @State private var cardHeight: CGFloat = 0

    var body: some View {
        @Bindable var sidebar = sidebar
        @Bindable var model = model
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
                .id("header")

                CardSection {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Settings mode", selection: $model.settings.advancedSettings) {
                            Text("Simple").tag(false)
                            Text("Advanced").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Text(model.settings.advancedSettings
                             ? "Advanced: every fine-tune control is shown."
                             : "Simple: just the essentials. Switch to Advanced for fine-tune controls throughout the app.")
                            .font(.caption)
                            .foregroundStyle(specialKeyTextColor)
                    }
                    .padding(.vertical, UX.rowVPadding)
                }
                .id("mode")

                gridSection("General", cards: generalCards).id("general")
                gridSection("Customization", cards: customizationCards).id("customization")
                gridSection("Extensions", cards: extensionCards, gearAction: { showExtensionPicker = true }).id("extensions")
                if !advancedCards.isEmpty {
                    gridSection("Advanced", cards: advancedCards).id("advanced")
                }

                VStack(spacing: 10) {
                    Button { showChangelog = true } label: {
                        Text("CHANGELOG")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)

                    // Required attribution for the bundled prediction data
                    // (see Tools/wordlists/README.md for sources + licenses).
                    Text("Dictionaries: FrequencyWords (CC-BY-SA 4.0) · Tatoeba (CC-BY 2.0 FR)")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .id("footer")
            }
            .padding(UX.screenPadding)
        }
        .scrollPosition(id: $sidebar.homeScrollAnchor)
        .onPreferenceChange(DestCardHeightKey.self) { cardHeight = $0 }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navTrailingButton("ellipsis.circle") { showBackupSheet = true }
        .themePageBackground()
        .themedSheet(isPresented: $showExtensionPicker, title: "Extensions") { ExtensionPickerContent() }
        .themedSheet(isPresented: $showBackupSheet, title: "Backup & Restore") { BackupControls() }
        .themedSheet(isPresented: $showChangelog, title: "Changelog") { ChangelogContent() }
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

            // Non-lazy pairs so every card is always rendered and measured,
            // which lets DestCardHeightKey capture the true global maximum
            // on the very first layout pass — LazyVGrid would miss off-screen rows.
            VStack(spacing: 10) {
                ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { i in
                    HStack(spacing: 10) {
                        destCard(cards[i])
                        if i + 1 < cards.count {
                            destCard(cards[i + 1])
                        } else {
                            // Odd-count section: phantom cell keeps the real card
                            // at the correct 50 % width instead of stretching full.
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func destCard(_ card: DestCard) -> some View {
        let isGhost = card.ghost
        return Button { card.action?() ?? sidebar.navigate?(card.dest) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: card.icon)
                    .font(.title2)
                    .foregroundStyle(isGhost ? AnyShapeStyle(.secondary) : AnyShapeStyle(themeAccent))
                    .frame(height: 28, alignment: .center)
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isGhost ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(card.description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(isGhost ? Color.clear : (cardTint ?? Color(.secondarySystemBackground)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isGhost ? Color.primary.opacity(0.18) : Color.primary.opacity(UX.Glass.outlineOpacity),
                        style: isGhost ? StrokeStyle(lineWidth: 1, dash: [5, 3]) : StrokeStyle(lineWidth: UX.Glass.outlineWidth)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: cardHeight > 0 ? cardHeight : nil)
        .background(isGhost ? nil : GeometryReader { geo in
            Color.clear.preference(key: DestCardHeightKey.self, value: geo.size.height)
        })
    }

}

// MARK: - Changelog sheet

/// Renders the build-time-baked CHANGELOG.md (`ChangelogData.markdown`, generated
/// by `make changelog`) as a lightweight formatted list. We don't use a full
/// Markdown engine: `AttributedString(markdown:)` handles inline styling
/// (**bold**, `code`, [links]) per line, while block structure (headings,
/// bullets, blank lines) is laid out by hand.
private struct ChangelogContent: View {
    private enum Block {
        case heading(String, level: Int)
        case bullet(AttributedString)
        case text(AttributedString)
        case spacer
    }

    private var blocks: [Block] {
        ChangelogData.markdown.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return .spacer }
            if trimmed.hasPrefix("### ") { return .heading(String(trimmed.dropFirst(4)), level: 3) }
            if trimmed.hasPrefix("## ")  { return .heading(String(trimmed.dropFirst(3)), level: 2) }
            if trimmed.hasPrefix("# ")   { return .heading(String(trimmed.dropFirst(2)), level: 1) }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return .bullet(inline(String(trimmed.dropFirst(2))))
            }
            return .text(inline(trimmed))
        }
    }

    /// Inline-only markdown → AttributedString. `.inlineOnlyPreservingWhitespace`
    /// keeps a line's text intact while still styling bold/code/links.
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let s, let level):
                    Text(s)
                        .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(level >= 3 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .padding(.top, level <= 2 ? 8 : 2)
                case .bullet(let a):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.tertiary)
                        Text(a).font(.callout)
                    }
                case .text(let a):
                    Text(a).font(.callout).foregroundStyle(.secondary)
                case .spacer:
                    Color.clear.frame(height: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(.accentColor)
    }
}

