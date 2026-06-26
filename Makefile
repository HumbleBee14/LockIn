PROJECT := LockIn.xcodeproj
SCHEME  := LockIn
DEST    := platform=macOS
CONFIG  := Debug
DERIVED := build
APP     := $(DERIVED)/Build/Products/$(CONFIG)/LockIn.app

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "LockIn — common tasks"
	@echo "  make gen       Regenerate LockIn.xcodeproj from project.yml (run after adding files)"
	@echo "  make build     Build the signed app, daemon, and agent (installable)"
	@echo "  make test      Run all unit tests (daemon + app + agent)"
	@echo "  make run       Build and launch the app"
	@echo "  make release   Build, sign (Developer ID), notarize, and produce LockIn.dmg"
	@echo "  make clean     Remove build artifacts"
	@echo ""
	@echo "Signing uses the team set in project.yml. The system-level lock needs a"
	@echo "signed build to register the background blocker. See Tests/Validation/RISKS.md."
	@echo ""
	@echo "make release needs: a Developer ID Application cert in your keychain, plus"
	@echo "  APPLE_ID and APPLE_PASSWORD (app-specific) env vars for notarization, e.g."
	@echo "  make release APPLE_ID=you@example.com APPLE_PASSWORD=abcd-efgh-ijkl-mnop"

.PHONY: gen
gen:
	xcodegen generate

.PHONY: build
build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) build -allowProvisioningUpdates

.PHONY: test
test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		test CODE_SIGNING_ALLOWED=NO

.PHONY: run
run: build
	open "$(APP)"

RELEASE_APP := $(DERIVED)/Build/Products/Release/LockIn.app
TEAM_ID := 252N2WS4Y3
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo 0.0.0)

.PHONY: release
release: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) build \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
		DEVELOPMENT_TEAM=$(TEAM_ID) OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
		MARKETING_VERSION=$(VERSION)
	rm -rf "$(DERIVED)/dmg" "LockIn.dmg"
	mkdir -p "$(DERIVED)/dmg"
	cp -R "$(RELEASE_APP)" "$(DERIVED)/dmg/"
	ln -s /Applications "$(DERIVED)/dmg/Applications"
	hdiutil create -volname LockIn -srcfolder "$(DERIVED)/dmg" -ov -format UDZO "LockIn.dmg"
	xcrun notarytool submit "LockIn.dmg" --apple-id "$(APPLE_ID)" \
		--password "$(APPLE_PASSWORD)" --team-id $(TEAM_ID) --wait
	xcrun stapler staple "LockIn.dmg"
	@echo "Built and notarized LockIn.dmg"

# Developer-ID-signed build installed to /Applications for LOCAL daemon/enforcement testing.
# No notarization (that's only for distributing to other Macs). Gatekeeper may warn once on first open.
.PHONY: local
local: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) build \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
		DEVELOPMENT_TEAM=$(TEAM_ID) OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
		MARKETING_VERSION=$(VERSION)
	pkill -x LockIn 2>/dev/null || true
	rm -rf /Applications/LockIn.app
	cp -R "$(RELEASE_APP)" /Applications/LockIn.app
	@echo "Installed Developer-ID build to /Applications/LockIn.app — open it to test the real daemon"

.PHONY: clean
clean:
	rm -rf $(DERIVED)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean CODE_SIGNING_ALLOWED=NO >/dev/null 2>&1 || true
