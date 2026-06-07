#!/usr/bin/env bash
set -euo pipefail

# install-requirements.sh — set up everything needed to build Clink.
#
# Run once after cloning. Safe to re-run; each step checks before acting.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_DIR="$(dirname "$SCRIPT_DIR")"

# ── Xcode ────────────────────────────────────────────────────────────────────

echo "→ Checking Xcode..."
if ! xcode-select -p &>/dev/null; then
  echo "  Xcode not found. Install from the Mac App Store, then re-run."
  exit 1
fi

XCODE_VERSION=$(xcodebuild -version 2>/dev/null | awk 'NR==1{print $2}')
XCODE_MAJOR="${XCODE_VERSION%%.*}"
if [[ "$XCODE_MAJOR" -lt 16 ]]; then
  echo "  Xcode $XCODE_VERSION found — need 16+. Update via the Mac App Store."
  exit 1
fi
echo "  Xcode $XCODE_VERSION ✓"

# ── Homebrew ─────────────────────────────────────────────────────────────────

echo "→ Checking Homebrew..."
if ! command -v brew &>/dev/null; then
  echo "  Homebrew not found. Install from https://brew.sh, then re-run."
  exit 1
fi
echo "  Homebrew $(brew --version | head -1 | awk '{print $2}') ✓"

# ── XcodeGen ─────────────────────────────────────────────────────────────────

echo "→ Checking xcodegen..."
if ! command -v xcodegen &>/dev/null; then
  echo "  Installing xcodegen..."
  brew install xcodegen
else
  echo "  xcodegen $(xcodegen --version 2>/dev/null || echo 'installed') ✓"
fi

# ── iUX-ios sibling ──────────────────────────────────────────────────────────

echo "→ Checking iUX-ios..."
IUX_DIR="$PROJECTS_DIR/iUX-ios"
if [[ ! -d "$IUX_DIR" ]]; then
  echo "  iUX-ios not found at $IUX_DIR"
  echo "  Clone it as a sibling of this repo:"
  echo "    git clone <iUX-ios-url> \"$IUX_DIR\""
  exit 1
fi
echo "  iUX-ios found at $IUX_DIR ✓"

# ── iOS 17 platform ──────────────────────────────────────────────────────────

echo "→ Checking iOS 17+ platform..."
if xcrun simctl list runtimes 2>/dev/null | grep -q "iOS 1[789]"; then
  echo "  iOS platform ✓"
else
  echo "  No iOS 17+ simulator runtime found."
  echo "  Add one via Xcode → Settings → Platforms."
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "All requirements satisfied. Next steps:"
echo "  make icon     — render app icon"
echo "  make project  — generate Clink.xcodeproj"
echo "  make build    — build for simulator"
echo "  make device   — build + install on paired iPhone"
