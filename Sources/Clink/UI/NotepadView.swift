/**
 Notepad settings and note browser. Three tabs — General (toggle + mode),
 Scratch (live editor), Notes (saved archive). Scratch and Notes are disabled
 when the notepad panel is off.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Notepad panel toggle, mode picker, and saved-notes archive.
/// Settings persist via `AppModel.settings` `didSet`; notes via `NotepadManager`.
struct NotepadView: View {
    private enum Tab { case general, notes }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }
    @State private var selectedTab: Tab = .general
    @State private var openRow: Int? = nil

    var body: some View {
        @Bindable var model = model
        @Bindable var notepad = model.notepad
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    switch selectedTab {
                    case .general: generalTab(model: model)
                    case .notes:   notesTab(notepad: notepad, model: model)
                    }
                }
                .padding(UX.screenPadding)
                .animation(Motion.settingsReveal.animation, value: model.settings.notepadEnabled)
            }
            .id(selectedTab)

            ThemedTabPicker(
                options: [("General", Tab.general), ("Notes", Tab.notes)],
                selection: $selectedTab,
                disabledTags: model.settings.notepadEnabled ? [] : [.notes]
            )
            .padding(.horizontal, UX.screenPadding)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider().opacity(0.4) }
        }
        .navigationTitle("Notepad")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
    }

    // MARK: - Tabs

    @ViewBuilder
    private func generalTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Notepad") {
            ToggleRow("Quick notepad",
                      subtitle: "Jot text from any app, then drop it wherever you type. Adds a notepad to the panel button.",
                      isOn: $model.settings.notepadEnabled)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Style")
                    .font(.subheadline)
                    .padding(.top, 4)
                OptionChips(
                    options: NotepadMode.allCases.map { ($0.label, $0) },
                    selection: $model.settings.notepadMode
                )
                .tint(themeAccent)
                .padding(.bottom, 4)
            }
            .gated(model.settings.notepadEnabled,
                   reason: "Turn on Quick notepad to choose a style.")
        }
    }

    @ViewBuilder
    private func notesTab(notepad: NotepadManager, model: AppModel) -> some View {
        @Bindable var notepad = notepad
        if model.settings.notepadMode == .scratchpad {
            CardSection("Notes") {
                Text("Switch to Notes mode in the General tab to save and browse snippets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
            }
        } else if model.notepad.notes.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Saved notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                VStack(spacing: 8) {
                    ForEach(Array(model.notepad.notes.enumerated()), id: \.element.id) { index, note in
                        SwipeRow(id: index, cornerRadius: cardCornerRadius, actions: [
                            SwipeAction(icon: "pencil", label: "Load",
                                        tint: .blue) { notepad.scratch = note.text },
                            SwipeAction(icon: "trash.fill", label: "Delete",
                                        tint: .red) { model.notepad.deleteNote(at: index) },
                        ], openID: $openRow,
                           onTap: { notepad.scratch = note.text },
                           cardBackground: {
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        }) {
                            noteRow(note)
                        }
                    }
                }
            }
            Button(role: .destructive) {
                model.notepad.clearNotes()
            } label: {
                Text("Clear All")
            }
            .buttonStyle(ThemedFillButtonStyle(fill: .red.opacity(0.85), corner: cardCornerRadius))
        }
    }

    // MARK: - Helpers

    private func noteRow(_ note: NotepadNote) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.text)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
            Text(note.date.clipboardRelative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No saved notes")
                .font(.subheadline.weight(.medium))
            Text("Save the scratch buffer above to keep snippets here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
