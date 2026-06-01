<div align="center">

<img src="Resources/banner.png" alt="AppTemplate">

<br>

<img src="https://raw.githubusercontent.com/opensourcevillain/resources/bc6072cd7f49dc155b47c88e79daa9d49ece9b7e/OpenSourceVillain/Banner.png" alt="Open Source Villain">

<br><br>

# AppTemplate

**A new iOS app.**

![Platform](https://img.shields.io/badge/iOS%2017%2B-black?style=flat-square)
![Language](https://img.shields.io/badge/Swift%206.0-orange?style=flat-square&logo=swift)
[![License](https://img.shields.io/badge/license-CLL%20v1.2-blue?style=flat-square)](LICENSE.md)
![Status](https://img.shields.io/badge/status-alpha-yellow?style=flat-square)

![Offline-first](https://img.shields.io/badge/offline--first-✓-22c55e?style=flat-square)
![No accounts](https://img.shields.io/badge/no%20accounts-✓-22c55e?style=flat-square)
![One-time purchase](https://img.shields.io/badge/one--time%20purchase-✓-22c55e?style=flat-square)

</div>

---

> A new iOS app.

---

## Build

Requires **Xcode 16+** with the **iOS 17+ platform installed** (Xcode →
Settings → Components), and `xcodegen` (`brew install xcodegen`).

AppTemplate depends on **[iUX-ios](../iUX-ios)** — shared iOS design-system
library — via a local path. Check it out as a sibling directory before
building:

```
Projects/
├── ios-template/   ← this repo
└── iUX-ios/        ← shared iOS design system
```

```bash
git clone git@github.com:anti-ltd/iUX-ios.git ../iUX-ios   # one-time

make icon          # render and embed the app icon
make project       # regenerate AppTemplate.xcodeproj from project.yml (needs xcodegen)
make build         # xcodebuild for the iOS Simulator
make run           # boot the sim, install, launch
make device        # build, sign, install on the paired iPhone
make clean         # remove build/ and AppTemplate.xcodeproj
make help          # list every target
```

The `.xcodeproj` is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and is gitignored —
**`project.yml` is the source of truth**, never edit the generated
`.xcodeproj` by hand.

## Running on your iPhone

```bash
make device          # build, install, launch on the paired phone
make device-install  # build + install (no launch)
make device-launch   # re-launch what's already installed
```

`make device` wraps `xcrun devicectl`. Before the first run: cable the iPhone,
unlock it and accept **"Trust This Computer"**, then `xcrun devicectl list
devices` to confirm it's paired.

Codesigning uses Xcode automatic provisioning against Apple Developer team
`8248296AJX` (declared in `project.yml`). `make device` runs
`xcodebuild -allowProvisioningUpdates`, which auto-generates a development
profile for the bundle ID the first time it sees a new paired phone.

## Architecture

```
Sources/AppTemplate/
├── AppTemplateApp.swift     @main entry point
├── AppState.swift           observable app-wide state
├── AppStage.swift           DEBUG --appstage <state> deep-link (marketing capture)
├── ContentView.swift        root content view
└── UI/
    └── RootView.swift       root shell (iUXiOS.RootShell)
```

`Tools/RenderAppIcon.swift` is a standalone Swift script that renders the app
icon asset; run it via `make icon`.

`Resources/` holds the generated icon asset catalogue, banner, and any other
static assets bundled with the app.

## License

Source-available under the **Counter-Limitation License (CLL) v1.2** — see [LICENSE.md](LICENSE.md).

© 2026 Anti Limited.
