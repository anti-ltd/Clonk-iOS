# Emoji keyboard

## What it is

A full emoji picker swapped in place of the letter keyboard. Category tabs,
scrollable grid, search mode (types on QWERTY to filter by name), skin-tone
long-press, and recents. Rendered by `EmojiCanvas` — a sibling of
`KeyboardCanvas`, not an action-panel overlay.

---

## Where it sits

```
KeyboardViewController
    └── showEmoji ? EmojiCanvas : KeyboardCanvas

EmojiCanvas
    ├── category tab bar (EmojiTabTapSurface — UIKit)
    ├── emoji grid (EmojiCell)
    ├── suggestion bar strip (EmojiBarTouchSurface — UIKit)
    ├── SkinTonePicker (long-press overlay)
    ├── EmojiDeleteTile (hold-to-repeat backspace)
    └── search mode (QWERTY overlay for name filter)
```

---

## Files

| File | Role |
|---|---|
| `EmojiCanvas.swift` | Full emoji keyboard — grid, tabs, search, skin tones, settings integration |
| `EmojiCell.swift` | One grid cell — tap insert, long-press tone picker, glass bloom |
| `EmojiData.swift` | `EmojiCategory` model; name-based search and suggestion logic |
| `EmojiData.generated.swift` | Full Unicode RGI emoji set — **generated, don't edit by hand** |
| `EmojiSkinTone.swift` | Fitzpatrick `SkinTone` enum + modifier application |
| `SkinTonePicker.swift` | Tone variant row on long-press; `EmojiHoldGesture` |
| `EmojiTabTapSurface.swift` | UIKit tap surface for scrollable category tabs |
| `EmojiBarTouchSurface.swift` | UIKit tap surface for emoji suggestion bar strip |
| `EmojiDeleteTile.swift` | Backspace with hold-to-repeat (`HoldRepeatSurface`) |

App settings:

| File | Role |
|---|---|
| `EmojiSettingsView.swift` | Layout, scroll direction, skin tone defaults, recents |

Build tooling:

| File | Role |
|---|---|
| `Tools/emoji-test.txt` | Unicode 16.0 source data |
| `Tools/GenerateEmojiData.swift` | Generator script |
| Command | `make emoji` |

---

## How it works

### Separate canvas, not a panel

Emoji mode sets `KeyboardController.showEmoji = true`. The view controller
swaps the hosting root between `EmojiCanvas` and `KeyboardCanvas`. This is
instant — no system keyboard transition animation.

Action panels (clipboard, notepad) use `live.activePanel` inside
`KeyboardCanvas` instead. Emoji is big enough to warrant its own top-level view.

### Generated data

`EmojiData.generated.swift` contains the full RGI emoji arrays grouped by
category. Regenerate when updating Unicode:

```bash
make emoji   # reads Tools/emoji-test.txt → writes generated Swift
```

Hand-editing the generated file will be overwritten.

### Skin tones

Long-press on a supported emoji → `SkinTonePicker` shows Fitzpatrick variants.
Per-emoji tone memory stored in `KeyboardSettings.recentEmojiTones` (saved with
`notify: false` to avoid reload churn).

Default tone preference in settings applies to emojis without a stored choice.

### Search mode

Toggle search → QWERTY row appears → typed letters filter `EmojiData` by
emoji name (e.g. "fire" → 🔥). Uses the same touch routing patterns as the
main keyboard but scoped to the search overlay.

### UIKit tap surfaces

Category tabs and the suggestion bar strip use UIKit surfaces for the same
reason as `KeyTouchRouter` — reliable simultaneous touch handling in dense UI.

### Recents

Recently used emojis stored in `KeyboardSettings.recentEmoji` (ordered, capped).
Updated on insert; persisted with `notify: false`.

---

## Gotchas

- **Don't edit `EmojiData.generated.swift`.** Run `make emoji` instead.

- **Glass droplet flash is gated on `MotionProfile.allowsExpensiveEffects`.**
  The additive flash layer dropped frames on older GPUs — see [MOTION.md](../MOTION.md).

- **Emoji suggestions in the letter keyboard** (bar strip while typing `:fire:`-style
  names) use `EmojiData` search in `SuggestionEngine`, separate from `EmojiCanvas`.

- **Delete tile hold-to-repeat** uses `HoldRepeatSurface` — same pattern as
  letter keyboard backspace repeat.

---

## Read order

1. `EmojiCanvas.swift` — structure and mode switching
2. `EmojiData.swift` — category model and search
3. `EmojiCell.swift` + `SkinTonePicker.swift` — interaction
4. `EmojiSettingsView.swift` — what users can tune

---

## See also

- [02-keyboard-core](02-keyboard-core.md) — why emoji isn't an action panel
- [04-prediction](04-prediction.md) — emoji name suggestions in letter mode
- [10-extension-host](10-extension-host.md) — canvas swap wiring
