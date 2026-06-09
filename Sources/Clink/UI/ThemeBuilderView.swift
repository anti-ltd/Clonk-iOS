/**
 Custom theme editor sheet. Also houses `GradientEditorView`, a nested sheet for
 building multi-stop background and key-background gradients.
 */
import SwiftUI
import UIKit
import iUXiOS
import PhotosUI

/// Create or edit a custom theme. Presented as a sheet from the theme picker.
/// Every change updates the live `KeyboardPreview` at the top, and Save upserts
/// the theme into `settings.customThemes` (which travels to the extension).
struct ThemeBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cardCornerRadius) private var cardCornerRadius

    @State private var draft: Theme
    /// The background Photos pick in flight, if any.
    @State private var photoItem: PhotosPickerItem?
    /// The per-key-image Photos pick in flight, if any (glass themes).
    @State private var keyPhotoItem: PhotosPickerItem?

    /// The background / key-image photos this theme had when the editor opened.
    /// Lets us tell a freshly-picked-but-unsaved image (safe to delete on cancel /
    /// re-pick) from one already persisted on the saved theme (left alone).
    private let originalImageID: String?
    private let originalKeyImageID: String?

    // Gradient editor state
    @State private var showBgGradientEditor = false
    @State private var editingBgGradient: ThemeGradient?
    @State private var showKeyGradientEditor = false
    @State private var editingKeyGradient: ThemeGradient?

    @State private var colorPicker = ColorPickerPresenter()

    init(theme: Theme) {
        _draft = State(initialValue: theme)
        originalImageID = theme.backgroundImageID
        originalKeyImageID = theme.keyImageID
    }

    /// True once this theme exists in the saved list — i.e. we're editing, not
    /// creating. Gates the Delete button.
    private var isExisting: Bool {
        model.settings.customThemes.contains { $0.id == draft.id }
    }

    /// The user's current settings with the draft theme injected + selected, so
    /// the preview renders exactly what the keyboard will.
    private var previewSettings: KeyboardSettings {
        var s = model.settings
        s.matchSystemAppearance = false
        s.themeID = draft.id
        // Always paint the background in the editor preview so the colour/photo
        // being edited is visible, even when the global switch is currently off.
        s.backgroundVisible = true
        if let i = s.customThemes.firstIndex(where: { $0.id == draft.id }) {
            s.customThemes[i] = draft
        } else {
            s.customThemes.append(draft)
        }
        return s
    }

    var body: some View {
        NavigationStack {
            TabbedPreviewLayout(settings: previewSettings,
                                previewColorScheme: draft.isDark ? .dark : .light, tabs: [
                PreviewTab("General") {
                    styleCard
                    if draft.material == .liquidGlass { glassCard }
                },
                PreviewTab("Font") {
                    fontCard
                },
                PreviewTab("Keys") {
                    colorsCard
                    if draft.material == .liquidGlass {
                        keyImageCard
                    }
                },
                PreviewTab("Background") {
                    backgroundCard
                },
            ])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: photoItem) { _, item in importPhoto(item) }
            .onChange(of: keyPhotoItem) { _, item in importKeyPhoto(item) }
            .sheet(isPresented: $showBgGradientEditor) {
                if let g = editingBgGradient {
                    GradientEditorView(initial: g) { draft.backgroundGradient = $0 }
                }
            }
            .sheet(isPresented: $showKeyGradientEditor) {
                if let g = editingKeyGradient {
                    GradientEditorView(initial: g) { draft.keyGradient = $0 }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { customNavBar }
        }
        // Environment on the NavigationStack so both page content AND the color
        // picker overlay share the same theme values.
        .tint(draft.accent.color)
        .fontDesign(draft.keyFontDesign.fontDesign)
        .environment(\.resolvedKeyboardTheme, draft)
        .environment(\.cardTint, draft.keyFill.color)
        .environment(\.specialKeyTint, draft.specialKeyFill.color)
        .environment(\.cardCornerRadius, previewSettings.keyCornerRadius)
        .environment(\.useGlassCards, draft.material == .liquidGlass)
        .environment(\.colorPickerPresenter, colorPicker)
        .themedColorPicker(colorPicker)
    }

    private var customNavBar: some View {
        HStack {
            Button("Cancel") { cancel() }
                .foregroundStyle(Color.primary)
                .buttonStyle(ThemeNavTextButtonStyle(
                    useGlass: false,
                    cornerRadius: min(cardCornerRadius, 22),
                    fill: draft.specialKeyFill.color,
                    accent: draft.accent.color))
            Spacer()
            Text(isExisting ? "Edit Theme" : "New Theme")
                .font(.headline)
            Spacer()
            Button("Save") { save() }
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .buttonStyle(ThemeNavTextButtonStyle(
                    useGlass: false,
                    cornerRadius: min(cardCornerRadius, 22),
                    fill: draft.accent.color,
                    accent: draft.accent.color))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .frame(height: 54)
    }

    private var styleCard: some View {
        CardSection("Style") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Material").foregroundStyle(.secondary).font(.subheadline)
                ThemedChipPicker(
                    options: [("Solid", KeyMaterial.solid), ("Liquid Glass", KeyMaterial.liquidGlass)],
                    selection: $draft.material,
                    accent: draft.accent.color,
                    inactive: draft.specialKeyFill.color)
            }
            .padding(.vertical, UX.rowVPadding)
            Divider()
            ToggleRow("Dark theme",
                      subtitle: "Tints the status bar to match and sets the Liquid Glass fallback.",
                      isOn: $draft.isDark)
        }
    }

    private var fontCard: some View {
        CardSection("Font") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Design").foregroundStyle(.secondary).font(.subheadline)
                ThemedChipPicker(
                    options: ThemeFontDesign.allCases.map { ($0.label, $0) },
                    selection: $draft.keyFontDesign,
                    accent: draft.accent.color,
                    inactive: draft.specialKeyFill.color)
            }
            .padding(.vertical, UX.rowVPadding)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Weight").foregroundStyle(.secondary).font(.subheadline)
                ThemedChipPicker(
                    options: ThemeFontWeight.allCases.map { ($0.label, $0) },
                    selection: $draft.keyFontWeight,
                    accent: draft.accent.color,
                    inactive: draft.specialKeyFill.color,
                    fillWidth: false)
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    /// Fine-tuning for the Liquid Glass look — variant, tint strength, and the
    /// interactive lens. Shown only for glass themes.
    private var glassCard: some View {
        CardSection("Glass") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Variant").foregroundStyle(.secondary).font(.subheadline)
                ThemedChipPicker(
                    options: GlassVariant.allCases.map { ($0.label, $0) },
                    selection: $draft.glassVariant,
                    accent: draft.accent.color,
                    inactive: draft.specialKeyFill.color)
            }
            .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Tint strength", value: $draft.glassTintStrength,
                      in: 0...1, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
            Divider()
            ToggleRow("Interactive glass",
                      subtitle: "Warp the glass under your finger as you press each key, like the shift key.",
                      isOn: $draft.glassInteractive)
        }
    }

    /// The theme's backdrop — solid colour, gradient, or photo. Priority (highest
    /// first): photo → gradient → colour. Only visible when the global "Show
    /// background" switch is on.
    private var backgroundCard: some View {
        CardSection("Background") {
            colorRow("Colour", \.background)
            Divider()
            backgroundGradientRow
            Divider()
            photoRow
        }
    }

    @ViewBuilder private var backgroundGradientRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                backgroundGradientThumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.backgroundGradient == nil ? "No gradient" : "Gradient")
                        .font(.subheadline.weight(.medium))
                    Text("A gradient fills the keyboard behind the keys, overriding the colour.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: UX.cardSpacing) {
                Button {
                    editingBgGradient = draft.backgroundGradient ?? .seed(from: draft.background)
                    showBgGradientEditor = true
                } label: {
                    Label(draft.backgroundGradient == nil ? "Add Gradient" : "Edit",
                          systemImage: "paintpalette")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ThemedFillButtonStyle(fill: draft.accent.color, corner: cardCornerRadius))
                if draft.backgroundGradient != nil {
                    Button(role: .destructive) { draft.backgroundGradient = nil } label: {
                        Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ThemedFillButtonStyle(fill: .red, corner: cardCornerRadius))
                }
            }
        }
        .padding(.vertical, UX.rowVPadding)
    }

    @ViewBuilder private var backgroundGradientThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: max(4, cardCornerRadius - 4), style: .continuous)
        Group {
            if let gradient = draft.backgroundGradient {
                gradient.makeView()
            } else {
                shape.fill(draft.specialKeyFill.color)
                    .overlay(Image(systemName: "paintpalette").foregroundStyle(draft.specialKeyText.color))
            }
        }
        .frame(width: 52, height: 38)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
    }

    @ViewBuilder private var photoRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                backgroundThumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.backgroundImageID == nil ? "No photo" : "Photo")
                        .font(.subheadline.weight(.medium))
                    Text("A photo fills the keyboard behind the keys and overrides the gradient.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: UX.cardSpacing) {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label(draft.backgroundImageID == nil ? "Import Photo" : "Replace",
                          systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ThemedFillButtonStyle(fill: draft.accent.color, corner: cardCornerRadius))
                if draft.backgroundImageID != nil {
                    Button(role: .destructive) { removePhoto() } label: {
                        Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ThemedFillButtonStyle(fill: .red, corner: cardCornerRadius))
                }
            }
        }
        .padding(.vertical, UX.rowVPadding)
    }

    /// A small preview of the chosen photo (or a placeholder tile).
    @ViewBuilder private var backgroundThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: max(4, cardCornerRadius - 4), style: .continuous)
        Group {
            if let id = draft.backgroundImageID,
               let image = ThemeBackgroundStore.shared.image(for: id) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                shape.fill(draft.specialKeyFill.color)
                    .overlay(Image(systemName: "photo").foregroundStyle(draft.specialKeyText.color))
            }
        }
        .frame(width: 52, height: 38)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
    }

    /// Liquid-Glass only: a photo or gradient laid behind the key area so each key
    /// reveals its slice and the glass refracts it. Photo overrides gradient.
    private var keyImageCard: some View {
        CardSection("Key background") {
            keyGradientRow
            Divider()
            keyPhotoRow
        }
    }

    @ViewBuilder private var keyGradientRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                keyGradientThumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.keyGradient == nil ? "No gradient" : "Gradient")
                        .font(.subheadline.weight(.medium))
                    Text("A gradient fills behind the keys, refracted through the glass.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: UX.cardSpacing) {
                Button {
                    editingKeyGradient = draft.keyGradient ?? .seed(from: draft.background)
                    showKeyGradientEditor = true
                } label: {
                    Label(draft.keyGradient == nil ? "Add Gradient" : "Edit",
                          systemImage: "paintpalette")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ThemedFillButtonStyle(fill: draft.accent.color, corner: cardCornerRadius))
                if draft.keyGradient != nil {
                    Button(role: .destructive) { draft.keyGradient = nil } label: {
                        Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ThemedFillButtonStyle(fill: .red, corner: cardCornerRadius))
                }
            }
        }
        .padding(.vertical, UX.rowVPadding)
    }

    @ViewBuilder private var keyGradientThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: max(4, cardCornerRadius - 4), style: .continuous)
        Group {
            if let gradient = draft.keyGradient {
                gradient.makeView()
            } else {
                shape.fill(draft.specialKeyFill.color)
                    .overlay(Image(systemName: "paintpalette").foregroundStyle(draft.specialKeyText.color))
            }
        }
        .frame(width: 52, height: 38)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
    }

    @ViewBuilder private var keyPhotoRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                keyImageThumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.keyImageID == nil ? "No photo" : "Photo")
                        .font(.subheadline.weight(.medium))
                    Text("A photo fills behind the keys and overrides the gradient.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: UX.cardSpacing) {
                PhotosPicker(selection: $keyPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Label(draft.keyImageID == nil ? "Import Photo" : "Replace",
                          systemImage: "square.grid.3x3.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ThemedFillButtonStyle(fill: draft.accent.color, corner: cardCornerRadius))
                if draft.keyImageID != nil {
                    Button(role: .destructive) { removeKeyPhoto() } label: {
                        Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ThemedFillButtonStyle(fill: .red, corner: cardCornerRadius))
                }
            }
        }
        .padding(.vertical, UX.rowVPadding)
    }

    @ViewBuilder private var keyImageThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: max(4, cardCornerRadius - 4), style: .continuous)
        Group {
            if let id = draft.keyImageID,
               let image = ThemeBackgroundStore.shared.image(for: id) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                shape.fill(draft.specialKeyFill.color)
                    .overlay(Image(systemName: "square.grid.3x3").foregroundStyle(draft.specialKeyText.color))
            }
        }
        .frame(width: 52, height: 38)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
    }

    private var colorsCard: some View {
        CardSection("Colors") {
            colorRow("Key fill", \.keyFill)
            Divider()
            colorRow("Key text", \.keyText)
            Divider()
            colorRow("Function-key fill", \.specialKeyFill)
            Divider()
            colorRow("Function-key text", \.specialKeyText)
            Divider()
            colorRow("Accent / pressed", \.accent)
        }
    }

    private func colorRow(_ label: String, _ keyPath: WritableKeyPath<Theme, RGBA>) -> some View {
        let binding = Binding(
            get: { draft[keyPath: keyPath].color },
            set: { draft[keyPath: keyPath] = RGBA($0) }
        )
        return HStack {
            Text(label)
            Spacer(minLength: 12)
            ColorSwatchButton(color: binding, width: 56, height: 30)
        }
        .padding(.vertical, UX.rowVPadding)
    }

    /// Load the picked photo, downscale it to a keyboard-sized JPEG, store it in
    /// the App Group, and point the draft at it. Done eagerly (not on Save) so the
    /// live preview shows the photo immediately. A superseded unsaved pick is
    /// cleaned up so re-picking doesn't leak files.
    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = ThemeBackgroundStore.downscaledJPEG(from: data) else { return }
            await MainActor.run {
                discardUnsavedImage()
                draft.backgroundImageID = model.saveBackgroundImage(jpeg)
            }
        }
    }

    private func removePhoto() {
        discardUnsavedImage()
        draft.backgroundImageID = nil
    }

    /// As `importPhoto`, but for the per-key glass image.
    private func importKeyPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = ThemeBackgroundStore.downscaledJPEG(from: data) else { return }
            await MainActor.run {
                discardUnsavedKeyImage()
                draft.keyImageID = model.saveBackgroundImage(jpeg)
            }
        }
    }

    private func removeKeyPhoto() {
        discardUnsavedKeyImage()
        draft.keyImageID = nil
    }

    /// Delete the draft's current background image *iff* it was picked in this
    /// session and not yet committed to the saved theme — never the persisted one.
    private func discardUnsavedImage() {
        if let current = draft.backgroundImageID, current != originalImageID {
            ThemeBackgroundStore.shared.delete(id: current)
        }
    }

    private func discardUnsavedKeyImage() {
        if let current = draft.keyImageID, current != originalKeyImageID {
            ThemeBackgroundStore.shared.delete(id: current)
        }
    }

    private func cancel() {
        discardUnsavedImage()
        discardUnsavedKeyImage()
        dismiss()
    }

    private func save() {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = "My Theme"
        }
        model.saveCustomTheme(draft)
        // Select the freshly-saved theme so the user sees it take effect.
        if model.settings.matchSystemAppearance {
            if draft.isDark { model.settings.darkThemeID = draft.id }
            else { model.settings.lightThemeID = draft.id }
        } else {
            model.settings.themeID = draft.id
        }
        dismiss()
    }
}

