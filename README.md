<div align="center">

<img src="Resources/banner.png" alt="Clink">

<br>

<img src="https://raw.githubusercontent.com/opensourcevillain/resources/bc6072cd7f49dc155b47c88e79daa9d49ece9b7e/OpenSourceVillain/Banner.png" alt="Open Source Villain">

<br><br>

# Clink

**A fully customizable iOS keyboard.**

![Platform](https://img.shields.io/badge/iOS%2017%2B-black?style=flat-square)
![Language](https://img.shields.io/badge/Swift%206.0-orange?style=flat-square&logo=swift)
[![License](https://img.shields.io/badge/license-CLL%20v1.2-blue?style=flat-square)](LICENSE.md)
![Status](https://img.shields.io/badge/status-v1-brightgreen?style=flat-square)

![Offline-first](https://img.shields.io/badge/offline--first-✓-22c55e?style=flat-square)
![No accounts](https://img.shields.io/badge/no%20accounts-✓-22c55e?style=flat-square)
![One-time purchase](https://img.shields.io/badge/one--time%20purchase-✓-22c55e?style=flat-square)
![Private by default](https://img.shields.io/badge/no%20Full%20Access%20needed-✓-22c55e?style=flat-square)

</div>

---

> A custom iOS keyboard you can make completely your own — 30 built-in themes
> (including a Liquid Glass collection for iOS 26), four layouts, offline
> autocomplete and autocorrect, an emoji keyboard, clipboard history, a quick
> notepad, and a full custom-theme builder. Private by default: it works
> completely without Full Access, and never phones home. The iOS sibling of
> clonk-macos.

---

## Screenshots

<div align="center">

| Liquid Glass | Make it yours | Themes | Layouts |
|:---:|:---:|:---:|:---:|
| <img src="Resources/screenshots/glass.png" width="200" alt="Liquid Glass keyboard, mid-type"> | <img src="Resources/screenshots/hero.png" width="200" alt="Live in-app keyboard preview"> | <img src="Resources/screenshots/themes.png" width="200" alt="Theme gallery"> | <img src="Resources/screenshots/layout.png" width="200" alt="Layout & keys"> |

</div>

Regenerate with the [AppStage](../appstage) pipeline:

```bash
appstage capture clink && appstage build clink && appstage sync clink
```

It Debug-builds Clink, boots the iOS Simulator, routes the app to each screen
via `--appstage <slug>` launch args (seeding a curated theme so the live preview
looks its best), and writes device-framed PNGs into `Resources/screenshots/`.
The routing is `#if DEBUG` — none of it ships in Release.

---

## Features

**Themes**
- 30 built-in presets across dark, light, and six Liquid Glass variants (iOS 26)
- Custom theme builder: solid or Liquid Glass material, font design (sans / serif),
  per-color pickers, gradient editor (linear / radial, multi-stop), and photo backgrounds
- Export / import themes as `.clink` files; duplicate any preset as a starting point
- Match-system-appearance mode: separate light and dark theme, auto-switched

**Layouts & keys**
- Four layouts: QWERTY, AZERTY, QWERTZ, Dvorak
- Optional number row, home-row inset, adjustable key height / width / spacing / roundness
- Key popups: standard balloon or Liquid Glass bubble, position and size tunable
- Liquid key press: bloom + warp animation on each key; independently tunable springs

**Text**
- Offline autocomplete + autocorrect via `UITextChecker` — no network, no telemetry
- Smart punctuation: curly quotes, double-space to period, contraction apostrophes
- Auto-capitalize, auto-return-to-letters after symbols, configurable per preference

**Panels**
- Clipboard history: FIFO list, pin entries, bar or overlay display style
- Quick notepad: scratchpad buffer or saved-notes archive, drop text anywhere
- Full emoji keyboard with skin-tone picking, per-emoji tone memory, recents tab
- Panel switcher: tap the suggestion-bar icon or slide up on 123; cards or cycling picker

**Sound & haptics**
- Per-keypress sound packs; standard system click works without Full Access
- Volume slider, per-keypress haptics (requires Full Access)

**Cursor**
- Spacebar cursor: slide to move the cursor; three modes (slide / trackpad / combined)
- Configurable activation delay, scroll sensitivity, and line stride

---

## Architecture

Clink ships as **two targets plus shared code** — not a single app:

```
Clink (container app)  ──embeds──▶  ClinkKeyboard.appex (the keyboard)
        │                                   │
        └──────── App Group ────────────────┘
              group.ltd.anti.clink
     (settings written by app, read by keyboard; file-based, not UserDefaults)
```

- **`Clink`** — the App Store product: onboarding, enable flow, all settings,
  and a live interactive preview of the keyboard.
- **`ClinkKeyboard`** — a `UIInputViewController` extension; the keyboard that
  runs inside other apps.
- **`Sources/ClinkKit`** — shared code compiled into *both* targets (no dynamic
  framework, so no extension-embedding / rpath pitfalls). Includes
  **`KeyboardCanvas`** — the keyboard view itself — so the in-app preview is the
  *exact same SwiftUI view* the extension renders.

`SharedStore` persists `KeyboardSettings` as a JSON file in the App Group
container, not `UserDefaults(suiteName:)`. `cfprefsd` can return stale values
for minutes when the suite is written from one process and read from another;
file-based I/O reads the current bytes every time.

### Source layout

```
Sources/
├── ClinkKit/                       shared (compiled into both targets)
│   │
│   ├── Theme + theming
│   │   ├── Theme.swift             core value type (colors, material, font, gradients)
│   │   ├── ThemeTypes.swift        ThemeGradient, KeyMaterial, GlassVariant, font enums
│   │   ├── ThemePresets.swift      built-in preset catalog + default accessors
│   │   ├── Theme+<Name>.swift      one file per preset (30 total)
│   │   ├── RGBA.swift              Codable color bridging SwiftUI + UIKit
│   │   └── ThemeBackgroundStore.swift  App Group photo storage (down-scaled JPEGs)
│   │
│   ├── Settings + IPC
│   │   ├── KeyboardSettings.swift  the Codable config that crosses processes
│   │   └── SharedStore.swift       file-based App Group store + Darwin change-notify
│   │
│   ├── Keyboard core
│   │   ├── KeyboardCanvas.swift    ⭐ the full keyboard view (app + extension)
│   │   ├── KeyboardController.swift  shift / plane / emoji mode state
│   │   ├── KeyboardLiveState.swift   per-keystroke suggestion + panel state
│   │   ├── KeyboardLayout.swift    QWERTY / AZERTY / QWERTZ / Dvorak presets
│   │   ├── KeyTouchRouter.swift    multitouch routing for the key grid
│   │   ├── KeyView.swift           individual key rendering + bloom animation
│   │   ├── KeySpec.swift           key identity, label, and action value type
│   │   ├── KeyPopup.swift          pressed-key popup bubble
│   │   └── KeyGlyphLayer.swift     unified glyph-layer draw pass
│   │
│   ├── Autocomplete
│   │   ├── SuggestionEngine.swift  offline UITextChecker + Damerau-Levenshtein ranker
│   │   ├── SuggestionBar.swift     autocomplete / correction strip
│   │   └── SmartPunctuation.swift  curly quotes, double-space, contractions
│   │
│   ├── Emoji keyboard
│   │   ├── EmojiCanvas.swift       emoji keyboard (sibling of KeyboardCanvas)
│   │   ├── EmojiCell.swift         tappable emoji cell + long-press for skin tone
│   │   ├── EmojiBarTouchSurface.swift  UIKit touch surface for the emoji bar
│   │   ├── EmojiTabTapSurface.swift    UIKit touch surface for category tabs
│   │   ├── EmojiDeleteTile.swift   backspace tile with hold-to-repeat
│   │   ├── SkinTonePicker.swift    long-press skin-tone picker overlay
│   │   ├── EmojiSkinTone.swift     SkinTone enum + modifier application
│   │   ├── EmojiData.swift         EmojiCategory model + name-based search
│   │   └── EmojiData.generated.swift  full Unicode 16.0 emoji set (generated)
│   │
│   ├── Action panels
│   │   ├── ClipboardBar.swift      inline clipboard strip (bar style)
│   │   ├── ClipboardPanel.swift    full-keyboard clipboard overlay
│   │   ├── ClipboardManager.swift  FIFO history + pin / delete, persisted
│   │   ├── ClipboardEntry.swift    one clipboard entry + relative-time label
│   │   ├── NotepadBar.swift        inline notepad compose strip
│   │   ├── NotepadBrowsePanel.swift  full-keyboard saved-notes browser
│   │   ├── NotepadManager.swift    scratch buffer + notes archive, persisted
│   │   ├── NotepadNote.swift       one saved note
│   │   ├── PanelSwitcherPanel.swift  cards-style panel picker
│   │   └── ActionPanelButton.swift   suggestion-bar panel-open button
│   │
│   ├── Sound
│   │   ├── SoundPack.swift         named sound-pack definitions
│   │   └── SoundPlayer.swift       AVFoundation playback + haptics
│   │
│   └── Utilities
│       ├── SwipeRow.swift          swipe-to-reveal list row (clipboard / notepad)
│       ├── TrackpadPanel.swift     trackpad-mode move-glyph overlay
│       └── InputViewHeight.swift   tame UIView-Encapsulated-Layout-Height constraint
│
├── Clink/                          container app
│   ├── ClinkApp.swift              @main entry point
│   ├── AppModel.swift              app-wide observable state
│   ├── AppStage.swift              DEBUG marketing-capture routing
│   └── UI/
│       ├── RootView.swift          four-tab root (Style / Typing / Feel / Setup)
│       ├── KeyboardPreview.swift   live preview widget + PinnedPreviewLayout / TabbedPreviewLayout
│       ├── ThemeEditorView.swift   theme grid picker + export / import
│       ├── ThemeBuilderView.swift  custom theme editor sheet + GradientEditorView
│       ├── LayoutPickerView.swift  layout, size, popups, and feel tabs
│       ├── TypingView.swift        autocorrect + suggestions settings
│       ├── AdvancedSettingsView.swift  touch / spring / timing tuning with presets
│       ├── TuningPresets.swift     Preset type, named catalogs, PresetChips, TunedSection
│       ├── ClipboardHistoryView.swift  clipboard settings + history browser
│       ├── NotepadView.swift       notepad settings + note browser
│       ├── EmojiSettingsView.swift emoji preferences + skin-tone picker
│       ├── SoundPickerView.swift   sound pack list + volume + haptics
│       ├── EnableFlowView.swift    step-by-step setup guide
│       ├── BackupView.swift        export / import whole config as .clinkconfig
│       ├── ShowcaseView.swift      SHOWCASE: automated typing simulator for footage
│       └── StagedHeroView.swift    DEBUG: deterministic hero-shot for marketing
│
└── ClinkKeyboard/                  keyboard extension
    └── KeyboardViewController.swift  principal class: wires canvas, proxy, IPC, sound
```

---

## Privacy & Full Access

iOS custom keyboards can request **Full Access**, which shows a system warning.
Clink is **privacy-first**: it works completely without it (you get the standard
system click), and never transmits anything. Full Access is optional — iOS only
lets keyboard extensions fire haptics and read from the clipboard when it is
granted, so those two features ask for it. Nothing else does.

---

## Build

Requires **Xcode 16+** with the **iOS 17+ platform installed**, and `xcodegen`
(`brew install xcodegen`).

Depends on **[iUX-ios](../iUX-ios)** — shared iOS design system — via a local
path. Check it out as a sibling directory before building:

```
Projects/
├── clonk-ios/   ← this repo
└── iUX-ios/     ← shared iOS design system
```

```bash
make icon      # render the app icon from Tools/RenderAppIcon.swift
make project   # regenerate Clink.xcodeproj from project.yml (needs xcodegen)
make build     # xcodebuild for the iOS Simulator
make run       # boot the sim, install, launch
make device    # build, sign, install on the paired iPhone
make clean     # remove build/ and Clink.xcodeproj
make help      # list every target
```

`project.yml` is the source of truth — `.xcodeproj` is generated by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and gitignored. **Never edit
the generated `.xcodeproj` by hand.**

### Liquid Glass

Liquid Glass effects (`GlassEffectContainer`, `.glassEffect()`) are
`@available(iOS 26.0, *)` guarded throughout. The app deploys to iOS 17;
glass themes simply render a `.ultraThinMaterial` fallback on earlier OS versions.

### Generated files

`EmojiData.generated.swift` is produced from `Tools/emoji-test.txt` (Unicode 16.0)
by `Tools/GenerateEmojiData.swift`. Regenerate with `make emoji` — only needed
when updating the Unicode emoji set.

---

## Enabling the keyboard

1. **Settings → General → Keyboard → Keyboards → Add New Keyboard… → Clink**
2. Switch to it from any app by holding the 🌐 globe key.
3. *(Optional)* **Clink → Allow Full Access** for per-keypress haptics and
   clipboard history.

The in-app **Setup** screen walks through this and deep-links to Settings.

---

## Community

Questions, theme sharing, feedback, or just saying hi — join the Discord:

**[anti.ltd/discord](https://anti.ltd/discord)** · **[counter.ltd/discord](https://counter.ltd/discord)**

---

## License

Clink is source-available under the **Counter-Limitation License (CLL) v1.2** —
see [LICENSE.md](LICENSE.md).

© 2026 Anti Limited.
