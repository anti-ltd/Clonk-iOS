# Overview

## What it is

Clink is a custom iOS keyboard shipped as two processes plus shared code. The
container app is the App Store product — settings, onboarding, live preview. The
keyboard extension is what actually runs inside Messages, Notes, etc. Both compile
the same `KeyboardCanvas` SwiftUI view so the in-app preview never drifts from
what users type with.

---

## Where it sits

```
┌─────────────────────┐         ┌─────────────────────┐
│   Clink (app)       │         │ ClinkKeyboard.appex │
│                     │         │                     │
│  RootView           │         │ KeyboardViewController
│  AppModel ──write──┼────────▶│ ──read── SharedStore│
│  KeyboardPreview    │         │ KeyboardCanvas      │
│    └─ KeyboardCanvas│         │ EmojiCanvas         │
└─────────┬───────────┘         └─────────┬───────────┘
          │                               │
          └──────── App Group ────────────┘
                group.ltd.anti.clink
           clink-settings.v1.json  (main config)
           clink-status.v1.json    (Full Access flag)
           clink-clipboard.v2.json
           clink-notepad.v1.json
           clink-extensions.v1.json
           clink-panels.v1.json
           theme-photos/*.jpg
```

| Target | Path | Runs where |
|---|---|---|
| **Clink** | `Sources/Clink/` | Foreground app |
| **ClinkKeyboard** | `Sources/ClinkKeyboard/` | Sandboxed extension (~50 MB budget) |
| **ClinkKit** | `Sources/ClinkKit/` | Linked into both targets (not a dynamic framework) |

ClinkKit is a shared *source directory*, not an `.xcframework`. Both targets
compile the same files. That avoids extension embedding / rpath headaches that
bite keyboard projects using dynamic frameworks.

---

## Files

| File | Role |
|---|---|
| `project.yml` | XcodeGen manifest — targets, entitlements, SPM deps |
| `Sources/Clink/ClinkApp.swift` | `@main` entry; URL import handler |
| `Sources/Clink/AppModel.swift` | App-wide state; persists settings on every mutation |
| `Sources/ClinkKeyboard/KeyboardViewController.swift` | Extension principal class |
| `Sources/ClinkKit/KeyboardCanvas.swift` | The keyboard view (app + extension) |
| `Sources/ClinkKit/SharedStore.swift` | App Group file I/O + Darwin notifications |
| `Sources/ClinkKit/KeyboardSettings.swift` | Single `Codable` config blob |

See [FILE-INDEX](FILE-INDEX.md) for all 153 Swift files.

---

## How it works

### Settings round-trip

1. User toggles something in the app → `AppModel.settings` mutates → `SharedStore.save()` writes JSON atomically.
2. Darwin notification `ltd.anti.clink.settingsDidChange` fires (unless `notify: false` for high-frequency writes like emoji recents).
3. Running keyboard extension receives notification → reloads settings → SwiftUI re-renders.
4. On iPhone, keyboard also reloads on `viewWillAppear` (fresh file read every time).

### Keystroke path (extension only)

```
UITouch → TouchEngine → KeyboardCanvas.insert/backspace
    → KeyboardViewController.insertMirrored/backspaceMirrored
    → textDocumentProxy
    → scheduleSuggestionUpdate (debounced, quiet-gated)
    → SuggestionEngine → KeyboardLiveState → SuggestionBar
```

The app preview uses the same canvas but passes stub callbacks — no document proxy.

### What crosses the process boundary

| Data | Mechanism | Direction |
|---|---|---|
| `KeyboardSettings` | JSON file | app → extension (extension reads; rarely writes) |
| Full Access status | JSON file | extension → app |
| Clipboard / notepad / extensions / panels |各自的 JSON files | both read/write |
| Theme background photos | JPEG files in App Group | app writes; extension reads |
| Live suggestion state | never | stays in extension memory |

---

## Gotchas

- **Don't use App Group `UserDefaults` for settings.** `cfprefsd` caches per-process; the extension can hold a stale snapshot for minutes. File reads always get current bytes. (See comment block at top of `SharedStore.swift`.)

- **Document edits stay in the extension.** ClinkKit views call `onInsert` / `onBackspace` callbacks. Only `KeyboardViewController` touches `textDocumentProxy`. The app preview passes no-ops or local buffer logic.

- **No `TextField` inside the extension for panel compose.** The keyboard *is* the keyboard — embedded fields get no input. Route keys into a buffer instead (notepad pattern). See [13-extending-panels](13-extending-panels.md).

- **Keyboard extension memory budget is tight.** ~50 MB before jetsam. That's why PyMini exists instead of CPython, and why glass effects can't go on every list cell.

- **`KeyboardSettings` decode must tolerate old payloads.** Every new field: property + init default + `decodeIfPresent ?? default`. A throwing decode kills the entire settings load.

- **Liquid Glass is iOS 26+.** `@available` guards throughout; iOS 17–25 get `.ultraThinMaterial` fallback.

---

## Read order

1. [01-settings-and-storage](01-settings-and-storage.md) — the data model everything hangs off
2. [02-keyboard-core](02-keyboard-core.md) — what users actually see
3. [10-extension-host](10-extension-host.md) — how the extension wires it together

---

## See also

- [README.md](../README.md) — product features, build commands
- [11-theming](11-theming.md) — visual layer
- [12-motion](12-motion.md) — animation layer
- [15-touch-engine](15-touch-engine.md) — text-first input contract & unification plan
