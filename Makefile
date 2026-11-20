# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
LOCAL_CODESIGN_IDENTITY ?=
RUN_APP_NAME ?= VoiceInk
# Organisation edition "Undertone" (make org)
ORG_DERIVED_DATA := $(CURDIR)/.org-build
ORG_DIST_DIR ?= $(abspath $(CURDIR)/../dist)
ORG_APP_NAME := Undertone
MODEL ?= parakeet-tdt-0.6b-v3
MODEL_SERVER ?= https://huggingface.co
MODEL_ARCHIVE ?=
# Name of a (self-signed) code signing certificate in the login keychain. Empty = ad-hoc.
# A stable identity keeps the TCC permissions (microphone, accessibility) across app updates.
# Default: own certificate "Undertone Signing" (login keychain); "-" = ad-hoc.
ORG_SIGN_IDENTITY ?= Undertone Signing
# Sparkle update feed (appcast.xml + archives); Defaults/MDM key updateFeedBaseURL overrides it.
GITHUB_RELEASE_REPO ?= AlverichSven/undertone-releases
UPDATE_FEED_BASE ?= https://github.com/$(GITHUB_RELEASE_REPO)/releases/latest/download/
# CFBundleVersion, rises with every build.
ifeq ($(origin ORG_BUILD_NUMBER),undefined)
ORG_BUILD_NUMBER := $(shell date +%Y%m%d%H%M)
endif
# 1 = put MODEL (+ silero-vad) into Undertone.app/Contents/Resources/Models (default), 0 = app without model
ORG_BUNDLE_MODEL ?= 1
ORG_RELEASE_DIR := $(ORG_DIST_DIR)/release
ORG_PACKAGE := Undertone-Sprachmodell-$(MODEL).zip

.PHONY: all clean whisper setup build local org org-models org-release org-publish check healthcheck help dev run release release-setup

# Default target
all: check build

# Development workflow
dev: RUN_APP_NAME = VoiceInk Dev
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		build

# Build locally with stable Apple Development signing when available.
local: check setup
	@echo "Building VoiceInk for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	@SIGNING_IDENTITY="$(LOCAL_CODESIGN_IDENTITY)"; \
	if [ -z "$$SIGNING_IDENTITY" ]; then \
		SIGNING_IDENTITIES=$$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development: / { print $$2 }'); \
		SIGNING_IDENTITY_COUNT=$$(printf '%s\n' "$$SIGNING_IDENTITIES" | awk 'NF { count++ } END { print count + 0 }'); \
		if [ "$$SIGNING_IDENTITY_COUNT" -eq 1 ]; then \
			SIGNING_IDENTITY=$$(printf '%s\n' "$$SIGNING_IDENTITIES" | awk 'NF { print; exit }'); \
		elif [ "$$SIGNING_IDENTITY_COUNT" -gt 1 ]; then \
			echo "Multiple Apple Development identities found; set LOCAL_CODESIGN_IDENTITY to choose one; using ad-hoc signing"; \
		fi; \
	fi; \
	if [ -n "$$SIGNING_IDENTITY" ] && [ "$$SIGNING_IDENTITY" != "-" ]; then \
		SIGNING_REQUIRED=YES; \
		echo "Using stable local signing identity: $$SIGNING_IDENTITY"; \
	else \
		SIGNING_IDENTITY="-"; \
		SIGNING_REQUIRED=NO; \
		echo "Using ad-hoc signing (permissions may need approval after rebuilds)"; \
	fi; \
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="$$SIGNING_IDENTITY" \
		CODE_SIGNING_REQUIRED="$$SIGNING_REQUIRED" \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Release/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying VoiceInk.app to ~/Downloads..."; \
		rm -rf "$$HOME/Downloads/VoiceInk.app"; \
		ditto "$$APP_PATH" "$$HOME/Downloads/VoiceInk.app"; \
		xattr -cr "$$HOME/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/VoiceInk.app"; \
		echo "Run with: open ~/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Organisation build "Undertone" (ad-hoc signed, LOCAL_BUILD + ORG_EDITION).
