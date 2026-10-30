.PHONY: build test clean cert install uninstall app dmg install-app run-app dev-app run-dev

# CI signs releases with the release identity (Scripts/make-release-cert.sh): make app IDENTITY="Activity Monitor X Release Signing".
IDENTITY ?= Activity Monitor X Local Signing
LABEL := com.henryqw.activitymonitorx.daemon
BIN := .build/release
# The one place the version lives; `make app` writes it into the bundle, and AMX.version must match (a test checks).
VERSION := $(shell cat VERSION)
APP := .build/Activity Monitor X.app
APP_ID := com.henryqw.activitymonitorx
CLI_ID := com.henryqw.activitymonitorx.amx
INSTALLED := /Applications/Activity Monitor X.app
DEV_APP := .build/Activity Monitor X Dev.app
DEV_ID := com.henryqw.activitymonitorx.dev

build:
	swift build -c release

test:
	swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

clean:
	swift package clean

cert:
	Scripts/make-cert.sh

# The helper and the CLI in the bundle keep their own identifiers: the helper's XPC pin accepts the CLI by its identifier.
# The check takes untrusted matches too: CI imports the release identity without trust, and the pin compares certificates.
app: build
	@security find-identity -p codesigning | grep -F "$(IDENTITY)" >/dev/null || { echo "error: identity '$(IDENTITY)' missing; run 'make cert' first" >&2; exit 1; }
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" "$(APP)/Contents/Library/LaunchDaemons"
	cp Packaging/Info.plist "$(APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $(VERSION)" -c "Add :CFBundleVersion string $(VERSION)" "$(APP)/Contents/Info.plist"
	cp Packaging/glossary.json Packaging/Credits.html Packaging/AppIcon.icns "$(APP)/Contents/Resources/"
	cp Packaging/$(LABEL).plist "$(APP)/Contents/Library/LaunchDaemons/"
	cp $(BIN)/ActivityMonitorX $(BIN)/amxd $(BIN)/amx "$(APP)/Contents/MacOS/"
	codesign --force --options runtime --timestamp=none --entitlements Packaging/amx.entitlements -s "$(IDENTITY)" -i $(LABEL) "$(APP)/Contents/MacOS/amxd"
	codesign --force --options runtime --timestamp=none --entitlements Packaging/amx.entitlements -s "$(IDENTITY)" -i $(CLI_ID) "$(APP)/Contents/MacOS/amx"
	codesign --force --options runtime --timestamp=none --entitlements Packaging/amx.entitlements -s "$(IDENTITY)" -i $(APP_ID) "$(APP)"

# The release disk image, .build/AMX-<VERSION>.dmg.
dmg: app
	Scripts/dmg.sh

# A dev build with its own identity and name, for checks while the installed app runs.
dev-app: app
	rm -rf "$(DEV_APP)"
	ditto "$(APP)" "$(DEV_APP)"
	rm -rf "$(APP)"
	plutil -replace CFBundleIdentifier -string $(DEV_ID) "$(DEV_APP)/Contents/Info.plist"
	plutil -replace CFBundleName -string "Activity Monitor X Dev" "$(DEV_APP)/Contents/Info.plist"
	plutil -replace CFBundleDisplayName -string "Activity Monitor X Dev" "$(DEV_APP)/Contents/Info.plist"
	codesign --force --options runtime --timestamp=none --entitlements Packaging/amx.entitlements -s "$(IDENTITY)" -i $(DEV_ID) "$(DEV_APP)"

# One dev build at a time on this Mac: waits for the others, runs until the app quits, then unregisters it.
run-dev: dev-app
	Scripts/run-dev.sh "$(CURDIR)/$(DEV_APP)"

install-app: app
	rm -rf "$(INSTALLED)"
	ditto "$(APP)" "$(INSTALLED)"

run-app: install-app
	open "$(INSTALLED)"

# No root: the app registers its bundled helper with launchd at its first launch, and macOS asks the owner to allow it
# in Login Items (D91).
install: install-app
	@if [ -e /Library/LaunchDaemons/$(LABEL).plist ]; then \
		echo "The helper from an older install still runs. Remove it once, then open the app:"; \
		echo "  sudo launchctl bootout system/$(LABEL)"; \
		echo "  sudo rm -f /Library/LaunchDaemons/$(LABEL).plist /usr/local/libexec/amxd"; \
	fi
	@if [ -w /usr/local/bin ]; then \
		ln -sf "$(INSTALLED)/Contents/MacOS/amx" /usr/local/bin/amx && echo "Linked /usr/local/bin/amx"; \
	else \
		echo "/usr/local/bin is not writable. To link amx, run:"; \
		echo "  sudo mkdir -p /usr/local/bin && sudo ln -sf \"$(INSTALLED)/Contents/MacOS/amx\" /usr/local/bin/amx"; \
	fi
	@echo "Open $(INSTALLED), then turn it on in System Settings > General > Login Items & Extensions > Allow in the Background."

# The helper is registered by the app, so only the owner can remove it: these are the steps.
uninstall:
	@echo "To remove Activity Monitor X:"
	@echo "  1. Quit Activity Monitor X."
	@echo "  2. In System Settings > General > Login Items & Extensions, turn off Activity Monitor X under Allow in the Background. The helper stops."
	@echo "  3. Move $(INSTALLED) to the Trash."
	@echo "  4. If you linked amx: rm /usr/local/bin/amx"
ifeq ($(PURGE),1)
	@! pgrep -x amxd >/dev/null || { echo "error: the helper runs; do step 2, then run 'make uninstall PURGE=1' again" >&2; exit 1; }
	sudo rm -rf "/Library/Application Support/ActivityMonitorX"
else
	@echo "Kept (history database and daemon settings): /Library/Application Support/ActivityMonitorX"
	@echo "  remove it with: make uninstall PURGE=1"
endif
	@echo "Kept (your groups): ~/Library/Application Support/ActivityMonitorX/groups.json"
	@echo "  remove it with: rm ~/Library/'Application Support'/ActivityMonitorX/groups.json"
	@echo "Kept (app settings): the $(APP_ID) defaults"
	@echo "  remove them with: defaults delete $(APP_ID)"
	@echo "Kept (login item, if you turned on Launch at Login):"
	@echo "  remove it in System Settings > General > Login Items & Extensions"
	@echo "Kept (signing certificate that 'make cert' created): $(IDENTITY)"
	@echo "  remove it with: security delete-identity -t -c \"$(IDENTITY)\""
	@echo "  or delete it in Keychain Access (login keychain, My Certificates)"
