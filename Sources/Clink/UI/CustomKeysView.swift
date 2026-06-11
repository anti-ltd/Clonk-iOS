/**
 Custom keys editor (Layout → Custom tab). Users build their own keys — insert
 text with optional long-press alternates, or function keys (cursor, tab,
 numbers, emoji, backspace) — and place them beside the space bar or in whole
 custom rows above/below the letters. Keys appear on the letters plane only.

 Writes straight into `model.settings.spaceBarLeadingKeys` /
 `spaceBarTrailingKeys` / `customRows`; the pinned preview reflects edits live.
 */
import SwiftUI
import iUXiOS

struct CustomKeysView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius

    /// Non-nil while the key editor sheet is up. Owned by the host screen
    /// (`LayoutView`) so the themed sheet can be presented full-screen.
    @Binding var editing: KeyEdit?

    private var settings: KeyboardSettings { model.settings }

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        CardSection("Beside space bar") {
            Text("Put your own keys next to the space bar, like a quick comma and period.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            flankEditor("Left of space", keys: settings.spaceBarLeadingKeys, location: .leading)
            Divider()
            flankEditor("Right of space", keys: settings.spaceBarTrailingKeys, location: .trailing)
            if settings.spaceBarLeadingKeys.isEmpty && settings.spaceBarTrailingKeys.isEmpty {
                Divider()
                Button {
                    addCommaAndPeriod()
                } label: {
                    Label("Add comma & period", systemImage: "wand.and.stars")
                }
                .buttonStyle(ThemedFillButtonStyle(fill: themeAccent, corner: cardCornerRadius))
                .padding(.vertical, UX.rowVPadding)
            }
        }

        CardSection("Custom rows") {
            Text("Add whole rows of keys above or below the letters.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            ForEach(settings.customRows) { row in
                Divider()
                rowEditor(row)
            }
            Divider()
            Button {
                model.settings.customRows.append(CustomRow())
            } label: {
                Label("Add row", systemImage: "plus")
            }
            .buttonStyle(ThemedFillButtonStyle(fill: themeAccent, corner: cardCornerRadius))
            .padding(.vertical, UX.rowVPadding)
        }
    }

    // MARK: - Flank (beside-space) editor

    @ViewBuilder
    private func flankEditor(_ title: String, keys: [CustomKey], location: KeyLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            keyChips(keys, location: location)
        }
        .padding(.vertical, UX.rowVPadding)
    }

    // MARK: - Custom row editor

    @ViewBuilder
    private func rowEditor(_ row: CustomRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ThemedTabPicker(
                    options: CustomRowPosition.allCases.map { ($0.label, $0) },
                    selection: positionBinding(row))
                Button(role: .destructive) {
                    model.settings.customRows.removeAll { $0.id == row.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            keyChips(row.keys, location: .row(row.id))
        }
        .padding(.vertical, UX.rowVPadding)
    }

    // MARK: - Shared chip strip (tap to edit, + to add)

    @ViewBuilder
    private func keyChips(_ keys: [CustomKey], location: KeyLocation) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(keys.enumerated()), id: \.element.id) { idx, key in
                    // Existing key: a solid accent pill (themed, like a real key).
                    themedChip(key.isSymbol ? "" : displayText(key),
                               systemImage: key.isSymbol ? key.glyph : nil,
                               filled: true) {
                        editing = KeyEdit(location: location, index: idx, key: key)
                    }
                }
                // Add affordance: a lighter accent-tinted pill, clearly secondary.
                themedChip("Add", systemImage: "plus", filled: false) {
                    editing = KeyEdit(location: location, index: nil,
                                      key: CustomKey(glyph: "", action: .insert("")))
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// A capsule chip that tracks the keyboard theme: a solid accent fill with a
    /// white glyph when `filled`, otherwise a soft accent tint with an accent
    /// label. Matches the accent + rounding of the themed action buttons.
    @ViewBuilder
    private func themedChip(_ label: String, systemImage: String?, filled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                if !label.isEmpty { Text(label) }
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(themeAccent))
            .background(filled ? AnyShapeStyle(themeAccent)
                               : AnyShapeStyle(themeAccent.opacity(0.18)),
                        in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// What a non-symbol chip shows: the cap glyph, else the action's short name.
    private func displayText(_ key: CustomKey) -> String {
        if !key.glyph.isEmpty { return key.glyph }
        switch key.action {
        case let .insert(s):  return s.isEmpty ? "(empty)" : s
        case .cursorLeft:     return "◀"
        case .cursorRight:    return "▶"
        case .tab:            return "⇥"
        case .numbersPlane:   return "123"
        case .emoji:          return "emoji"
        case .backspace:      return "⌫"
        }
    }

    // MARK: - Writes

    private func positionBinding(_ row: CustomRow) -> Binding<CustomRowPosition> {
        Binding(
            get: { model.settings.customRows.first { $0.id == row.id }?.position ?? .belowLetters },
            set: { newValue in
                if let i = model.settings.customRows.firstIndex(where: { $0.id == row.id }) {
                    model.settings.customRows[i].position = newValue
                }
            }
        )
    }

    /// Insert (when `index == nil`) or replace the edited key at its location.
    /// Static so the host screen (`LayoutView`), which presents the themed sheet,
    /// can commit the result back into settings.
    static func commit(model: AppModel, edit: KeyEdit, key: CustomKey) {
        switch edit.location {
        case .leading:  write(&model.settings.spaceBarLeadingKeys, edit.index, key)
        case .trailing: write(&model.settings.spaceBarTrailingKeys, edit.index, key)
        case let .row(id):
            guard let r = model.settings.customRows.firstIndex(where: { $0.id == id }) else { return }
            write(&model.settings.customRows[r].keys, edit.index, key)
        }
    }

    private static func write(_ keys: inout [CustomKey], _ index: Int?, _ key: CustomKey) {
        if let index, keys.indices.contains(index) {
            keys[index] = key
        } else {
            keys.append(key)
        }
    }

    /// Delete the edited key from its location (existing keys only).
    static func remove(model: AppModel, edit: KeyEdit) {
        guard let index = edit.index else { return }
        func drop(_ keys: inout [CustomKey]) {
            if keys.indices.contains(index) { keys.remove(at: index) }
        }
        switch edit.location {
        case .leading:  drop(&model.settings.spaceBarLeadingKeys)
        case .trailing: drop(&model.settings.spaceBarTrailingKeys)
        case let .row(id):
            guard let r = model.settings.customRows.firstIndex(where: { $0.id == id }) else { return }
            drop(&model.settings.customRows[r].keys)
        }
    }

    private func addCommaAndPeriod() {
        model.settings.spaceBarLeadingKeys.append(
            CustomKey(glyph: ",", action: .insert(","), alternates: [";", ":"]))
        model.settings.spaceBarTrailingKeys.append(
            CustomKey(glyph: ".", action: .insert("."), alternates: ["?", "!", "…"]))
    }

    /// Identifies which list a key being edited belongs to.
    enum KeyLocation: Equatable {
        case leading
        case trailing
        case row(UUID)
    }

    /// A key being edited, plus where it lives. `index == nil` means a new key
    /// to append on save.
    struct KeyEdit: Identifiable {
        let id = UUID()
        var location: KeyLocation
        var index: Int?
        var key: CustomKey
    }
}

// MARK: - Key editor (themed-sheet content)

/// Edits a single `CustomKey`: glyph, action, long-press alternates, width.
/// Rendered as the content of a `themedSheet` (the host provides the handle bar
/// + scroll + padding), so it's just a stack of cards plus Save / Remove. Owns a
/// working copy seeded from `initial`; `onSave` returns the built key.
struct CustomKeyEditorBody: View {
    let initial: CustomKey
    /// Show the destructive Remove button (only for an existing key).
    var canRemove: Bool = false
    let onSave: (CustomKey) -> Void
    var onRemove: () -> Void = {}

    @Environment(\.resolvedKeyboardTheme) private var theme
    @Environment(\.cardCornerRadius) private var cardCornerRadius

    @State private var glyph: String
    @State private var isSymbol: Bool
    @State private var kind: ActionKind
    @State private var insertText: String
    @State private var alternates: [String]
    @State private var width: Double
    @State private var newAlternate: String = ""

    init(initial: CustomKey, canRemove: Bool = false,
         onSave: @escaping (CustomKey) -> Void, onRemove: @escaping () -> Void = {}) {
        self.initial = initial
        self.canRemove = canRemove
        self.onSave = onSave
        self.onRemove = onRemove
        _glyph = State(initialValue: initial.glyph)
        _isSymbol = State(initialValue: initial.isSymbol)
        _kind = State(initialValue: ActionKind(initial.action))
        if case let .insert(s) = initial.action {
            _insertText = State(initialValue: s)
        } else {
            _insertText = State(initialValue: "")
        }
        _alternates = State(initialValue: initial.alternates)
        _width = State(initialValue: initial.width)
    }

    /// Long-press alternates only make sense for a single-character insert key.
    private var alternatesAllowed: Bool { kind == .insert && insertText.count == 1 }

    private var canSave: Bool {
        switch kind {
        case .insert: return !insertText.isEmpty
        default:      return !glyph.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: UX.cardSpacing) {
            CardSection("Action") {
                Picker("Action", selection: $kind) {
                    ForEach(ActionKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                if kind == .insert {
                    Divider()
                    TextFieldRow("Types", prompt: "e.g. , or :)", text: $insertText)
                }
            }

            CardSection("Cap") {
                TextFieldRow(isSymbol ? "Symbol" : "Label",
                             prompt: isSymbol ? "e.g. arrow.left" : "shown on the key",
                             text: $glyph)
                Divider()
                ToggleRow("SF Symbol",
                          subtitle: "Draw the cap as an SF Symbol (use a symbol name above).",
                          isOn: $isSymbol)
                if kind == .insert {
                    Text("Leave the label blank to show what the key types.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if alternatesAllowed {
                CardSection("Long-press alternates") {
                    Text("Hold the key to pick one of these, Gboard-style.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !alternates.isEmpty {
                        Divider()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(alternates.enumerated()), id: \.offset) { idx, alt in
                                    Chip(alt, onRemove: { alternates.remove(at: idx) })
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Divider()
                    TextFieldRow("Add", prompt: "a character", text: $newAlternate,
                                 onSubmit: addAlternate) {
                        Button(action: addAlternate) { Image(systemName: "plus.circle.fill") }
                            .disabled(newAlternate.isEmpty)
                    }
                }
            }

            CardSection("Size") {
                SliderRow("Width", value: $width, in: 0.5...2.5, step: 0.1) {
                    String(format: "%.1f keys", $0)
                }
            }

            Button { save() } label: { Text("Save key") }
                .buttonStyle(ThemedFillButtonStyle(fill: theme.accent.color, corner: cardCornerRadius))
                .disabled(!canSave)

            if canRemove {
                Button(role: .destructive) { onRemove() } label: { Text("Remove key") }
                    .buttonStyle(ThemedFillButtonStyle(fill: .red.opacity(0.85), corner: cardCornerRadius))
            }
        }
    }

    private func addAlternate() {
        let trimmed = newAlternate.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        alternates.append(trimmed)
        newAlternate = ""
    }

    private func save() {
        let action: CustomKeyAction
        switch kind {
        case .insert:       action = .insert(insertText)
        case .cursorLeft:   action = .cursorLeft
        case .cursorRight:  action = .cursorRight
        case .tab:          action = .tab
        case .numbersPlane: action = .numbersPlane
        case .emoji:        action = .emoji
        case .backspace:    action = .backspace
        }
        // For an insert key with no explicit label, the cap shows what it types.
        let cap = (kind == .insert && glyph.isEmpty) ? insertText : glyph
        onSave(CustomKey(id: initial.id, glyph: cap, isSymbol: isSymbol,
                         action: action,
                         alternates: alternatesAllowed ? alternates : [],
                         width: width))
    }

    /// UI-facing mirror of `CustomKeyAction` (no associated value), for the picker.
    enum ActionKind: String, CaseIterable, Identifiable {
        case insert, cursorLeft, cursorRight, tab, numbersPlane, emoji, backspace

        init(_ action: CustomKeyAction) {
            switch action {
            case .insert:       self = .insert
            case .cursorLeft:   self = .cursorLeft
            case .cursorRight:  self = .cursorRight
            case .tab:          self = .tab
            case .numbersPlane: self = .numbersPlane
            case .emoji:        self = .emoji
            case .backspace:    self = .backspace
            }
        }

        var id: String { rawValue }
        var label: String {
            switch self {
            case .insert:       return "Insert text"
            case .cursorLeft:   return "Cursor left"
            case .cursorRight:  return "Cursor right"
            case .tab:          return "Tab"
            case .numbersPlane: return "Numbers (123)"
            case .emoji:        return "Emoji"
            case .backspace:    return "Backspace"
            }
        }
    }
}

#if DEBUG
#Preview { LayoutView().clinkPreview() }
#endif