#   make org [MODEL=parakeet-tdt-0.6b-v3|parakeet-ultra|cohere-transcribe] [MODEL_SERVER=https://...]
#            [MODEL_ARCHIVE=https://nexus.example/repository/raw/undertone]
# org/models.json (scripts/org_pack_models.sh) supplies the size/SHA-256 manifest for archive mode.
# Result: $(ORG_DIST_DIR)/Undertone.app (bundle id com.undertone.app). Nothing is copied to ~/Downloads.
org: check setup
	@echo "Building $(ORG_APP_NAME) (organisation edition, model $(MODEL), server $(MODEL_SERVER))..."
	@case "$(MODEL)" in parakeet-tdt-0.6b-v3|parakeet-ultra|cohere-transcribe) ;; \
		*) echo "MODEL must be parakeet-tdt-0.6b-v3, parakeet-ultra or cohere-transcribe"; exit 1 ;; esac
	@rm -rf "$(ORG_DERIVED_DATA)"
	@if [ -d "$(LOCAL_DERIVED_DATA)/SourcePackages" ]; then \
		echo "Reusing Swift package checkouts from .local-build"; \
		mkdir -p "$(ORG_DERIVED_DATA)"; \
		ditto "$(LOCAL_DERIVED_DATA)/SourcePackages" "$(ORG_DERIVED_DATA)/SourcePackages"; \
	fi
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
		-derivedDataPath "$(ORG_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD ORG_EDITION' \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		build
	@SRC_APP="$(ORG_DERIVED_DATA)/Build/Products/Release/VoiceInk.app"; \
	DEST_APP="$(ORG_DIST_DIR)/$(ORG_APP_NAME).app"; \
	test -d "$$SRC_APP" || { echo "Error: $$SRC_APP not found"; exit 1; }; \
	mkdir -p "$(ORG_DIST_DIR)"; \
	rm -rf "$(ORG_DIST_DIR)/$(ORG_APP_NAME).app"; \
	ditto "$$SRC_APP" "$$DEST_APP"; \
	echo "Removing VoiceInkRefineXPC (local AI post-processing is not part of the organisation build)..."; \
	rm -rf "$(ORG_DIST_DIR)/$(ORG_APP_NAME).app/Contents/XPCServices"; \
	UNDERTONE_BUILD_NUMBER="$(ORG_BUILD_NUMBER)" UNDERTONE_UPDATE_FEED_BASE="$(UPDATE_FEED_BASE)" \
		/usr/bin/python3 -I "$(CURDIR)/scripts/org_patch_bundle.py" "$$DEST_APP" "$(CURDIR)/VoiceInk/Localizable.xcstrings" "$(MODEL)" "$(MODEL_SERVER)" "$(MODEL_ARCHIVE)" "$(CURDIR)/org/models.json" || exit 1; \
	if [ "$(ORG_BUNDLE_MODEL)" = "1" ]; then \
		echo "Bundling model $(MODEL) into the app (sealed by the signature)..."; \
		/usr/bin/python3 -I "$(CURDIR)/scripts/org_bundle_model.py" "$$DEST_APP" "$(MODEL)" || exit 1; \
	else \
		echo "ORG_BUNDLE_MODEL=$(ORG_BUNDLE_MODEL): building without bundled model"; \
	fi; \
	xattr -cr "$$DEST_APP"; \
	echo "Signing with identity: $(or $(ORG_SIGN_IDENTITY),-)"; \
	"$(CURDIR)/scripts/org_sign_app.sh" "$$DEST_APP" "$(or $(ORG_SIGN_IDENTITY),-)" || exit 1; \
	codesign -dv "$$DEST_APP" 2>&1 | grep -E "^(Identifier|Authority|Signature)" || true; \
	codesign -dr - "$$DEST_APP" 2>&1 | grep designated || true; \
	echo ""; \
	echo "Build complete: $$DEST_APP"; \
	du -sh "$$DEST_APP"

# Optional model package (fallback only; the release ships the model inside the app):
# dist/models/Undertone-Sprachmodell-$(MODEL).zip. Existing packages matching org/models.json stay byte-identical.
org-models:
	@case "$(MODEL)" in parakeet-tdt-0.6b-v3|parakeet-ultra|cohere-transcribe) ;; \
		*) echo "MODEL must be parakeet-tdt-0.6b-v3, parakeet-ultra or cohere-transcribe"; exit 1 ;; esac
	"$(CURDIR)/scripts/org_pack_models.sh" --only "$(MODEL)"
	@ls -l "$(ORG_DIST_DIR)/models/$(ORG_PACKAGE)"

