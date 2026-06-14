# Clink — build/run wrapper around xcodebuild. Mirrors sidekick-ios so the
# muscle memory carries across our apps.
#
#   make run     — build + launch in the simulator
#   make device  — build + install + launch on a paired iPhone
#
# Clink is a custom keyboard: the `Clink` scheme builds the container app AND
# embeds the `ClinkKeyboard` extension. To actually type with it you must enable
# it once in Settings → General → Keyboard → Keyboards → Add New Keyboard.
#
APP_NAME       := Clink
SCHEME         := Clink
BUNDLE_ID      := ltd.anti.clink

PROJECT        := Clink.xcodeproj
BUILD_DIR      := build
DERIVED        := $(BUILD_DIR)/DerivedData
CONFIG         ?= Debug

# Simulator selection. Override on the command line:
#   make run SIM_NAME="iPhone 16 Pro Max"
SIM_NAME       ?= iPhone 17 Pro
SIM_DEST       := "platform=iOS Simulator,name=$(SIM_NAME)"

# Device selection. Defaults to the lambda-ios phone (this project's test
# device); other paired iPhones — e.g. the SW-IOS-US remote unit — would
# otherwise win the name-less pick just by sorting first. Override with
# DEVICE=<udid> or DEVICE_NAME="My iPhone" (DEVICE_NAME= to pick any).
DEVICE         ?=
DEVICE_NAME    ?= lambda-ios

# App Store Connect distribution. Same API key clonk uses for notarytool; the
# .p8 lives outside the repo. memory: KZ765P9ZHP / issuer 66eec4bc-...
ASC_KEY_ID     ?= KZ765P9ZHP
ASC_ISSUER     ?= 66eec4bc-6987-480b-9af2-c26ea01d2ed2
ASC_KEY        ?= $(HOME)/.appstoreconnect/private_keys/AuthKey_$(ASC_KEY_ID).p8
ARCHIVE        := $(BUILD_DIR)/$(APP_NAME).xcarchive
EXPORT_DIR     := $(BUILD_DIR)/export
IPA            := $(EXPORT_DIR)/$(APP_NAME).ipa
EXPORT_OPTIONS := ExportOptions.plist

.PHONY: all project icon emoji lexicons build run sim install clean stop help test \
        device device-install device-launch build-device \
        device-showcase build-device-showcase \
        archive package validate-asc upload-asc bump

# Extra Swift compilation conditions for the showcase build. SHOWCASE flips the
# app's root to the typing-simulator screen (Sources/Clink/UI/ShowcaseView.swift);
# DEBUG is kept so the rest of the debug-only scaffolding still compiles.
SHOWCASE_CONDITIONS := DEBUG SHOWCASE

all: build

help:
	@echo "Simulator targets:"
	@echo "  make project — regenerate $(PROJECT) from project.yml (needs xcodegen)"
	@echo "  make icon    — render the app icon PNGs into Assets.xcassets"
	@echo "  make build   — xcodebuild for the iOS simulator"
	@echo "  make run     — boot the sim, install, launch Clink"
	@echo "  make stop    — terminate the running sim instance"
	@echo "  make test    — run unit tests on the simulator"
	@echo "  make clean   — remove $(BUILD_DIR) and $(PROJECT)"
	@echo ""
	@echo "Device targets (requires a paired, unlocked iPhone):"
	@echo "  make device         — build + install + launch Clink on the paired iPhone"
	@echo "  make device-install — build + install (no launch)"
	@echo "  make device-launch  — just relaunch the installed app"
	@echo ""
	@echo "Showcase target (typing-simulator build for demo capture):"
	@echo "  make device-showcase — build + install + launch the showcase build"
	@echo "                         on the paired iPhone (boots into the typer)"
	@echo ""
	@echo "Overrides:"
	@echo "  SIM_NAME=\"iPhone 16 Pro Max\"  pick a different simulator"
	@echo "  DEVICE=<udid>              pick a specific iPhone by UDID"
	@echo "  DEVICE_NAME=\"My iPhone\"     pick a specific iPhone by name"

# Render the app icon into Resources/Assets.xcassets via the standalone
# CoreGraphics script. The PNGs are a real build artifact that depends on the
# renderer, so editing RenderAppIcon.swift re-renders on the next build — the
# `build*` targets list $(ICON_OUT) as a prerequisite. `make icon` forces it.
ICON_SRC := Tools/RenderAppIcon.swift
ICON_OUT := Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png

