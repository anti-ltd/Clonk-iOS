# Extending Clink — Action Panels

An **action panel** is an optional surface the keyboard can show in place of (or
alongside) the keys: clipboard history, the quick notepad, the emoji keyboard.
They all hang off one shared activation system — a top-left bar button and/or a
slide-up gesture on the `123` key — and the user enables/picks them in
**Settings → Typing → Action panels**.

This document walks through adding a new panel end to end, using a worked
example: a **Snippets** panel (saved canned phrases you tap to insert).

> TL;DR checklist
> 1. Add a case to [`ActionPanel`](../Sources/ClinkKit/KeyboardLiveState.swift).
> 2. Add `…Enabled` (and any style) fields to [`KeyboardSettings`](../Sources/ClinkKit/KeyboardSettings.swift) — property, init param, decode.
> 3. (If it owns data) add a `@MainActor @Observable` manager persisted to the App Group, mirroring [`ClipboardManager`](../Sources/ClinkKit/ClipboardManager.swift) / [`NotepadManager`](../Sources/ClinkKit/NotepadManager.swift).
> 4. Wire the manager + an `on…Insert` callback into [`KeyboardCanvas`](../Sources/ClinkKit/KeyboardCanvas.swift) and [`KeyboardViewController`](../Sources/ClinkKeyboard/KeyboardViewController.swift).
> 5. Render it: a bar strip (`barContent`) and/or a full overlay (`overlayPanel`).
> 6. Add the in-app settings screen + a NavRow in [`RootView`](../Sources/Clink/UI/RootView.swift).
> 7. `make project && make build`.

---

## 0. Concepts & where things live

| Concern | Type | File |
|---|---|---|
| Which panel is open | `ActionPanel?` on `KeyboardLiveState.activePanel` | `Sources/ClinkKit/KeyboardLiveState.swift` |
| Persisted on/off + style | fields on `KeyboardSettings` | `Sources/ClinkKit/KeyboardSettings.swift` |
| Panel data + persistence | a `@MainActor @Observable` manager | `Sources/ClinkKit/<Name>Manager.swift` |
| Rendering + activation | `KeyboardCanvas` | `Sources/ClinkKit/KeyboardCanvas.swift` |
| Host document edits | `KeyboardViewController` | `Sources/ClinkKeyboard/KeyboardViewController.swift` |
| In-app settings | a SwiftUI screen + `RootView` NavRow | `Sources/Clink/UI/` |

Two hard constraints to internalize first:

- **ClinkKit compiles into BOTH the app and the extension.** Keep panel models
  and views in `Sources/ClinkKit`. Anything app-only (settings screens) goes in
  `Sources/Clink/UI`. Anything that must touch the live document
  (`textDocumentProxy`) stays in the extension via a callback.