# Release for manual installation: dist/release/Undertone.zip = Undertone.app (model inside) + LIESMICH.txt.
# Fixed file name without version. Copy to a shared folder: scripts/org_publish_folder.sh <dir>
org-release: org
	@rm -f "$(ORG_RELEASE_DIR)"/Undertone-Sprachmodell-*.zip
	@VERSION=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$(ORG_DIST_DIR)/$(ORG_APP_NAME).app/Contents/Info.plist"); \
	BUILD=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$(ORG_DIST_DIR)/$(ORG_APP_NAME).app/Contents/Info.plist"); \
	STAGE="$(ORG_RELEASE_DIR)/.stage"; \
	rm -rf "$(ORG_RELEASE_DIR)/.stage"; \
	mkdir -p "$$STAGE"; \
	ditto "$(ORG_DIST_DIR)/$(ORG_APP_NAME).app" "$$STAGE/$(ORG_APP_NAME).app"; \
	sed -e "s/{{VERSION}}/$$VERSION ($$BUILD)/g" "$(CURDIR)/org/LIESMICH.txt" > "$$STAGE/LIESMICH.txt"; \
	rm -f "$(ORG_RELEASE_DIR)/$(ORG_APP_NAME).zip"; \
	ditto -c -k --norsrc --noextattr --noqtn "$$STAGE" "$(ORG_RELEASE_DIR)/$(ORG_APP_NAME).zip"; \
	rm -rf "$(ORG_RELEASE_DIR)/.stage"; \
	echo ""; \
	echo "Release $$VERSION ($$BUILD) in $(ORG_RELEASE_DIR):"; \
	cd "$(ORG_RELEASE_DIR)" && f="$(ORG_APP_NAME).zip" && \
		printf "%s\t%s Bytes\t%s\n" "$$f" "$$(stat -f %z "$$f")" "$$(shasum -a 256 "$$f" | cut -d' ' -f1)"

# Sparkle update: dist/updates/Undertone-<version>-<build>.zip + appcast.xml, upload to UPDATE_FEED_BASE.
#   make org-publish MODEL=parakeet-ultra            (needs org/RELEASE_NOTES.md)
#   make org-publish ... PUBLISH_ARGS=--no-upload    (only build archive + appcast locally)
org-publish: org-release
	GITHUB_RELEASE_REPO="$(GITHUB_RELEASE_REPO)" "$(CURDIR)/scripts/org_publish_update.sh" "$(ORG_DIST_DIR)/$(ORG_APP_NAME).app" "$(UPDATE_FEED_BASE)" $(PUBLISH_ARGS)

# Run application
run:
	@if [ -d "$$HOME/Downloads/$(RUN_APP_NAME).app" ]; then \
		echo "Opening ~/Downloads/$(RUN_APP_NAME).app..."; \
		open "$$HOME/Downloads/$(RUN_APP_NAME).app"; \
	else \
		echo "Looking for $(RUN_APP_NAME).app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "$(RUN_APP_NAME).app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "$(RUN_APP_NAME).app not found. Build it with 'make local' or use 'make dev' for the development app."; \
			exit 1; \
		fi; \
	fi

# Build a signed, notarized DMG and matching local Sparkle Appcast.
release: whisper
	@if [ -n "$(NOTES)" ]; then \
		./scripts/release.sh --notes "$(NOTES)" $(RELEASE_ARGS); \
	else \
		./scripts/release.sh $(RELEASE_ARGS); \
	fi

# Store Apple's notarization credentials securely in Keychain.
release-setup:
	@./scripts/setup-release-notarization.sh

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build locally with stable signing when available"
	@echo "    LOCAL_CODESIGN_IDENTITY=<SHA or name> overrides automatic Apple Development detection"
	@echo "  org                Build the organisation edition 'Undertone' into ../dist"
	@echo "    MODEL=<parakeet-tdt-0.6b-v3|parakeet-ultra|cohere-transcribe> MODEL_SERVER=<url> MODEL_ARCHIVE=<url>"
	@echo "    ORG_SIGN_IDENTITY=<keychain certificate name> (default: Undertone Signing, - = ad-hoc)"
	@echo "    UPDATE_FEED_BASE=<url/> ORG_BUILD_NUMBER=<n>"
	@echo "  org-publish        org-release + Sparkle update archive + appcast.xml, upload to UPDATE_FEED_BASE"
	@echo "  org-models         Optional model package for MODEL into ../dist/models (fallback)"
	@echo "  org-release        org, then ../dist/release/Undertone.zip (app with model + LIESMICH.txt)"
	@echo "    ORG_BUNDLE_MODEL=0 builds the app without the model"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  release            Build DMG and Appcast using release-notes/<version>.html"
	@echo "  release-setup      Store notarization credentials in Keychain"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