// MARK: - Gradient editor

/// Full-screen gradient editor sheet. Edits a local copy of `ThemeGradient` and
/// calls `onSave` with the result when the user taps Done; Cancel discards.
struct GradientEditorView: View {
    let onSave: (ThemeGradient) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @State private var draft: ThemeGradient
    @State private var colorPicker = ColorPickerPresenter()

    init(initial: ThemeGradient, onSave: @escaping (ThemeGradient) -> Void) {
        _draft = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    preview
                    typeCard
                    if draft.type != .radial { angleCard }
                    stopsCard
                }
                .padding(.horizontal, UX.screenPadding)
                .padding(.vertical, UX.cardSpacing)
            }
            .background(.clear)
            .navigationTitle("Gradient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(draft); dismiss() }
                }
            }
        }
        .environment(\.colorPickerPresenter, colorPicker)
        .themedColorPicker(colorPicker)
    }

    private var preview: some View {
        draft.makeView()
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private var typeCard: some View {
        CardSection("Type") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: $draft.type) {
                    ForEach(GradientType.allCases) { t in Text(t.label).tag(t) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    private var angleCard: some View {
        CardSection("Angle") {
            SliderRow("Rotation", value: $draft.rotation, in: 0...360, step: 1) {
                "\(Int($0.rounded()))°"
            }
        }
    }

    private var stopsCard: some View {
        CardSection("Stops") {
            ForEach($draft.stops) { $stop in
                stopRow(stop: $stop)
                if stop.id != draft.stops.last?.id { Divider() }
            }
            Divider()
            Button {
                let pos = nextStopPosition()
                draft.stops.append(GradientStop(color: interpolatedColor(at: pos), position: pos))
                draft.stops.sort { $0.position < $1.position }
            } label: {
                Label("Add Stop", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    @ViewBuilder private func stopRow(stop: Binding<GradientStop>) -> some View {
        HStack(spacing: 12) {
            stopSwatch(Binding(
                get: { stop.wrappedValue.color.color },
                set: { stop.color.wrappedValue = RGBA($0) }
            ))

            Slider(value: stop.position, in: 0...1, step: 0.01)

            Text("\(Int((stop.wrappedValue.position * 100).rounded()))%")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)

            if draft.stops.count > 2 {
                Button {
                    let id = stop.wrappedValue.id
                    draft.stops.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, UX.rowVPadding)
    }

    private func stopSwatch(_ binding: Binding<Color>) -> some View {
        ColorSwatchButton(color: binding, width: 36, height: 36)
    }

    /// Position for a new stop: midpoint of the largest gap between existing stops.
    private func nextStopPosition() -> Double {
        let sorted = draft.stops.map(\.position).sorted()
        guard sorted.count >= 2 else { return 0.5 }
        var best = (pos: 0.0, gap: 0.0)
        for i in 0..<sorted.count - 1 {
            let gap = sorted[i + 1] - sorted[i]
            if gap > best.gap { best = (sorted[i] + gap / 2, gap) }
        }
        return best.pos
    }

    /// Color interpolated between the two nearest stops at `position`.
    private func interpolatedColor(at position: Double) -> RGBA {
        let sorted = draft.stops.sorted { $0.position < $1.position }
        guard let lo = sorted.last(where: { $0.position <= position }),
              let hi = sorted.first(where: { $0.position >= position }),
              lo.position != hi.position else {
            return sorted.first?.color ?? RGBA(0.5, 0.5, 0.5, 1)
        }
        let t = (position - lo.position) / (hi.position - lo.position)
        return RGBA(
            lo.color.r + (hi.color.r - lo.color.r) * t,
            lo.color.g + (hi.color.g - lo.color.g) * t,
            lo.color.b + (hi.color.b - lo.color.b) * t,
            lo.color.a + (hi.color.a - lo.color.a) * t
        )
    }
}

// MARK: - Color picker presenter (environment-threaded state)

@Observable @MainActor
final class ColorPickerPresenter {
    var isPresented = false
    private var getter: (() -> Color)?
    private var setter: ((Color) -> Void)?

    var color: Color {
        get { getter?() ?? .white }
        set { setter?(newValue) }
    }

    func present(_ binding: Binding<Color>) {
        getter = { binding.wrappedValue }
        setter = { binding.wrappedValue = $0 }
        isPresented = true
    }

    func dismiss() { isPresented = false }
}

private struct ColorPickerPresenterKey: EnvironmentKey {
    static let defaultValue: ColorPickerPresenter? = nil
}

extension EnvironmentValues {
    var colorPickerPresenter: ColorPickerPresenter? {
        get { self[ColorPickerPresenterKey.self] }
        set { self[ColorPickerPresenterKey.self] = newValue }
    }
}

// MARK: - Swatch button

private struct ColorSwatchButton: View {
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.colorPickerPresenter) private var presenter
    @Binding var color: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: max(2, cardCornerRadius - 4), style: .continuous)
        Button { presenter?.present($color) } label: {
            shape.fill(color)
                .frame(width: width, height: height)
                .overlay(shape.strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Themed color picker overlay (wraps the general ThemedSheet)

extension View {
    func themedColorPicker(_ presenter: ColorPickerPresenter) -> some View {
        modifier(ThemedColorPickerModifier(presenter: presenter))
    }
}

private struct ThemedColorPickerModifier: ViewModifier {
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    let presenter: ColorPickerPresenter

    func body(content: Content) -> some View {
        content.overlay {
            if presenter.isPresented {
                ThemedSheetOverlay(
                    cornerRadius: cardCornerRadius,
                    title: "Color",
                    maxHeightFraction: 0.42,
                    onDismiss: { withAnimation(.spring(response: 0.35)) { presenter.dismiss() } }
                ) {
                    ColorPickerContent(presenter: presenter)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: presenter.isPresented)
    }
}

// MARK: - HSB picker content

private struct ColorPickerContent: View {
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    let presenter: ColorPickerPresenter

    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1
    @State private var alpha: Double = 1

    private var current: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness, opacity: alpha)
    }

    var body: some View {
        VStack(spacing: 20) {
            preview
            sliders
            presets
        }
        .onAppear { loadFrom(presenter.color) }
        .onChange(of: hue)        { _, _ in presenter.color = current }
        .onChange(of: saturation) { _, _ in presenter.color = current }
        .onChange(of: brightness) { _, _ in presenter.color = current }
        .onChange(of: alpha)      { _, _ in presenter.color = current }
    }

    private func loadFrom(_ c: Color) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h); saturation = Double(s); brightness = Double(b); alpha = Double(a)
    }

    // Rows of presets — each row is shown as a full-width evenly-spaced HStack.
    private static let presetRows: [[Color]] = [
        // Neutrals
        [.white, Color(white: 0.93), Color(white: 0.82), Color(white: 0.68),
         Color(white: 0.50), Color(white: 0.32), Color(white: 0.18), Color(white: 0.08), .black],
        // Reds / oranges
        [Color(hex: "FF8787"), Color(hex: "FF6B6B"), Color(hex: "FA5252"),
         Color(hex: "FF8E53"), Color(hex: "FD7E14"), Color(hex: "E8590C"),
         Color(hex: "D9480F"), Color(hex: "B34000"), Color(hex: "7D2E00")],
        // Yellows / amber
        [Color(hex: "FFE066"), Color(hex: "FFD43B"), Color(hex: "FCC419"),
         Color(hex: "FAB005"), Color(hex: "F59F00"), Color(hex: "E67700"),
         Color(hex: "FFEC99"), Color(hex: "FFD8A8"), Color(hex: "FFA94D")],
        // Blues
        [Color(hex: "A5D8FF"), Color(hex: "74C0FC"), Color(hex: "4DABF7"),
         Color(hex: "339AF0"), Color(hex: "228BE6"), Color(hex: "1971C2"),
         Color(hex: "1864AB"), Color(hex: "145591"), Color(hex: "0C4A8A")],
        // Greens
        [Color(hex: "B2F2BB"), Color(hex: "8CE99A"), Color(hex: "51CF66"),
         Color(hex: "2F9E44"), Color(hex: "1E7E34"), Color(hex: "38D9A9"),
         Color(hex: "20C997"), Color(hex: "0CA678"), Color(hex: "087F5B")],
        // Purples / pinks
        [Color(hex: "EEB4F7"), Color(hex: "E599F7"), Color(hex: "CC5DE8"),
         Color(hex: "AE3EC9"), Color(hex: "862E9C"), Color(hex: "F783AC"),
         Color(hex: "E64980"), Color(hex: "C2255C"), Color(hex: "A61E4D")],
        // Translucent whites & blacks
        [Color.white.opacity(0.9), Color.white.opacity(0.75), Color.white.opacity(0.55),
         Color.white.opacity(0.35), Color.white.opacity(0.15),
         Color.black.opacity(0.15), Color.black.opacity(0.35),
         Color.black.opacity(0.55), Color.black.opacity(0.75)],
    ]

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                ForEach(Self.presetRows.indices, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(Self.presetRows[row].indices, id: \.self) { col in
                            presetSwatch(Self.presetRows[row][col])
                        }
                    }
                }
            }
        }
    }

    private func presetSwatch(_ c: Color) -> some View {
        let r = max(2, cardCornerRadius - 8)
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        return Button { applyColor(c) } label: {
            ZStack {
                CheckerboardView().clipShape(shape)
                shape.fill(c)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay(shape.strokeBorder(.secondary.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func applyColor(_ c: Color) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
        alpha = Double(a)
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        return ZStack {
            CheckerboardView()
                .clipShape(shape)
            shape.fill(current)
        }
        .frame(height: 56)
        .overlay(shape.strokeBorder(.secondary.opacity(0.2), lineWidth: 0.5))
    }

    private var sliders: some View {
        VStack(spacing: 14) {
            GradientSlider(value: $hue, cornerRadius: cardCornerRadius, gradient: LinearGradient(
                colors: stride(from: 0.0, through: 1.0, by: 1.0/11).map {
                    Color(hue: $0, saturation: 1, brightness: 1)
                },
                startPoint: .leading, endPoint: .trailing))

            GradientSlider(value: $saturation, cornerRadius: cardCornerRadius, gradient: LinearGradient(
                colors: [Color(hue: hue, saturation: 0, brightness: brightness),
                         Color(hue: hue, saturation: 1, brightness: brightness)],
                startPoint: .leading, endPoint: .trailing))

            GradientSlider(value: $brightness, cornerRadius: cardCornerRadius, gradient: LinearGradient(
                colors: [Color(hue: hue, saturation: saturation, brightness: 0),
                         Color(hue: hue, saturation: saturation, brightness: 1)],
                startPoint: .leading, endPoint: .trailing))

            ZStack {
                CheckerboardView()
                    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                    .frame(height: 28)
                GradientSlider(value: $alpha, cornerRadius: cardCornerRadius, gradient: LinearGradient(
                    colors: [current.opacity(0), current.opacity(1)],
                    startPoint: .leading, endPoint: .trailing))
            }
        }
    }
}

private struct GradientSlider: View {
    @Binding var value: Double
    var cornerRadius: CGFloat = 14
    let gradient: LinearGradient

    var body: some View {
        GeometryReader { geo in
            let trackW = geo.size.width
            let thumbX = value * (trackW - 28) + 14
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(gradient)
                    .frame(height: 28)
                RoundedRectangle(cornerRadius: max(4, cornerRadius - 4), style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: 28, height: 28)
                    .offset(x: thumbX - 14)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = max(0, min(1, (drag.location.x - 14) / (trackW - 28)))
            })
        }
        .frame(height: 28)
    }
}

private struct CheckerboardView: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 6
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for col in 0..<cols {
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell,
                                     width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color((row + col) % 2 == 0 ? .white : Color(white: 0.8)))
                }
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                          .prefix(6), radix: 16) ?? 0xFFFFFF
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >>  8) & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}