$(ICON_OUT): $(ICON_SRC)
	swift Tools/RenderAppIcon.swift

icon: $(ICON_OUT)

# Regenerate Sources/ClinkKit/EmojiData.generated.swift (the full emoji set)
# from Tools/emoji-test.txt. Re-run after vendoring a newer emoji-test.txt.
emoji:
	swift Tools/GenerateEmojiData.swift

# Regenerate Resources/Lexicons/*.clex|*.cngm (frequency dictionaries + bigram
# models for the prediction engine) from the word lists under Tools/wordlists.
# The raw lists are gitignored — see Tools/wordlists/README.md for downloads.
lexicons:
	swift Tools/GenerateLexicons.swift

# Regenerate the xcodeproj from project.yml. XcodeGen is the source of truth.
project:
	@command -v xcodegen >/dev/null 2>&1 || { \
		echo "xcodegen not found. Install with: brew install xcodegen" >&2; exit 1; \
	}
	xcodegen generate
	@echo "Generated $(PROJECT)"

# Build for the iOS simulator. Generates the project on first run.
build: $(PROJECT) $(ICON_OUT)
	@mkdir -p $(BUILD_DIR)
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination $(SIM_DEST) \
		-derivedDataPath $(DERIVED) \
		build | xcbeautify --quiet 2>/dev/null || \
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination $(SIM_DEST) \
		-derivedDataPath $(DERIVED) \
		build

test: $(PROJECT)
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination $(SIM_DEST) \
		-derivedDataPath $(DERIVED) \
		test

# Boot the named simulator, install the freshly-built .app, launch it.
run: build
	@xcrun simctl boot "$(SIM_NAME)" 2>/dev/null || true
	@open -a Simulator
	@APP=$$(find $(DERIVED)/Build/Products -name "$(APP_NAME).app" -type d | head -n1); \
	if [ -z "$$APP" ]; then echo "No built .app found"; exit 1; fi; \
	xcrun simctl install "$(SIM_NAME)" "$$APP"; \
	xcrun simctl launch "$(SIM_NAME)" $(BUNDLE_ID)

stop:
	@xcrun simctl terminate "$(SIM_NAME)" $(BUNDLE_ID) 2>/dev/null || true

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)

# ============================================================
# Device deployment — wraps `xcrun devicectl`. The device must already be
# paired with this Mac (plug in once, accept "Trust", unlock).
# ============================================================
DEVICE_UDID = $(shell \
	if [ -n "$(DEVICE)" ]; then \
		echo "$(DEVICE)"; \
	else \
		xcrun devicectl list devices 2>/dev/null \
			| awk -v name="$(DEVICE_NAME)" '\
				/^----/ {next} \
				!/physical/ {next} \
				!/connected| available/ {next} \
				name != "" && index($$0, name) == 0 {next} \
				{ \
					if (match($$0, /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/)) { \
						print substr($$0, RSTART, RLENGTH); exit \
					} \
				}'; \
	fi)

build-device: $(PROJECT) $(ICON_OUT)
	@mkdir -p $(BUILD_DIR)
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates \
		build | xcbeautify --quiet 2>/dev/null || \
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates \
		build

device: device-install device-launch

device-install: build-device
	@if [ -z "$(DEVICE_UDID)" ]; then \
		echo ""; \
		echo "No paired iPhone found. Steps:" >&2; \
		echo "  1. Plug your phone in (or pair over Wi-Fi via Finder)." >&2; \
		echo "  2. Unlock it and accept the 'Trust This Computer' prompt." >&2; \
		echo "  3. Run: xcrun devicectl list devices" >&2; \
		echo "     If it lists the phone, re-run \`make device\`." >&2; \
		echo ""; \
		exit 1; \
	fi
	@APP=$$(find $(DERIVED)/Build/Products/Debug-iphoneos -name "$(APP_NAME).app" -type d | head -n1); \
	if [ -z "$$APP" ]; then echo "No iOS-device .app found in $(DERIVED)"; exit 1; fi; \
	echo "Installing $$APP to device $(DEVICE_UDID)..."; \
	xcrun devicectl device install app --device "$(DEVICE_UDID)" "$$APP"

device-launch:
	@if [ -z "$(DEVICE_UDID)" ]; then echo "No paired iPhone — see \`make device-install\`."; exit 1; fi
	@echo "Launching $(BUNDLE_ID) on $(DEVICE_UDID)..."
	xcrun devicectl device process launch --device "$(DEVICE_UDID)" "$(BUNDLE_ID)" || true

