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
![Status](https://img.shields.io/badge/status-alpha-yellow?style=flat-square)

![Offline-first](https://img.shields.io/badge/offline--first-✓-22c55e?style=flat-square)
![No accounts](https://img.shields.io/badge/no%20accounts-✓-22c55e?style=flat-square)
![One-time purchase](https://img.shields.io/badge/one--time%20purchase-✓-22c55e?style=flat-square)
![Private by default](https://img.shields.io/badge/no%20Full%20Access%20needed-✓-22c55e?style=flat-square)

</div>

---

> A custom iOS keyboard you can make your own — themes, layouts, and a real
> Liquid Glass variant, with offline autocomplete and auto-correct. Private by
> default: it works fully without Full Access, and never phones home. The iOS
> sibling of clonk-macos.

---

## Screenshots

<div align="center">

| Liquid Glass | Make it yours | Themes | Layouts |
|:---:|:---:|:---:|:---:|
| <img src="Resources/screenshots/glass.png" width="200" alt="Liquid Glass keyboard, mid-type"> | <img src="Resources/screenshots/hero.png" width="200" alt="Live in-app keyboard preview"> | <img src="Resources/screenshots/themes.png" width="200" alt="Theme gallery"> | <img src="Resources/screenshots/layout.png" width="200" alt="Layout & keys"> |

</div>

Regenerate these with the [AppStage](../appstage) pipeline — `appstage capture
clink && appstage build clink && appstage sync clink`. It Debug-builds Clink,
boots the iOS Simulator, routes the app to each screen via its DEBUG
`--appstage <slug>` launch arg (seeding a curated theme so the live preview looks
its best), and writes the device-framed PNGs into `Resources/screenshots/`. The
routing is `#if DEBUG`, so none of it ships in Release.

---

## Architecture

Clink is a custom keyboard, so it ships as **two targets plus shared code** —
not a single app:

```
Clink (container app)  ──embeds──▶  ClinkKeyboard.appex (the keyboard)
        │                                   │
        └──────── App Group ────────────────┘
              group.ltd.anti.clink
        (settings written by the app, read by the keyboard)
```

- **`Clink`** — the App Store product. Onboarding / enable flow plus the
  theme, layout and sound & haptics settings, with a live, interactive preview.
- **`ClinkKeyboard`** — a `UIInputViewController` extension; the keyboard that
  runs inside other apps.
- **`Sources/ClinkKit`** — shared, UI-and-model code compiled into *both*
  targets (no dynamic framework, so no extension embedding/rpath pitfalls).
  Crucially this includes **`KeyboardCanvas`**, the SwiftUI keyboard itself —
  so the in-app preview is the *exact same view* the extension renders.

The two processes are isolated; they share state only through the App Group's
`UserDefaults` suite (`SharedStore`).

```
Sources/
├── ClinkKit/                 shared (compiled into both targets)
│   ├── KeyboardSettings.swift   the Codable config that crosses processes
│   ├── SharedStore.swift        App Group store + Darwin change-notify
│   ├── Theme.swift              color themes + presets
│   ├── KeyboardLayout.swift     QWERTY / AZERTY / QWERTZ / Dvorak
│   ├── SoundPack.swift          sound-pack definitions (system click)
│   ├── RGBA.swift               Codable color
│   └── KeyboardCanvas.swift     ⭐ the keyboard view (app + extension)
├── Clink/                    container app
│   ├── ClinkApp.swift  AppModel.swift
│   └── UI/  RootView · ThemeEditor · LayoutPicker · SoundPicker · EnableFlow · KeyboardPreview
└── ClinkKeyboard/            extension
    ├── KeyboardViewController.swift   hosts KeyboardCanvas, wires the document proxy
    └── SoundPlayer.swift              system-click playback + per-keypress haptics
```

## Privacy & Full Access

iOS custom keyboards can request **Full Access**, which shows a scary system
warning. Clink is **privacy-first**: it works completely without it (you get
the standard system click), and never transmits anything. Full Access is an
**optional opt-in** — iOS only lets a keyboard extension fire **haptics** when
it's granted, so the per-keypress haptic asks for it. Nothing else does.

## Build

Requires **Xcode 16+** with the **iOS 17+ platform installed**, and `xcodegen`
(`brew install xcodegen`).

Depends on **[iUX-ios](../iUX-ios)** — our shared iOS design system — via a
local path. Check it out as a sibling directory before building:

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

`project.yml` is the source of truth — the `.xcodeproj` is generated by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and gitignored. **Never edit
the generated `.xcodeproj` by hand.**

## Enabling the keyboard

A custom keyboard can't be used until the user enables it once:

1. **Settings → General → Keyboard → Keyboards → Add New Keyboard… → Clink**
2. Switch to it from any app by holding the 🌐 globe key.
3. *(Optional)* tap **Clink → Allow Full Access** for per-keypress haptics.

The in-app **Setup** screen walks through this and deep-links to Settings.

## Sound & haptics

Every keypress plays the standard iOS click — adjustable volume, no Full Access
required — with an optional per-keypress haptic (which iOS only permits with
Full Access). Tune both from the in-app **Sound & Feel** screen.

## Roadmap

- **v0.1** (this) — working keyboard + themes + layouts + system click & haptics.
- **v0.2** — user-authored themes, key-popup polish, emoji plane, one-handed mode.

## License

Clink is source-available under the **Counter-Limitation License (CLL) v1.2** —
see [LICENSE.md](LICENSE.md).

© 2026 Anti Limited.
