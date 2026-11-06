.PHONY: build test clean cert install uninstall app dmg install-app run-app dev-app run-dev

# CI signs releases with the release identity (Scripts/make-release-cert.sh): make app IDENTITY="Activity Monitor X Release Signing".
IDENTITY ?= Activity Monitor X Local Signing
LABEL := com.henryqw.activitymonitorx.daemon
PLIST := /Library/LaunchDaemons/$(LABEL).plist
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

# amxd and amx in the bundle are the copies that install.sh, the cask and `make install` put in root-owned folders;
# root never runs code from the bundle (D92). The helper and the CLI keep their own identifiers: the helper's XPC pin accepts the CLI by its identifier.
# The check takes untrusted matches too: CI imports the release identity without trust, and the pin compares certificates.
app: build
	@security find-identity -p codesigning | grep -F "$(IDENTITY)" >/dev/null || { echo "error: identity '$(IDENTITY)' missing; run 'make cert' first" >&2; exit 1; }
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp Packaging/Info.plist "$(APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $(VERSION)" -c "Add :CFBundleVersion string $(VERSION)" "$(APP)/Contents/Info.plist"
	cp Packaging/glossary.json Packaging/Credits.html Packaging/AppIcon.icns Packaging/henry.png "$(APP)/Contents/Resources/"
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

# Root-owned copies outside the user-writable bundle, as install.sh does (D92).
install: install-app
	sudo mkdir -p /Library/PrivilegedHelperTools
	sudo mkdir -p /usr/local/bin
	sudo install -m 755 -o root -g wheel "$(INSTALLED)/Contents/MacOS/amxd" /Library/PrivilegedHelperTools/amxd
	sudo install -m 755 -o root -g wheel "$(INSTALLED)/Contents/MacOS/amx" /usr/local/bin/amx
	sudo install -m 644 -o root -g wheel Packaging/$(LABEL).plist $(PLIST)
	-sudo launchctl bootout system/$(LABEL)
	# bootout returns before the old helper exits; a bootstrap before that fails (EIO).
	while sudo launchctl print system/$(LABEL) >/dev/null 2>&1; do sleep 0.2; done
	sudo launchctl bootstrap system $(PLIST)

uninstall:
	-sudo launchctl bootout system/$(LABEL)
	sudo rm -f $(PLIST) /Library/PrivilegedHelperTools/amxd /usr/local/bin/amx
	-osascript -e 'quit app id "$(APP_ID)"'
	rm -rf "$(INSTALLED)"
ifeq ($(PURGE),1)
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
