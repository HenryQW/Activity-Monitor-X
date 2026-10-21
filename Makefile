.PHONY: build test clean cert sign install uninstall

IDENTITY := Activity Monitor X Local Signing
LABEL := com.henryqw.activitymonitorx.daemon
PLIST := /Library/LaunchDaemons/$(LABEL).plist
BIN := .build/release

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

# sudo only where root is needed: build and signing use the user's keychain.
install: sign
	sudo install -d -m 755 -o root -g wheel /usr/local/libexec /usr/local/bin /Library/Logs/ActivityMonitorX
	sudo install -m 755 -o root -g wheel $(BIN)/amxd /usr/local/libexec/amxd
	sudo install -m 755 -o root -g wheel $(BIN)/amx /usr/local/bin/amx
	sudo install -m 644 -o root -g wheel Packaging/$(LABEL).plist $(PLIST)
	-sudo launchctl bootout system/$(LABEL)
	sudo launchctl bootstrap system $(PLIST)

uninstall:
	-sudo launchctl bootout system/$(LABEL)
	sudo rm -f $(PLIST) /usr/local/libexec/amxd /usr/local/bin/amx
ifeq ($(PURGE),1)
	sudo rm -rf "/Library/Application Support/ActivityMonitorX"
endif
