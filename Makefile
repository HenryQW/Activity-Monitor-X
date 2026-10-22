.PHONY: build test clean cert sign install uninstall app install-app run-app dev-app run-dev

IDENTITY := Activity Monitor X Local Signing
LABEL := com.henryqw.activitymonitorx.daemon
PLIST := /Library/LaunchDaemons/$(LABEL).plist
BIN := .build/release
APP := .build/Activity Monitor X.app
APP_ID := com.henryqw.activitymonitorx
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

sign: build
	@security find-identity -v -p codesigning | grep -F "$(IDENTITY)" >/dev/null || { echo "error: identity '$(IDENTITY)' missing; run 'make cert' first" >&2; exit 1; }
	codesign --force --options runtime --timestamp=none --entitlements Packaging/amx.entitlements -s "$(IDENTITY)" -i $(LABEL) $(BIN)/amxd
	codesign --force --options runtime --timestamp=none --entitlements Packaging/amx.entitlements -s "$(IDENTITY)" -i com.henryqw.activitymonitorx.amx $(BIN)/amx

app: build
	@security find-identity -v -p codesigning | grep -F "$(IDENTITY)" >/dev/null || { echo "error: identity '$(IDENTITY)' missing; run 'make cert' first" >&2; exit 1; }
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp Packaging/Info.plist "$(APP)/Contents/Info.plist"
	cp Packaging/glossary.json Packaging/Credits.html "$(APP)/Contents/Resources/"
	cp $(BIN)/ActivityMonitorX "$(APP)/Contents/MacOS/ActivityMonitorX"
	codesign --force --options runtime --timestamp=none --entitlements Packaging/amx.entitlements -s "$(IDENTITY)" -i $(APP_ID) "$(APP)"

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
	rm -rf "/Applications/Activity Monitor X.app"
	ditto "$(APP)" "/Applications/Activity Monitor X.app"

run-app: install-app
	open "/Applications/Activity Monitor X.app"

# sudo only where root is needed: build and signing use the user's keychain.
install: sign install-app
	sudo install -d -m 755 -o root -g wheel /usr/local/libexec /usr/local/bin /Library/Logs/ActivityMonitorX
	sudo install -m 755 -o root -g wheel $(BIN)/amxd /usr/local/libexec/amxd
	sudo install -m 755 -o root -g wheel $(BIN)/amx /usr/local/bin/amx
	sudo install -m 644 -o root -g wheel Packaging/$(LABEL).plist $(PLIST)
	-sudo launchctl bootout system/$(LABEL)
	sudo launchctl bootstrap system $(PLIST)

uninstall:
	-sudo launchctl bootout system/$(LABEL)
	sudo rm -f $(PLIST) /usr/local/libexec/amxd /usr/local/bin/amx
	-osascript -e 'quit app "Activity Monitor X"'
	sudo rm -rf "/Applications/Activity Monitor X.app" /Library/Logs/ActivityMonitorX
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
	@echo "  remove it in System Settings > General > Login Items"
	@echo "Kept (signing certificate that 'make cert' created): $(IDENTITY)"
	@echo "  remove it with: security delete-identity -t -c \"$(IDENTITY)\""
	@echo "  or delete it in Keychain Access (login keychain, My Certificates)"
