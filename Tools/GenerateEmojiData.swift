#!/usr/bin/env swift
import Foundation

// Generates Sources/ClonkKit/EmojiData.generated.swift — the complete, ordered,
// categorized base-emoji set — from the vendored Unicode `emoji-test.txt`.
//
//   swift Tools/GenerateEmojiData.swift   (or `make emoji`)
//
// We keep only `fully-qualified` entries and drop any whose code points carry a
// skin-tone modifier (U+1F3FB…U+1F3FF), so the dataset holds only neutral BASE
// emoji — the keyboard applies the user's chosen tone at render time. CLDR order
// from the file is preserved (recommended for keyboard palettes).

// Map each Unicode group to an app category id + SF Symbol tab icon. The
// "Component" group (lone modifiers / hair) is intentionally absent → skipped.
let categoryMap: [(group: String, id: String, icon: String)] = [
    ("Smileys & Emotion", "smileys", "face.smiling"),
    ("People & Body", "people", "hand.wave"),
    ("Animals & Nature", "animals", "pawprint"),
    ("Food & Drink", "food", "fork.knife"),
    ("Activities", "activity", "basketball"),
    ("Travel & Places", "travel", "car"),
    ("Objects", "objects", "lightbulb"),
    ("Symbols", "symbols", "number"),
    ("Flags", "flags", "flag"),
]

let toneModifiers: Set<UInt32> = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]

let scriptURL = URL(fileURLWithPath: #filePath)
let toolsDir = scriptURL.deletingLastPathComponent()
let repoRoot = toolsDir.deletingLastPathComponent()
let inputURL = toolsDir.appendingPathComponent("emoji-test.txt")
let outputURL = repoRoot.appendingPathComponent("Sources/ClonkKit/EmojiData.generated.swift")

guard let text = try? String(contentsOf: inputURL, encoding: .utf8) else {
    FileHandle.standardError.write(Data("error: cannot read \(inputURL.path)\n".utf8))
    exit(1)
}

// Parse into ordered per-group emoji lists.
var byGroup: [String: [String]] = [:]
var order: [String] = []        // group names in first-seen order
var version = "unknown"
var currentGroup: String?

for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
    let line = String(rawLine)
    if line.hasPrefix("# Version:") {
        version = line.replacingOccurrences(of: "# Version:", with: "").trimmingCharacters(in: .whitespaces)
        continue
    }
    if line.hasPrefix("# group:") {
        currentGroup = line.replacingOccurrences(of: "# group:", with: "").trimmingCharacters(in: .whitespaces)
        continue
    }
    if line.hasPrefix("#") || line.isEmpty { continue }

    // "CODEPOINTS ; status # glyph …"
    guard let semi = line.firstIndex(of: ";") else { continue }
    let codePart = line[..<semi].trimmingCharacters(in: .whitespaces)
    let rest = line[line.index(after: semi)...]
    let status = rest.split(separator: "#", maxSplits: 1).first.map {
        $0.trimmingCharacters(in: .whitespaces)
    } ?? ""
    guard status == "fully-qualified" else { continue }

    let values = codePart.split(separator: " ").compactMap { UInt32($0, radix: 16) }
    guard !values.isEmpty else { continue }
    // Skip skin-tone variants — we only want neutral bases.
    if values.contains(where: { toneModifiers.contains($0) }) { continue }
    guard let group = currentGroup,
          categoryMap.contains(where: { $0.group == group }) else { continue }

    let scalars = values.compactMap { Unicode.Scalar($0) }
    guard scalars.count == values.count else { continue }
    let emoji = String(String.UnicodeScalarView(scalars))

    if byGroup[group] == nil { byGroup[group] = []; order.append(group) }
    byGroup[group]?.append(emoji)
}

// Emit Swift.
var out = """
import Foundation

// GENERATED — do not edit by hand. Run `make emoji` (Tools/GenerateEmojiData.swift)
// to regenerate from Tools/emoji-test.txt (Unicode \(version)).
//
// The complete RGI emoji set, neutral (no skin tone) bases only, in CLDR order.
// Skin tones are applied at render time from the user's preferences.

extension EmojiData {
    public static let generatedCategories: [EmojiCategory] = [\n
"""

for entry in categoryMap {
    guard let emoji = byGroup[entry.group], !emoji.isEmpty else { continue }
    out += "        EmojiCategory(id: \"\(entry.id)\", icon: \"\(entry.icon)\", emoji: [\n"
    var idx = 0
    while idx < emoji.count {
        let row = emoji[idx..<min(idx + 12, emoji.count)]
        out += "            " + row.map { "\"\($0)\"" }.joined(separator: ",") + ",\n"
        idx += 12
    }
    out += "        ]),\n"
}

out += "    ]\n}\n"

do {
    try out.write(to: outputURL, atomically: true, encoding: .utf8)
    let total = order.reduce(0) { $0 + (byGroup[$1]?.count ?? 0) }
    print("Wrote \(outputURL.lastPathComponent): \(total) emoji across \(categoryMap.count) categories (Unicode \(version)).")
} catch {
    FileHandle.standardError.write(Data("error: cannot write \(outputURL.path): \(error)\n".utf8))
    exit(1)
}