# ============================================================
# Showcase build — the typing-simulator demo build. Same device pipeline as
# `make device`, but compiled with the SHOWCASE condition so the app boots into
# ShowcaseView. Regenerates the project first so a freshly-added showcase source
# is always picked up.
# ============================================================
build-device-showcase: project $(ICON_OUT)
	@mkdir -p $(BUILD_DIR)
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS="$(SHOWCASE_CONDITIONS)" \
		build | xcbeautify --quiet 2>/dev/null || \
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS="$(SHOWCASE_CONDITIONS)" \
		build

device-showcase: build-device-showcase
	@if [ -z "$(DEVICE_UDID)" ]; then \
		echo ""; \
		echo "No paired iPhone found. Steps:" >&2; \
		echo "  1. Plug your phone in (or pair over Wi-Fi via Finder)." >&2; \
		echo "  2. Unlock it and accept the 'Trust This Computer' prompt." >&2; \
		echo "  3. Run: xcrun devicectl list devices" >&2; \
		echo "     If it lists the phone, re-run \`make device-showcase\`." >&2; \
		echo ""; \
		exit 1; \
	fi
	@APP=$$(find $(DERIVED)/Build/Products/Debug-iphoneos -name "$(APP_NAME).app" -type d | head -n1); \
	if [ -z "$$APP" ]; then echo "No iOS-device .app found in $(DERIVED)"; exit 1; fi; \
	echo "Installing showcase build $$APP to device $(DEVICE_UDID)..."; \
	xcrun devicectl device install app --device "$(DEVICE_UDID)" "$$APP"; \
	echo "Launching $(BUNDLE_ID) on $(DEVICE_UDID)..."; \
	xcrun devicectl device process launch --device "$(DEVICE_UDID)" "$(BUNDLE_ID)" || true

# ============================================================
# App Store Connect distribution. Mirrors clonk's MAS path, but iOS uses the
# xcodebuild archive → export → altool pipeline (no hand-assembled bundle).
# Signing is automatic: -allowProvisioningUpdates + the ASC API key let
# xcodebuild mint the Apple Distribution cert and App Store profiles headlessly.
#
#   make archive      — Release archive of the app + both keyboard extensions
#   make package      — export a distribution-signed .ipa from the archive
#   make validate-asc — dry-run the upload (catches most rejections, uploads nothing)
#   make upload-asc    — archive + package + validate + upload to App Store Connect
# ============================================================
archive: project
	@mkdir -p $(BUILD_DIR)
	rm -rf $(ARCHIVE)
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE) \
		-allowProvisioningUpdates \
		-authenticationKeyPath $(ASC_KEY) \
		-authenticationKeyID $(ASC_KEY_ID) \
		-authenticationKeyIssuerID $(ASC_ISSUER) \
		archive

package: $(EXPORT_OPTIONS)
	rm -rf $(EXPORT_DIR)
	# No -authenticationKey* here: the export's distribution signing is managed by
	# the Apple ID signed into Xcode (full signing rights). Passing the notary key
	# instead forces cloud signing through an under-scoped key and fails.
	xcodebuild \
		-exportArchive \
		-archivePath $(ARCHIVE) \
		-exportOptionsPlist $(EXPORT_OPTIONS) \
		-exportPath $(EXPORT_DIR) \
		-allowProvisioningUpdates
	@echo "Built $(IPA)"

validate-asc:
	xcrun altool --validate-app -f $(IPA) --type ios \
		--apiKey $(ASC_KEY_ID) --apiIssuer $(ASC_ISSUER)

upload-asc: archive package validate-asc
	xcrun altool --upload-app -f $(IPA) --type ios \
		--apiKey $(ASC_KEY_ID) --apiIssuer $(ASC_ISSUER)
	@echo "Uploaded $(APP_NAME) to App Store Connect."

bump:
	@CURRENT=$$(grep -m1 'CFBundleVersion:' project.yml | sed 's/[^0-9]//g'); \
	NEXT=$$(( CURRENT + 1 )); \
	sed -i '' "s/CFBundleVersion: \"$$CURRENT\"/CFBundleVersion: \"$$NEXT\"/g" project.yml; \
	echo "CFBundleVersion: $$CURRENT -> $$NEXT"