- **You can't put a `TextField`/`TextEditor` inside the keyboard extension and
  type into it** — the keyboard *is* the keyboard, so an embedded field gets no
  input. If your panel needs text entry, route the keyboard's own keys into a
  buffer (see [§5b, the notepad pattern](#5b-routing-keystrokes-into-a-panel)).
  In-app (the container) `TextEditor` works fine.

### Two kinds of panel

1. **In-canvas panel** (clipboard, notepad). Rendered *inside* `KeyboardCanvas`
   as a bar strip and/or a full overlay. `activate()` sets `live.activePanel`.
2. **Separate-canvas panel** (emoji). Rendered as its own top-level canvas
   swapped in by the view controller. `activate()` flips a controller flag
   (`controller.showEmoji`) instead of `live.activePanel`. Only do this if your
   surface is genuinely a different keyboard mode; **prefer in-canvas.**

The Snippets example below is an in-canvas panel.

---

## 1. Register the panel — `ActionPanel`

`Sources/ClinkKit/KeyboardLiveState.swift`:

```swift
public enum ActionPanel: String, Sendable, CaseIterable, Identifiable {
    case clipboard
    case notepad
    case emoji
    case snippets            // ← new

    public var label: String {
        switch self {
        …
        case .snippets: return "Snippets"
        }
    }

    public func icon(active: Bool) -> String {
        switch self {
        …
        case .snippets: return active ? "text.badge.star" : "text.badge.plus"
        }
    }

    public var summary: String {       // shown in the `cards` picker
        switch self {
        …
        case .snippets: return "Saved canned phrases"
        }
    }
}
```

Adding the case forces exhaustive `switch`es to fail to compile until you handle
them — that's your to-do list. Touch points: `panelIsOverlay`, the
`overlayPanel` switch in `body`, and `activate(_:)`, all in `KeyboardCanvas`.

---

## 2. Persisted settings — `KeyboardSettings`

`Sources/ClinkKit/KeyboardSettings.swift`. `KeyboardSettings` is the single
`Codable` value that crosses the App Group between app and extension. `CodingKeys`
and `encode(to:)` are **auto-synthesized**, so for each new field you add exactly
three lines: stored property, init parameter (with default), and a tolerant
decode line.

```swift
// 1) stored property
public var snippetsEnabled: Bool

// 2) init parameter — KEEP a default so existing call sites compile
snippetsEnabled: Bool = false,
// …and the assignment in init:
self.snippetsEnabled = snippetsEnabled

// 3) decode — decodeIfPresent so old payloads without the key still load
snippetsEnabled = try c.decodeIfPresent(Bool.self, forKey: .snippetsEnabled) ?? false
```

> **Always `decodeIfPresent ?? default`.** A plain `try decode` throws on any
> older persisted blob and fails the *entire* settings load. For enum-typed
> style fields use `(try? c.decodeIfPresent(MyEnum.self, …)) ?? .someCase` so a
> retired case can't poison the decode either.

If your panel has presentation options, add an enum next to `ClipboardStyle` /
`NotepadMode`, conforming to `String, Codable, Sendable, CaseIterable,
Identifiable` with a `label` — the in-app segmented picker iterates `.allCases`
so it appears automatically.

---

## 3. The data manager (only if the panel owns state)

Pure-compute panels (a calculator, a symbol palette) need no manager — skip to
§4. Stateful panels get a `@MainActor @Observable` class persisted to the App
Group container, with a `UserDefaults.standard` fallback for when the group is
unavailable. Copy the shape from `ClipboardManager` / `NotepadManager`.

`Sources/ClinkKit/SnippetsManager.swift`:

```swift
import SwiftUI

public struct Snippet: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public init(id: UUID = UUID(), text: String) { self.id = id; self.text = text }
}

@MainActor
@Observable
public final class SnippetsManager {
    public private(set) var items: [Snippet] = []
    public init() { load() }

    public func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.insert(Snippet(text: t), at: 0)
        save()
    }
    public func delete(at i: Int) {
        guard items.indices.contains(i) else { return }
        items.remove(at: i); save()
    }

    // Persistence — App Group file, UserDefaults fallback (see ClipboardManager).
    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent("clink-snippets.v1.json")
    }
    private func load() {
        if let url = fileURL, let d = try? Data(contentsOf: url),
           let v = try? JSONDecoder().decode([Snippet].self, from: d) { items = v; return }
        if let d = UserDefaults.standard.data(forKey: "clink-snippets-v1"),
           let v = try? JSONDecoder().decode([Snippet].self, from: d) { items = v }
    }
    private func save() {
        guard let d = try? JSONEncoder().encode(items) else { return }
        if let url = fileURL { try? d.write(to: url, options: .atomic); return }
        UserDefaults.standard.set(d, forKey: "clink-snippets-v1")
    }
}
```

Notes:
- `@Observable` makes SwiftUI re-render the panel when `items` changes — no
  manual `objectWillChange`.
- Pick a **versioned filename** (`…v1.json`). If you change the schema later,
  bump to `v2` and migrate on load, like `ClipboardManager` does for v1→v2.
- The App Group id is `group.ltd.anti.clink` ([`SharedStore.appGroupID`](../Sources/ClinkKit/SharedStore.swift)).
  Both processes read the same file, so a save in the app shows up in the
  keyboard and vice-versa.

---

## 4. Inject into the canvas + view controller

### 4a. `KeyboardCanvas` constructor

`KeyboardCanvas` receives managers and `on…Insert` callbacks. Add yours
alongside `clipboard` / `notepad` (`Sources/ClinkKit/KeyboardCanvas.swift`):

```swift
private var snippets: SnippetsManager
private let onSnippetInsert: (String) -> Void

public init(
    …
    snippets: SnippetsManager = SnippetsManager(),
    …
    onSnippetInsert: @escaping (String) -> Void = { _ in }
) {
    …
    self.snippets = snippets
    self.onSnippetInsert = onSnippetInsert
}
```

Defaults matter: every other call site (`KeyboardPreview`, `ShowcaseView`,
`StagedHeroView`, `EmojiCanvas`) constructs a `KeyboardCanvas` and relies on the
defaults so they keep compiling untouched.

### 4b. `KeyboardViewController`

The extension owns the one shared manager instance and the *only* code allowed
to mutate the host document. Mirror the clipboard/notepad wiring
(`Sources/ClinkKeyboard/KeyboardViewController.swift`):

```swift
private let snippets = SnippetsManager()
…
KeyboardCanvas(
    …
    snippets: snippets,
    …
    onSnippetInsert: { [weak self] text in
        guard let self, !text.isEmpty else { return }
        self.isApplyingEdit = true
        self.insertMirrored(text)        // writes to textDocumentProxy
        self.isApplyingEdit = false
        self.live.activePanel = nil      // close the panel after inserting
        self.scheduleSuggestionUpdate()
    }
)
```

Insertion **must** go through the controller's `insertMirrored(_:)` (not
`textDocumentProxy` directly) so the autocomplete/cursor mirror stays in sync.
`isApplyingEdit` brackets suppress our own change-notification feedback loop.

---

## 5. Rendering & activation

### Make `activate` and `panelIsOverlay` handle the case

In `KeyboardCanvas`:

```swift
private func panelIsOverlay(_ panel: ActionPanel) -> Bool {
    switch panel {
    …
    case .snippets: return true   // full overlay; or false for a bar strip
    }
}

private func activate(_ panel: ActionPanel) {
    pickerOpen = false
    switch panel {
    case .emoji:
        withAnimation(.snappy(duration: 0.22)) { controller.showEmoji = true }
    case .clipboard, .notepad, .snippets:
        live.activePanel = panel
    }
}
```

`enabledPanels` is the single source of truth for which panels exist right now —
add your gate there:

```swift
private var enabledPanels: [ActionPanel] {
    var p: [ActionPanel] = []
    if settings.clipboardEnabled && hasFullAccess { p.append(.clipboard) }
    if settings.notepadEnabled { p.append(.notepad) }
    if settings.emojiEnabled  { p.append(.emoji) }
    if settings.snippetsEnabled { p.append(.snippets) }   // ←
    return p
}
```

> **Full Access:** only gate on `hasFullAccess` if you read the system
> pasteboard or hit the network. Snippets is local, so no gate. (Clipboard
> needs it to read `UIPasteboard`.)

Everything else — the top-left icon, the popover/inline/cards pickers, the
slide-up gesture — is already driven off `enabledPanels` and needs no changes.

### Render a full overlay

Add a branch to the `overlayPanel` switch in `body`:

```swift
case .snippets:
    SnippetsPanel(
        items: snippets.items,
        theme: theme,
        cornerRadius: CGFloat(settings.keyCornerRadius),
        onTap: { onSnippetInsert($0) },
        onDelete: { snippets.delete(at: $0) },
        onDismiss: { closePanel() }
    )
```

Build the `SnippetsPanel` view by copying `NotepadBrowsePanel` (header at
`Metrics.suggestionBarHeight`, a `ScrollView` of `SwipeRow` cards, `cardSurface`
that switches on `theme.material`). Honor the **per-cell glass rule**: do *not*
put `glassEffect` on every card cell — it OOM-crashes/lags the keyboard
extension. Use one container-level material layer (the existing `cardSurface`
pattern is already safe).

### Render a bar strip (alternative / additional)

If your panel lives in the 44pt bar instead, add a branch to `barContent` (like
`ClipboardBar` / `NotepadBar`) and return `false` from `panelIsOverlay`. The bar
keeps the keys visible below — required if the panel needs the keys (text entry).

### 5b. Routing keystrokes into a panel

If the panel is a compose surface (notepad-style), intercept at the canvas's
input choke points so keys feed your buffer instead of the host:

```swift
private func insert(_ s: String) {
    if live.activePanel == .notepad { notepad.scratch += s }
    else { onInsert(s) }
}
private func backspace() {
    if live.activePanel == .notepad { if !notepad.scratch.isEmpty { notepad.scratch.removeLast() } }
    else { onBackspace() }
}
```

Both `insert` and `backspace` are the *only* paths keys take (space and return
call `insert(" ")` / `insert("\n")`), so intercepting there captures all typing.
Such a panel must be a **bar strip**, not a full overlay — the keys have to stay
on screen to type.

---

## 6. In-app settings

### 6a. The panel's own screen

Add `Sources/Clink/UI/SnippetsView.swift` mirroring `NotepadView` /
`ClipboardHistoryView`: an enable `ToggleRow`, any style `Picker` (segmented,
over `MyEnum.allCases`), and management of the saved items. The container app
*can* use `TextField`/`TextEditor` for adding/editing — that limitation only
applies inside the keyboard extension.

Bind through the model:

```swift
@Environment(AppModel.self) private var model
…
@Bindable var model = model
ToggleRow("Snippets", subtitle: "…", isOn: $model.settings.snippetsEnabled)
```

Expose the manager on `AppModel` (`Sources/Clink/AppModel.swift`) so the screen
reads/writes the same instance the keyboard uses:

```swift
let snippets = SnippetsManager()
```

### 6b. The NavRow

Add a row to the **Action panels** `CardSection` in
`Sources/Clink/UI/RootView.swift`:

```swift
Divider()
NavRow("Snippets", subtitle: "Saved canned phrases",
       systemImage: "text.badge.plus",
       value: model.settings.snippetsEnabled ? "On" : "Off") {
    SnippetsView()
}
```

The **Panel access** card (activation toggles + picker style) is generic — it
already counts your panel via `enabledPanelCount` once `snippetsEnabled` exists.
No change needed there.

---

## 7. Activation, for free

You don't wire activation per panel. Once a panel is in `enabledPanels`, all of
this works automatically:

- **Top-left icon** (`activateWithIcon`): 1 panel → toggles it; 2+ → opens the
  picker.
- **Slide up on `123`** (`activateWithSlideUp`): same — 1 opens directly, 2+
  opens the picker.
- **Picker style** (`panelPickerStyle`): `popover` (floating menu), `inline`
  (bar expands to an icon row), or `cards` (full-keyboard tappable cards via
  `PanelSwitcherPanel`). For `cards`, your `label`, `icon`, and `summary` are
  what render.
- Pressing any key while a picker is open dismisses it (`dismissPickerOnInput`).

---

## 8. Build & verify

New files under `Sources/**` are globbed by `project.yml`, so regenerate the
Xcode project, then build:

```sh
make project   # XcodeGen — picks up new Swift files
make build     # xcodebuild, iOS simulator target — compile check
```

Do **not** boot the simulator to "test" — verify by compiling; device testing is
done on a real device. Keep the `KeyboardSettings` round-trip in mind: anything
you add ships in config export/import automatically because it's one `Codable`.

---

## Reference: the height contract

`KeyboardCanvas.preferredHeight(for:hasFullAccess:)` decides the keyboard's
height. It adds one `suggestionBarHeight` when the bar is present (suggestions on,
or the icon is enabled with at least one panel). If your panel changes whether a
permanent bar should exist, update that computation too — otherwise a bar-style
panel can be clipped. Full overlays reuse the existing frame and need no change.
