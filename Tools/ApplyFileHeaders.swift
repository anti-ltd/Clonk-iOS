#!/usr/bin/env swift
// Adds Module / Target / Learn lines to Swift file headers.
// Run from repo root: swift Tools/ApplyFileHeaders.swift
//
// Append-only when a block comment already exists — preserves existing prose.
import Foundation

struct HeaderSpec {
    let module: String
    let target: String
    let learn: String
}

let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourcesRoot = repoRoot.appendingPathComponent("Sources")

func spec(for url: URL) -> HeaderSpec {
    let rel = url.path.replacingOccurrences(of: sourcesRoot.path + "/", with: "")
    let name = url.lastPathComponent

    if name == "EmojiData.generated.swift" {
        return .init(module: "emoji", target: "ClinkKit", learn: "docs/05-emoji.md")
    }
    if name.hasPrefix("Theme+"), name.hasSuffix(".swift") {
        return .init(module: "theme", target: "ClinkKit", learn: "THEMING.md")
    }

    switch rel {
    case "ClinkKeyboard/KeyboardViewController.swift":
        return .init(module: "extension-host", target: "ClinkKeyboard", learn: "docs/10-extension-host.md")
    case "Clink/ClinkApp.swift":
        return .init(module: "app-ui", target: "Clink", learn: "docs/09-app-ui.md")
    case "Clink/AppModel.swift":
        return .init(module: "settings", target: "Clink", learn: "docs/01-settings-and-storage.md")
    case "Clink/AppStage.swift", "Clink/MotionHUD.swift", "Clink/MotionMetrics.swift":
        return .init(module: "app-ui", target: "Clink", learn: "docs/09-app-ui.md")
    default: break
    }

    if rel.hasPrefix("Clink/UI/") {
        var learn = "docs/09-app-ui.md"
        if rel.contains("/Panels/") { learn = "docs/07-custom-panels.md" }
        else if rel.contains("/Extensions/") { learn = "EXTENSIONS-SDK.md" }
        else if ["ThemeEditorView.swift", "ThemeBuilderView.swift"].contains(name) { learn = "THEMING.md" }
        else if ["KeyboardPreview.swift"].contains(name) { learn = "docs/02-keyboard-core.md" }
        else if ["TypingView.swift", "SuggestionsView.swift", "AdaptationView.swift",
                 "LocalizationView.swift", "ArtificialIntelligenceView.swift", "PerformanceView.swift",
                 "AutomationView.swift"].contains(name) { learn = "docs/04-prediction.md" }
        else if ["SoundsView.swift", "SoundPickerView.swift", "HapticsView.swift"].contains(name) { learn = "docs/06-sound.md" }
        return .init(module: "app-ui", target: "Clink", learn: learn)
    }

    if rel.hasPrefix("ClinkKit/Motion/") {
        return .init(module: "motion", target: "ClinkKit", learn: "MOTION.md")
    }
    if rel.hasPrefix("ClinkKit/PyMini/") {
        return .init(module: "pymini", target: "ClinkKit", learn: "docs/08-pymini.md")
    }
    if rel.hasPrefix("ClinkKit/Panels/") {
        return .init(module: "custom-panels", target: "ClinkKit", learn: "docs/07-custom-panels.md")
    }
    if rel.hasPrefix("ClinkKit/Extensions/") {
        return .init(module: "extensions", target: "ClinkKit", learn: "EXTENSIONS-SDK.md")
    }

    let settings: Set = ["KeyboardSettings.swift", "SharedStore.swift", "FeatureFlags.swift",
        "ClipboardManager.swift", "ClipboardEntry.swift", "NotepadManager.swift", "NotepadNote.swift",
        "ThemeBackgroundStore.swift"]
    if settings.contains(name) {
        return .init(module: "settings", target: "ClinkKit", learn: "docs/01-settings-and-storage.md")
    }

    let theme: Set = ["Theme.swift", "ThemeTypes.swift", "ThemePresets.swift", "RGBA.swift"]
    if theme.contains(name) {
        return .init(module: "theme", target: "ClinkKit", learn: "THEMING.md")
    }

    let keyboardCore: Set = ["KeyboardCanvas.swift", "KeyboardController.swift", "KeyboardLayout.swift",
        "KeyboardLiveState.swift", "KeyView.swift", "KeyGlyphLayer.swift", "KeySpec.swift", "KeyPopup.swift",
        "CustomKey.swift", "InputViewHeight.swift", "SmartPunctuation.swift"]
    if keyboardCore.contains(name) {
        return .init(module: "keyboard-core", target: "ClinkKit", learn: "docs/02-keyboard-core.md")
    }

    let touch: Set = ["KeyTouchRouter.swift", "AdaptiveHitbox.swift", "AccentMap.swift", "AccentPicker.swift",
        "SwipeDecoder.swift", "SwipeLexicon.swift", "TrackpadPanel.swift", "SwipeRow.swift"]
    if touch.contains(name) {
        return .init(module: "touch", target: "ClinkKit", learn: "docs/03-touch-and-input.md")
    }

    let prediction: Set = ["SuggestionEngine.swift", "SuggestionBar.swift", "PredictionCore.swift",
        "Lexicon.swift", "LexiconRepository.swift", "NgramModel.swift", "CorrectionScorer.swift",
        "LanguageHeuristics.swift", "UserAdaptation.swift", "AIEngine.swift"]
    if prediction.contains(name) {
        return .init(module: "prediction", target: "ClinkKit", learn: "docs/04-prediction.md")
    }

    if name.hasPrefix("Emoji") || name == "SkinTonePicker.swift" {
        return .init(module: "emoji", target: "ClinkKit", learn: "docs/05-emoji.md")
    }

    if ["SoundPlayer.swift", "SoundPack.swift"].contains(name) {
        return .init(module: "sound", target: "ClinkKit", learn: "docs/06-sound.md")
    }

    let panels: Set = ["ActionPanelButton.swift", "ClipboardPanel.swift", "ClipboardBar.swift",
        "NotepadBrowsePanel.swift", "NotepadBar.swift", "CalculatorPanel.swift",
        "PanelSwitcherPanel.swift", "PanelLeadingIcon.swift"]
    if panels.contains(name) {
        return .init(module: "panels", target: "ClinkKit", learn: "EXTENDING.md")
    }

    return .init(module: "keyboard-core", target: "ClinkKit", learn: "docs/02-keyboard-core.md")
}

