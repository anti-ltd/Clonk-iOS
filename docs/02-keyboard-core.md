# Keyboard core

## What it is

The letter/number keyboard itself: layout, key rendering, popups, suggestion bar
slot, panel overlays, and height calculation. `KeyboardCanvas` is the single
view both the app preview and the extension render — no second implementation.

---

## Where it sits

```
KeyboardViewController
    └── KeyboardCanvas
            ├── KeyboardController     (plane, shift, emoji flag)
            ├── KeyboardLiveState      (suggestions, active panel)
            ├── KeyTouchRouter         (multitouch → key IDs)
            ├── KeyView × N            (individual keys)
            ├── KeyGlyphLayer          (unified glyph pass)
            ├── KeyPopup               (press balloon)
            ├── SuggestionBar          (predictions + panel button)
            └── Panel overlays         (clipboard, notepad, calculator, …)
```

---

## Files

| File | Role |
|---|---|
| `KeyboardCanvas.swift` | Full keyboard composition; `KeyPressPhysics`; panel activation; insert/backspace choke points |
| `KeyboardController.swift` | `@Observable` session: letter/number/symbol plane, shift, caps lock, emoji mode |
| `KeyboardLayout.swift` | QWERTY / AZERTY / QWERTZ / Dvorak presets; shared number/symbol rows |
| `KeyboardLiveState.swift` | Per-keystroke output: `suggestions`, `autocorrection`, `activePanel`, emoji suggestions; `ActionPanel` enum |
| `KeyView.swift` | One key: fill, glass, bloom animation, space-bar trackpad lean |
| `KeyGlyphLayer.swift` | Preference-key layer — glyphs drawn above key backgrounds in one pass |
| `KeySpec.swift` | Key identity, label, action value — rebuilt when plane/shift changes |
| `KeyPopup.swift` | Magnified popup balloon; `KeyPopupKey` preference plumbing |
| `CustomKey.swift` | User-defined keys: insert text or trigger function actions |
| `InputViewHeight.swift` | Extension height diagnostics; tame encapsulated layout constraint |
| `SmartPunctuation.swift` | Curly quotes, em-dash, double-space→period — runs on insert path |

App preview:

| File | Role |
|---|---|
| `KeyboardPreview.swift` | `PinnedPreviewLayout`, `TabbedPreviewLayout`, themed chrome for settings screens |

---

## How it works

### Composition

`KeyboardCanvas.body` stacks:

1. Optional background (solid, gradient, or photo from `ThemeBackgroundStore`)
2. Suggestion bar row (predictions and/or panel icon)
3. Key rows from `KeyboardLayout` + custom rows
4. Optional panel overlay (clipboard, notepad, calculator, extensions, custom panels)
5. `KeyGlyphLayer` on top for crisp glyph rendering
6. `KeyPopup` for the currently pressed key
7. `MultiTouchSurface` (UIKit) covering the key grid

### KeyboardController state

| State | Meaning |
|---|---|
| `plane` | `.letters`, `.numbers`, `.symbols` |
| `shift` | `.off`, `.on`, `.locked` |
| `showEmoji` | Switches to `EmojiCanvas` at the view-controller level |

Plane + shift determine which `KeySpec` map is active. The canvas caches the
built map in `@State` so touch resolution is O(1).

### Insert/backspace choke points

Every key action funnels through two private methods:

```swift
private func insert(_ s: String) { … onInsert(s) … }
private func backspace() { … onBackspace() … }
```

Panel intercept happens here (notepad routes keys into scratch buffer).
Smart punctuation runs after insert. Both paths are the only way characters
reach the document — intercepting here captures all typing.

### KeyPressPhysics

User-tunable springs live in `KeyboardSettings` and pack into `KeyPressPhysics`
at render time. On Liquid Glass themes, bloom is softened and return is
critically damped — a full tuned bloom inside `GlassEffectContainer` drops
frames on A-series GPUs. See the comment block in `KeyboardCanvas.swift` lines 37–45.

Resolved through `MotionProfile` like fixed `Motion` tokens — see [MOTION.md](../MOTION.md).

### Height contract

`KeyboardCanvas.preferredHeight(for:hasFullAccess:)` computes extension height from:

- Base key row count (number row on/off)
- Suggestion bar presence (suggestions on, or panel icon with ≥1 enabled panel)
- Panel style (bar strips don't add height; overlays reuse existing frame)

`InputViewHeight` tames the system's encapsulated layout constraint so custom
height actually sticks.

### Action panels

Built-in panels hang off `ActionPanel` in `KeyboardLiveState`. Activation,
picker styles, and render branches live in `KeyboardCanvas`. Full walkthrough:
[EXTENDING.md](../EXTENDING.md).

---

## Gotchas

- **Per-cell glass on panel lists OOMs the extension.** Use one container-level
  material layer (`cardSurface` pattern in panel views), not `glassEffect` on every row.

- **Emoji is a separate canvas**, not an `ActionPanel` overlay. `activate(.emoji)` sets
  `controller.showEmoji = true`; the view controller swaps `EmojiCanvas` in.

- **`onNextKeyboard` is nil in the app preview** — globe key hidden in settings.

- **KeySpec cache invalidates on plane/shift/layout/custom-key changes only.** Touch
  routing reads the cache, not a live rebuild.

- **Space bar is special-cased in KeyView** — tap vs trackpad cursor drag, own spring knobs.

---

## Read order

1. `KeyboardCanvas.swift` — start at the struct doc comment, then `body`
2. `KeyboardController.swift` — small, clear state machine
3. `KeyView.swift` — how one key renders and animates
4. `KeyboardLayout.swift` — where rows come from
5. `KeyboardPreview.swift` — how the app embeds the canvas in settings

---

## See also

- [03-touch-and-input](03-touch-and-input.md) — multitouch routing
- [04-prediction](04-prediction.md) — suggestion bar content
- [05-emoji](05-emoji.md) — sibling canvas
- [EXTENDING.md](../EXTENDING.md) — adding panels
- [MOTION.md](../MOTION.md) — key press animation
