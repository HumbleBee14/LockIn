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
	@echo "  make build     Build the app, daemon, and agent (unsigned, fast)"
	@echo "  make signed    Build code-signed so the daemon can install (real lock)"
	@echo "  make test      Run all unit tests (daemon + app + agent)"
	@echo "  make run       Build and launch the app"
	@echo "  make clean     Remove build artifacts"
	@echo ""
	@echo "Note: the real system-level lock needs Developer ID signing + install."
	@echo "An unsigned build runs the UI and all tests, but cannot register the"
	@echo "background blocker. See Tests/Validation/RISKS.md."

.PHONY: gen
gen:
	xcodegen generate

.PHONY: build
build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) build CODE_SIGNING_ALLOWED=NO

.PHONY: signed
signed: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) build -allowProvisioningUpdates

.PHONY: test
test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		test CODE_SIGNING_ALLOWED=NO

.PHONY: run
run: build
	open "$(APP)"

.PHONY: clean
clean:
	rm -rf $(DERIVED)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean CODE_SIGNING_ALLOWED=NO >/dev/null 2>&1 || true