func footer(_ spec: HeaderSpec) -> String {
    "\n\n Module: \(spec.module) · Target: \(spec.target)\n Learn: \(spec.learn)\n"
}

func typeName(from filename: String) -> String {
    String(filename.dropLast(6))
}

func processFile(_ url: URL) -> Bool {
    guard var content = try? String(contentsOf: url, encoding: .utf8) else { return false }
    if content.contains("Learn:") { return false }

    let spec = spec(for: url)
    let name = url.lastPathComponent

    // Generated emoji blob
    if name == "EmojiData.generated.swift" {
        guard !content.contains("Module: emoji") else { return false }
        content = content.replacingOccurrences(
            of: "// to regenerate from Tools/emoji-test.txt (Unicode 16.0).\n//",
            with: "// to regenerate from Tools/emoji-test.txt (Unicode 16.0).\n// Module: emoji · Target: ClinkKit · Learn: docs/05-emoji.md\n//"
        )
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    // Append to existing block comment
    if content.hasPrefix("/**") {
        guard let close = content.range(of: "*/") else { return false }
        let insert = footer(spec) + " "
        content.insert(contentsOf: insert, at: close.lowerBound)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    // No header — prepend minimal block
    let type = typeName(from: name)
    let header = "/**\n `\(type)`\n\(footer(spec)) " + "*/\n"
    content = header + content
    try? content.write(to: url, atomically: true, encoding: .utf8)
    return true
}

var updated = 0
func walk(_ dir: URL) {
    guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
    for url in items.sorted(by: { $0.path < $1.path }) {
        if url.hasDirectoryPath { walk(url); continue }
        guard url.pathExtension == "swift" else { continue }
        if processFile(url) { updated += 1 }
    }
}

walk(sourcesRoot)
print("Updated \(updated) files.")
