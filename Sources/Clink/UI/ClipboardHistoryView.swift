/**
 Clipboard settings and history browser. Shows the on/off toggle, style picker,
 and the list of saved entries with swipe-to-pin / copy / delete actions.
 */
import SwiftUI
import UIKit
import iUXiOS

/// Clipboard history settings and entry list.
struct ClipboardHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var copiedIndex: Int? = nil
    @State private var openRow: Int? = nil

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.settings.clipboardEnabled && model.settings.clipboardStyle == .overlay {
                ClipboardPreview(settings: model.settings)
                    .padding(.horizontal, UX.screenPadding)
                    .padding(.top, UX.screenPadding)
                    .padding(.bottom, UX.cardSpacing)
                    .overlay(alignment: .bottom) { Divider().opacity(0.4) }
            }
            ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Settings") {
                    ToggleRow("Clipboard history",
                              subtitle: "Save recently copied text for quick re-paste. Adds a clipboard icon to the suggestions bar.",
                              isOn: $model.settings.clipboardEnabled)
                    if model.settings.clipboardEnabled && !model.hasFullAccess {
                        Divider()
                        NavigationLink { EnableFlowView().tracksNavigationDepth() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield").font(.title3).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Full Access required").font(.subheadline.weight(.semibold))
                                    Text("Clipboard history needs Full Access to read what you've copied.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if model.settings.clipboardEnabled {
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Style")
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                            Picker("Style", selection: $model.settings.clipboardStyle) {
                                ForEach(ClipboardStyle.allCases) { style in
                                    Text(style.label).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 14)
                            styleCaption
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                        }
                        Divider()
                        ToggleRow("Delete on paste",
                                  subtitle: "Remove a clip from history after pasting it. Pinned clips are never deleted.",
                                  isOn: $model.settings.clipboardDeleteOnPaste)
                        Divider()
                        ToggleRow("Close on paste",
                                  subtitle: "Dismiss the clipboard panel after pasting a clip.",
                                  isOn: $model.settings.clipboardCloseOnPaste)
                        Divider()
                        ToggleRow("Delete pins on clear",
                                  subtitle: "Include pinned clips when clearing all history.",
                                  isOn: $model.settings.clipboardIgnorePinsOnDelete)
                    }
                }

                if model.settings.clipboardEnabled {
                    CardSection("Auto Copy") {
                        ToggleRow("On keyboard open",
                                  subtitle: "Capture the current clipboard when the keyboard finishes opening.",
                                  isOn: $model.settings.autoCopyOnKeyboardOpen)
                        Divider()
                        ToggleRow("On history open",
                                  subtitle: "Capture the current clipboard when the history panel is opened.",
                                  isOn: $model.settings.autoCopyOnClipboardOpen)
                    }
                }

                if model.settings.clipboardEnabled {
                    if model.clipboard.history.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("History")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            VStack(spacing: 8) {
                                ForEach(Array(model.clipboard.history.enumerated()), id: \.offset) { index, entry in
                                    let copy = {
                                        UIPasteboard.general.string = entry.text
                                        copiedIndex = index
                                        Task {
                                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                                            if copiedIndex == index { copiedIndex = nil }
                                        }
                                    }
                                    SwipeRow(id: index, actions: [
                                        SwipeAction(icon: "doc.on.doc.fill", label: "Copy",
                                                    tint: .gray) { copy() },
                                        SwipeAction(icon: entry.pinned ? "pin.slash.fill" : "pin.fill",
                                                    label: entry.pinned ? "Unpin" : "Pin",
                                                    tint: .blue) { model.clipboard.togglePin(at: index) },
                                        SwipeAction(icon: "trash.fill", label: "Delete",
                                                    tint: .red) { model.clipboard.delete(at: index) },
                                    ], openID: $openRow, onTap: copy, cardBackground: {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(.secondarySystemGroupedBackground))
                                    }) {
                                        ClipboardEntryRow(
                                            entry: entry,
                                            isCopied: copiedIndex == index
                                        )
                                    }
                                }
                            }
                        }

                        Button(role: .destructive) {
                            model.clipboard.clearAll(ignoringPins: model.settings.clipboardIgnorePinsOnDelete)
                        } label: {
                            Text("Clear All")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red.opacity(0.85))
                    }
                }
            }
            .padding(UX.screenPadding)
            }
        }
        .navigationTitle("Clipboard")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
    }

    @ViewBuilder private var styleCaption: some View {
        switch model.settings.clipboardStyle {
        case .bar:
            Text("Replaces the suggestion bar with a horizontal scroll of clips.")
                .font(.caption).foregroundStyle(.secondary)
        case .overlay:
            Text("Shows a panel over the keys with cards and timestamps.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No clipboard history")
                .font(.subheadline.weight(.medium))
            Text("Text you copy while typing with Clink will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let isCopied: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if entry.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                if entry.date != .distantPast {
                    Text(entry.date.clipboardRelative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14))
                .foregroundStyle(isCopied ? Color.green : Color.secondary)
                .animation(.easeInOut(duration: 0.15), value: isCopied)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
