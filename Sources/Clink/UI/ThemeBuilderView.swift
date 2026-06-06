import SwiftUI
import iUXiOS
import PhotosUI

/// Create or edit a custom theme. Presented as a sheet from the theme picker.
/// Every change updates the live `KeyboardPreview` at the top, and Save upserts
/// the theme into `settings.customThemes` (which travels to the extension).
struct ThemeBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

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
            // Pinned preview + segmented tabs, just like the Layout/Keys editor:
            // the keyboard stays put while the fields scroll under it.
            TabbedPreviewLayout(settings: previewSettings, tabs: [
                PreviewTab("Style") {
                    styleCard
                    fontCard
                    if draft.material == .liquidGlass { glassCard }
                    if isExisting { deleteButton }
                },
                PreviewTab("Colors") {
                    backgroundCard
                    colorsCard
                    if draft.material == .liquidGlass {
                        keyImageCard
                        glassHint
                    }
                },
            ])
            .navigationTitle(isExisting ? "Edit Theme" : "New Theme")
            .navigationBarTitleDisplayMode(.inline)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private var styleCard: some View {
        CardSection("Style") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Material").foregroundStyle(.secondary).font(.subheadline)
                Picker("Material", selection: $draft.material) {
                    Text("Solid").tag(KeyMaterial.solid)
                    Text("Liquid Glass").tag(KeyMaterial.liquidGlass)
                }
                .pickerStyle(.segmented)
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
                Picker("Design", selection: $draft.keyFontDesign) {
                    ForEach(ThemeFontDesign.allCases) { d in Text(d.label).tag(d) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, UX.rowVPadding)
            Divider()
            Picker("Weight", selection: $draft.keyFontWeight) {
                ForEach(ThemeFontWeight.allCases) { w in Text(w.label).tag(w) }
            }
            .padding(.vertical, 2)
        }
    }

    /// Fine-tuning for the Liquid Glass look — variant, tint strength, and the
    /// interactive lens. Shown only for glass themes.
    private var glassCard: some View {
        CardSection("Glass") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Variant").foregroundStyle(.secondary).font(.subheadline)
                Picker("Variant", selection: $draft.glassVariant) {
                    ForEach(GlassVariant.allCases) { v in Text(v.label).tag(v) }
                }
                .pickerStyle(.segmented)
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
            Divider()
            Text("Visible only when Show Background is on. Photo overrides gradient; gradient overrides colour.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .buttonStyle(.bordered)
                if draft.backgroundGradient != nil {
                    Button(role: .destructive) { draft.backgroundGradient = nil } label: {
                        Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var backgroundGradientThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let gradient = draft.backgroundGradient {
                gradient.makeView()
            } else {
                shape.fill(.secondary.opacity(0.12))
                    .overlay(Image(systemName: "paintpalette").foregroundStyle(.secondary))
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
                .buttonStyle(.bordered)
                if draft.backgroundImageID != nil {
                    Button(role: .destructive) { removePhoto() } label: {
                        Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// A small preview of the chosen photo (or a placeholder tile).
    @ViewBuilder private var backgroundThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let id = draft.backgroundImageID,
               let image = ThemeBackgroundStore.shared.image(for: id) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                shape.fill(draft.background.color)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
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
            Divider()
            Text("Each key reveals the portion of the photo/gradient behind it, refracted through the glass. Photo overrides gradient.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .buttonStyle(.bordered)
                if draft.keyGradient != nil {
                    Button(role: .destructive) { draft.keyGradient = nil } label: {
                        Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var keyGradientThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let gradient = draft.keyGradient {
                gradient.makeView()
            } else {
                shape.fill(.secondary.opacity(0.12))
                    .overlay(Image(systemName: "paintpalette").foregroundStyle(.secondary))
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
                .buttonStyle(.bordered)
                if draft.keyImageID != nil {
                    Button(role: .destructive) { removeKeyPhoto() } label: {
                        Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var keyImageThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let id = draft.keyImageID,
               let image = ThemeBackgroundStore.shared.image(for: id) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                shape.fill(.secondary.opacity(0.15))
                    .overlay(Image(systemName: "square.grid.3x3").foregroundStyle(.secondary))
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

    private var glassHint: some View {
        Text("Liquid Glass uses the fills as translucent tints — lower their opacity so the keys stay glassy.")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.deleteCustomTheme(id: draft.id)
            dismiss()
        } label: {
            Text("Delete Theme").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .padding(.top, 4)
    }

    private func colorRow(_ label: String, _ keyPath: WritableKeyPath<Theme, RGBA>) -> some View {
        ColorPicker(
            label,
            selection: Binding(
                get: { draft[keyPath: keyPath].color },
                set: { draft[keyPath: keyPath] = RGBA($0) }
            ),
            supportsOpacity: true
        )
        .padding(.vertical, 2)
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
    @State private var draft: ThemeGradient

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
            .background(Color(.systemGroupedBackground))
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
            ColorPicker("Color", selection: Binding(
                get: { stop.wrappedValue.color.color },
                set: { stop.color.wrappedValue = RGBA($0) }
            ), supportsOpacity: true)
            .labelsHidden()
            .frame(width: 36, height: 36)

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
