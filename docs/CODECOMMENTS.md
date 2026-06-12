# Code comment standard

Every Swift file under `Sources/` gets a file header. The goal is orientation —
what this file is for, where it sits, where to read more — not narration of
obvious code.

Match the tone already in files like `SharedStore.swift` and `KeyTouchRouter.swift`:
direct, constraint-aware, no filler.

---

## File header template

```swift
/**
 `PrimaryType` — one sentence: what this file owns.

 Module: <area> · Target: ClinkKit | Clink | ClinkKeyboard
 Learn: docs/<module>.md   (e.g. docs/11-theming.md, docs/13-extending-panels.md)

 Optional second paragraph only when there's a non-obvious constraint
 (jetsam budget, cfprefsd, @MainActor checker, no TextField in extension, etc.).
 */
import …
```

**PrimaryType** — the main struct/class/enum name, backtick-wrapped.

**Module** — one of: `settings`, `theme`, `keyboard-core`, `touch`, `prediction`,
`emoji`, `panels`, `extensions`, `custom-panels`, `pymini`, `motion`, `sound`,
`app-ui`, `extension-host`.

**Target** — which compile target(s) include this file.

**Learn** — the module doc or topic guide to read first.

---

## Theme presets (`Theme+<Name>.swift`)

```swift
/**
 Theme preset — Graphite. Near-black slate; default dark solid theme.
 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
```

One line of character description; details live in [11-theming.md](11-theming.md).

---

## Generated files

```swift
// GENERATED — do not edit. `make emoji` from Tools/GenerateEmojiData.swift.
// Module: emoji · Learn: docs/05-emoji.md
```

Same for lexicon tooling if we add generated Swift later.

---

## When to add inline comments

**Goal:** someone reading the file cold should understand structure, public API,
and non-obvious decisions without opening the module doc. The module doc
(`Learn:` in the header) still carries the full walkthrough — inline docs are
the signposts.

### Always (when missing)

- `// MARK: - Section` in files longer than ~150 lines — group by responsibility
  (load/save, lifecycle, rendering, callbacks, decoding, etc.)
- `///` on every `public` type, enum, and property whose name alone isn't enough
- `///` on settings-screen `struct …View` — one paragraph: what it edits, how it
  binds (`$model.settings` → `AppModel` `didSet` → `SharedStore`)

### Sometimes

- Inline `//` on logic that encodes a lesson (why UIKit not SwiftUI gestures,
  why file not UserDefaults, quiet-gated checker, glass per-cell OOM)
- Values where unit or range matters (`seconds`, `0…1`, `@MainActor`)
- iOS workarounds (encapsulated layout height, settling mask, cfprefsd)

### Skip

- Obvious SwiftUI `body` layout stacks
- Trivial getters and one-line forwarding
- Generated data blobs (`EmojiData.generated.swift`, `Theme+<Name>.swift` color literals)
- Restating what the next line of code literally does

---

## Public API

Public types exposed across targets get a `///` doc comment on the type itself
if behaviour isn't obvious from the name. One short paragraph max.

Settings enums get `///` on each case only when the label alone isn't enough
(e.g. `ClipboardStyle.grid` vs `.overlay`).

---

## Cross-reference

Module docs: [docs/README.md](README.md) · File list: [FILE-INDEX.md](FILE-INDEX.md)
