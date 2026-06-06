import SwiftUI
import iUXiOS

struct NotepadView: View {
    @Environment(AppModel.self) private var model
    @State private var openRow: Int? = nil

    var body: some View {
        @Bindable var model = model
        @Bindable var notepad = model.notepad
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Settings") {
                    ToggleRow("Quick notepad",
                              subtitle: "Jot text from any app, then drop it wherever you type. Adds a notepad to the panel button.",
                              isOn: $model.settings.notepadEnabled)
                    if model.settings.notepadEnabled {
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Mode")
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                            Picker("Mode", selection: $model.settings.notepadMode) {
                                ForEach(NotepadMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 14)
                            modeCaption
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                        }
                    }
                }

                if model.settings.notepadEnabled {
                    CardSection("Scratch") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextEditor(text: $notepad.scratch)
                                .frame(minHeight: 120)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(Color(.tertiarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    if notepad.scratch.isEmpty {
                                        Text("Type to jot a note…")
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 16)
                                            .allowsHitTesting(false)
                                    }
                                }
                            HStack {
                                if model.settings.notepadMode == .notes {
                                    Button {
                                        model.notepad.addNote(notepad.scratch)
                                        notepad.scratch = ""
                                    } label: {
                                        Label("Save as note", systemImage: "plus")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(notepad.scratch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    notepad.scratch = ""
                                } label: {
                                    Label("Clear", systemImage: "xmark")
                                }
                                .buttonStyle(.bordered)
                                .disabled(notepad.scratch.isEmpty)
                            }
                        }
                        .padding(14)
                    }

                    if model.settings.notepadMode == .notes {
                        if model.notepad.notes.isEmpty {
                            emptyState
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Saved notes")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                VStack(spacing: 8) {
                                    ForEach(Array(model.notepad.notes.enumerated()), id: \.element.id) { index, note in
                                        SwipeRow(id: index, actions: [
                                            SwipeAction(icon: "pencil", label: "Load",
                                                        tint: .blue) { notepad.scratch = note.text },
                                            SwipeAction(icon: "trash.fill", label: "Delete",
                                                        tint: .red) { model.notepad.deleteNote(at: index) },
                                        ], openID: $openRow,
                                           onTap: { notepad.scratch = note.text },
                                           cardBackground: {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color(.secondarySystemGroupedBackground))
                                        }) {
                                            noteRow(note)
                                        }
                                    }
                                }
                            }

                            Button(role: .destructive) {
                                model.notepad.clearNotes()
                            } label: {
                                Text("Clear All").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red.opacity(0.85))
                        }
                    }
                }
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("Notepad")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder private var modeCaption: some View {
        switch model.settings.notepadMode {
        case .scratchpad:
            Text("A single buffer you jot into and pull from.")
                .font(.caption).foregroundStyle(.secondary)
        case .notes:
            Text("The same buffer, plus a saved-notes archive you store snippets in.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

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
