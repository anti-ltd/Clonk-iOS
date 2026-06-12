# Clink codebase — learning guide

How to read the Clink-iOS source if you're new to the project, or coming back
after a while and need to find where something lives.

This isn't API reference. It's a map: what each piece does, how data moves
between the app and the keyboard extension, and the constraints that shaped the
code (memory limits, cross-process staleness, main-thread checker work, etc.).

---

## How these docs are organized

Every module doc follows the same shape:

| Section | What you get |
|---|---|
| **What it is** | One paragraph — the problem this code solves |
| **Where it sits** | How it connects to neighbours (with a diagram when useful) |
| **Files** | Table of every Swift file in the module, one line each |
| **How it works** | The actual flow — who calls whom, what gets persisted where |
| **Gotchas** | Things that will bite you if you don't know them upfront |
| **Read order** | If you're diving in cold, start here → then here |
| **See also** | Links to related module docs |

Cross-references use relative paths within this folder, e.g.
`[settings](01-settings-and-storage.md)`.

**In-source comments:** every Swift file under `Sources/` has a file header with
`Module`, `Target`, and `Learn` lines. Public types, settings screens, and
large files also have `///` docs and `// MARK:` sections — see
[CODECOMMENTS.md](CODECOMMENTS.md). Re-apply headers after adding files:
`swift Tools/ApplyFileHeaders.swift`.

---

## Suggested reading order

If you're learning the whole codebase, go roughly in this order. Skip sections
you already know.

1. **[00-overview](00-overview.md)** — two targets, one canvas, App Group IPC
2. **[01-settings-and-storage](01-settings-and-storage.md)** — `KeyboardSettings`, `SharedStore`, managers
3. **[11-theming](11-theming.md)** — themes, presets, Liquid Glass, `.clink` import
4. **[02-keyboard-core](02-keyboard-core.md)** — `KeyboardCanvas`, layout, keys, popups
5. **[03-touch-and-input](03-touch-and-input.md)** — multitouch routing, hitboxes, swipe
6. **[04-prediction](04-prediction.md)** — suggestions, autocorrect, lexicons
7. **[05-emoji](05-emoji.md)** — emoji keyboard, skin tones, generated data
8. **[13-extending-panels](13-extending-panels.md)** — adding a built-in action panel
9. **[06-sound](06-sound.md)** — clicks, haptics, Full Access gating
10. **[12-motion](12-motion.md)** — animation tokens and blessed patterns
11. **[14-extensions-sdk](14-extensions-sdk.md)** — custom Python actions
12. **[07-custom-panels](07-custom-panels.md)** — PyMini UI panels
13. **[08-pymini](08-pymini.md)** — interpreter internals
14. **[09-app-ui](09-app-ui.md)** — container app shell and settings screens
15. **[10-extension-host](10-extension-host.md)** — `KeyboardViewController` wiring
16. **[FILE-INDEX](FILE-INDEX.md)** — every Swift file, alphabetically by path

---

## Quick reference

```
Sources/
├── ClinkKit/          shared — compiled into app AND extension
├── Clink/             container app only (settings UI, AppModel)
└── ClinkKeyboard/     extension only (document proxy, lifecycle)
```

**App Group:** `group.ltd.anti.clink`

**The spine:** app writes `KeyboardSettings` → extension reads → both render
the same `KeyboardCanvas`. Document mutations happen only in the extension via
`onInsert` / `onBackspace` callbacks.

**Build:** `project.yml` is source of truth. `make project && make build`.
