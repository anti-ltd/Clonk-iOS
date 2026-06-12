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
 Learn: docs/<module>.md   (or THEMING.md / MOTION.md / EXTENDING.md / EXTENSIONS-SDK.md)

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
 Learn: THEMING.md
 */
```

One line of character description; details live in THEMING.md.

---

## Generated files

```swift
// GENERATED — do not edit. `make emoji` from Tools/GenerateEmojiData.swift.
// Module: emoji · Learn: docs/05-emoji.md
```

Same for lexicon tooling if we add generated Swift later.

---

## When to add inline comments

Add inline comments only when:

- The code encodes a lesson (why UIKit not SwiftUI gestures, why file not UserDefaults)
- A value's unit or range matters (`seconds`, `0…1`, `@MainActor`)
- A workaround for an iOS quirk (encapsulated layout height, settling mask)

Do **not** comment every property, obvious getters, or SwiftUI `body` layout.

Use `// MARK: - Section` to split files longer than ~200 lines when sections
are logically distinct (managers: load/save; view controllers: lifecycle vs proxy).

---

## Public API

Public types exposed across targets get a `///` doc comment on the type itself
if behaviour isn't obvious from the name. One short paragraph max.

Settings enums get `///` on each case only when the label alone isn't enough
(e.g. `ClipboardStyle.grid` vs `.overlay`).

---

## Cross-reference

Module docs: [docs/README.md](README.md) · File list: [FILE-INDEX.md](FILE-INDEX.md)
