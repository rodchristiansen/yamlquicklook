# Makefile for YAML Quick Look Extension

APP_NAME    = YamlQuickLook
SCHEME      = YamlQuickLook
INSTALL_PATH = /Applications
BUILD_DIR   = build/Build/Products/Release
APP_PATH    = $(BUILD_DIR)/$(APP_NAME).app
ZIP_FILE    = $(APP_NAME).zip

VERSION := $(shell TZ=America/Vancouver date +'%Y.%m.%d')

# Load .env if present (never committed — see .env.example)
-include .env
export

# Code signing — set in .env or pass on the command line
SIGNING_IDENTITY ?= $(APPLE_SIGNING_IDENTITY)
TEAM_ID          ?= $(APPLE_TEAM_ID)
NOTARY_PROFILE   ?= $(APPLE_NOTARY_PROFILE)
NOTARY_PROFILE   ?= notarization_credentials

# Colors
GREEN  = \033[0;32m
YELLOW = \033[1;33m
RED    = \033[0;31m
NC     = \033[0m

# -----------------------------------------------------------------------

all: build install register reset

help:
	@echo "$(GREEN)YamlQuickLook Build Targets:$(NC)"
	@echo "  $(YELLOW)build$(NC)         - Build unsigned release (for local dev/test)"
	@echo "  $(YELLOW)install$(NC)       - Copy built app to /Applications"
	@echo "  $(YELLOW)register$(NC)      - Register Quick Look extensions with pluginkit"
	@echo "  $(YELLOW)reset$(NC)         - Restart Finder and Quick Look daemon"
	@echo "  $(YELLOW)check$(NC)         - Show extension registration status"
	@echo "  $(YELLOW)release$(NC)       - Build signed, notarize, staple, and install"
	@echo "  $(YELLOW)setup-notary$(NC)  - Instructions for storing notarization credentials"
	@echo "  $(YELLOW)clean$(NC)         - Remove build artifacts"
	@echo "  $(YELLOW)uninstall$(NC)     - Remove app from /Applications"
	@echo ""
	@echo "$(GREEN)Required .env variables for make release:$(NC)"
	@echo "  $(YELLOW)APPLE_SIGNING_IDENTITY$(NC)"
	@echo "    Developer ID Application: Your Name (TEAMID)"
	@echo "  $(YELLOW)APPLE_TEAM_ID$(NC)"
	@echo "    Your 10-character Apple Developer Team ID"
	@echo "  $(YELLOW)APPLE_NOTARY_PROFILE$(NC)"
	@echo "    Keychain profile name (default: notarization_credentials)"
	@echo ""
	@echo "  Copy .env.example to .env and fill in your values."

build:
	@echo "$(GREEN)Building $(APP_NAME) (unsigned)...$(NC)"
	@rm -rf build
	xcodebuild -scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath build \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		clean build
	@echo "$(GREEN)Build complete$(NC)"

install:
	@echo "$(GREEN)Installing to $(INSTALL_PATH)...$(NC)"
	@rm -rf $(INSTALL_PATH)/$(APP_NAME).app
	@cp -R $(APP_PATH) $(INSTALL_PATH)/
	@echo "$(GREEN)Installed to $(INSTALL_PATH)/$(APP_NAME).app$(NC)"

register:
	@echo "$(GREEN)Registering extensions...$(NC)"
	@pluginkit -a $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/YamlQuickLookExtension.appex || true
	@pluginkit -a $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/YamlQuickLookThumbnailExtension.appex || true
	@echo "$(GREEN)Registration complete$(NC)"

reset:
	@echo "$(GREEN)Resetting Quick Look...$(NC)"
	@qlmanage -r
	@qlmanage -r cache
	@killall Finder 2>/dev/null || true
	@killall quicklookd 2>/dev/null || true
	@echo "$(GREEN)Ready. Press Space on a YAML file in Finder.$(NC)"

check:
	@echo "$(GREEN)Extension registration:$(NC)"
	@pluginkit -m -v | grep -A3 -i yaml || echo "Not registered"
	@echo ""
	@echo "$(GREEN)Installed location:$(NC)"
	@ls -la $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/*.appex 2>/dev/null || echo "Not found"

# -----------------------------------------------------------------------
# Signed release: build -> notarize -> staple -> install
# -----------------------------------------------------------------------

build-signed:
	@if [ -z "$(SIGNING_IDENTITY)" ]; then \
		echo "$(RED)Error: SIGNING_IDENTITY not set$(NC)"; \
		echo "Set APPLE_SIGNING_IDENTITY in .env or pass on the command line."; \
		exit 1; \
	fi
	@if [ -z "$(TEAM_ID)" ]; then \
		echo "$(RED)Error: TEAM_ID not set$(NC)"; \
		echo "Set APPLE_TEAM_ID in .env or pass on the command line."; \
		exit 1; \
	fi
	@echo "$(GREEN)Building signed $(APP_NAME) $(VERSION)...$(NC)"
	xcodebuild -scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath build \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		CODE_SIGN_IDENTITY="$(SIGNING_IDENTITY)" \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGNING_REQUIRED=YES \
		clean build
	@echo "$(GREEN)Verifying signature...$(NC)"
	codesign --verify --deep --verbose $(APP_PATH)
	@echo "$(GREEN)Build and sign complete$(NC)"

notarize: build-signed
	@echo "$(GREEN)Creating zip for notarization...$(NC)"
	@rm -f $(ZIP_FILE)
	ditto -c -k --keepParent $(APP_PATH) $(ZIP_FILE)
	@echo "$(YELLOW)Submitting for notarization (this may take a few minutes)...$(NC)"
	@echo "$(YELLOW)Using keychain profile: $(NOTARY_PROFILE)$(NC)"
	@if ! xcrun notarytool history --keychain-profile $(NOTARY_PROFILE) &>/dev/null; then \
		echo "$(RED)Error: Notarization profile '$(NOTARY_PROFILE)' not found$(NC)"; \
		echo "Run: make setup-notary"; \
		exit 1; \
	fi
	xcrun notarytool submit $(ZIP_FILE) \
		--keychain-profile $(NOTARY_PROFILE) \
		--wait
	@echo "$(GREEN)Stapling notarization ticket...$(NC)"
	xcrun stapler staple $(APP_PATH)
	@echo "$(GREEN)Verifying notarization...$(NC)"
	codesign --verify --deep --verbose $(APP_PATH)
	spctl -a -vvv -t install $(APP_PATH)
	@echo "$(GREEN)Notarization complete$(NC)"

release: notarize
	@echo "$(GREEN)Installing signed build to $(INSTALL_PATH)...$(NC)"
	@rm -rf $(INSTALL_PATH)/$(APP_NAME).app
	@cp -R $(APP_PATH) $(INSTALL_PATH)/
	pluginkit -a $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/YamlQuickLookExtension.appex || true
	pluginkit -a $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/YamlQuickLookThumbnailExtension.appex || true
	qlmanage -r && qlmanage -r cache
	killall Finder 2>/dev/null || true
	@echo "$(GREEN)Release complete: $(APP_NAME) $(VERSION)$(NC)"

setup-notary:
	@echo "$(GREEN)Notarization Setup Instructions:$(NC)"
	@echo ""
	@echo "1. Go to https://appleid.apple.com and generate an app-specific password"
	@echo "2. Store the credentials in your keychain:"
	@echo ""
	@echo "   $(YELLOW)xcrun notarytool store-credentials \\"
	@echo "     --apple-id YOUR_APPLE_ID \\"
	@echo "     --team-id $(TEAM_ID) \\"
	@echo "     $(NOTARY_PROFILE)$(NC)"
	@echo ""
	@echo "3. Copy .env.example to .env and fill in your values"
	@echo "4. Run: $(GREEN)make release$(NC)"

# -----------------------------------------------------------------------

clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf build
	@rm -f $(ZIP_FILE)
	@rm -rf ~/Library/Developer/Xcode/DerivedData/YAMLQuickLook-*
	@echo "$(GREEN)Clean complete$(NC)"

uninstall:
	@echo "$(YELLOW)Uninstalling...$(NC)"
	@pluginkit -r $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/YamlQuickLookExtension.appex 2>/dev/null || true
	@pluginkit -r $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/YamlQuickLookThumbnailExtension.appex 2>/dev/null || true
	@rm -rf $(INSTALL_PATH)/$(APP_NAME).app
	@$(MAKE) reset
	@echo "$(GREEN)Uninstalled$(NC)"

.PHONY: all help build install register reset check build-signed notarize release setup-notary clean uninstall
