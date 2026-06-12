# Sound & haptics

## What it is

Per-keypress audio feedback and haptic impact. Two audio paths: bundled custom
samples (needs Full Access) and the system input click (works without). Haptics
always require Full Access — iOS restriction on keyboard extensions.

---

## Where it sits

```
KeyboardViewController
    ├── ClinkInputView (UIInputViewAudioFeedback)
    └── SoundPlayer.play(settings:hasFullAccess:)
            ├── AVAudioPlayer (custom pack)
            └── UIDevice.playInputClick() (system fallback)
```

---

## Files

| File | Role |
|---|---|
| `SoundPlayer.swift` | Playback + haptic generator; pre-loaded `AVAudioPlayer` cache |
| `SoundPack.swift` | Named sound pack definitions; sample filename lists |

Resources:

| Path | Role |
|---|---|
| `Resources/Sounds/` | Bundled `.caf` / `.wav` samples per pack |

App settings:

| File | Role |
|---|---|
| `SoundsView.swift` | Master toggle, volume slider, pack list |
| `SoundPickerView.swift` | Combined sound + haptics picker |
| `HapticsView.swift` | Per-keypress haptic toggle + style |

---

## How it works

### Two audio paths

| Path | When | Full Access |
|---|---|---|
| Custom pack | `settings.soundPackID` selects a bundled pack | Required |
| System click | Default, or fallback when pack samples missing | Not required |

Custom path: pre-loaded `AVAudioPlayer` instances keyed by filename — no disk
I/O on the hot path.

System path: `UIDevice.playInputClick()` via `UIInputViewAudioFeedback`
conformance on `ClinkInputView`. This is why Clink works completely without
Full Access for sound (standard click only).

### Haptics

`UIImpactFeedbackGenerator` with style from `KeyboardSettings.hapticStyle`
(light / medium / heavy / rigid / soft). Generator rebuilt lazily when style
changes; primed before first use.

Gated on `hasFullAccess` — iOS won't fire haptics from keyboard extensions
without it.

### Trigger point

`KeyboardCanvas` calls `onAnyTap` on every key-down. `KeyboardViewController`
wires this to `sound.play(settings:hasFullAccess:)`.

Separate from insert — fires even on function keys that commit on release.

### Volume

Custom pack playback respects `settings.soundVolume` (0…1). System click
volume is OS-controlled.

---

## Gotchas

- **Custom pack without bundled samples falls back to system click.** v0.1 shipped
  the pipeline ahead of curated audio — keyboard always feels responsive.

- **`UIInputViewAudioFeedback` must be on the input view itself**, not a subview.
  `ClinkInputView` subclass handles this.

- **AVAudioSession activation is lazy** — first custom play activates session;
  failure falls back silently.

- **Rotation through samples** — some packs have multiple click variants;
  `SoundPlayer.rotation` cycles for variety.

---

## Read order

1. `SoundPlayer.swift` — both paths in one file
2. `SoundPack.swift` — pack definitions
3. `KeyboardViewController.swift` — search `onAnyTap`, `ClinkInputView`

---

## See also

- [00-overview](00-overview.md) — Full Access privacy model
- [09-app-ui](09-app-ui.md) — settings screens
- [Resources/Sounds/README.md](../Resources/Sounds/README.md) — sample format notes
