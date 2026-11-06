#!/bin/sh
# Installs Activity Monitor X: curl -fsSL https://amx.henry.wang/install.sh | sh
# A download with curl gets no quarantine flag, so macOS opens the app at once. The script installs only a copy signed
# with the release certificate. The helper runs as root, so it goes to root-owned folders outside the app, and the
# script checks each root-owned copy after it makes it (D92). It asks for an administrator password one time.
set -eu
# The system tools, also under sudo, not ones that come first in the PATH.
PATH=/usr/bin:/bin:/usr/sbin:/sbin

URL="https://github.com/HenryQW/Activity-Monitor-X/releases/latest/download/AMX.dmg"
APP="/Applications/Activity Monitor X.app"
LABEL="com.henryqw.activitymonitorx.daemon"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
# SHA-1 of the "Activity Monitor X Release Signing" certificate (Scripts/make-release-cert.sh prints it). Another
# certificate can have the same name. A code requirement takes only a SHA-1, as the helper's own check of its callers
# does. The release workflow checks each release against it and puts it in the cask.
CERT="dd9656117fabc3f038c37c364c4a06b8623d4edf"

fail() { echo "$1" >&2; exit 1; }
# True when the code at $1 has a valid signature with the identifier $2 and the release certificate.
signed() { codesign --verify --strict -R="identifier \"$2\" and certificate leaf = H\"$CERT\"" "$1" 2>/dev/null; }

# In a function, so that a download that stops before the end runs nothing.
main() {
[ "$(uname -m)" = arm64 ] || fail "Activity Monitor X needs a Mac with Apple silicon."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ] || fail "Activity Monitor X needs macOS 26 or later."

TMP="$(mktemp -d)"
# A detach can fail while macOS still reads the image; -force then ends it.
trap 'hdiutil detach -quiet "$TMP/mnt" 2>/dev/null || hdiutil detach -quiet -force "$TMP/mnt" 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "Downloading Activity Monitor X..."
curl -fL --progress-bar "$URL" -o "$TMP/AMX.dmg"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$TMP/mnt" "$TMP/AMX.dmg"
NEW="$TMP/mnt/Activity Monitor X.app"

codesign --verify --deep --strict "$NEW" 2>/dev/null && signed "$NEW" com.henryqw.activitymonitorx \
    || fail "The download is not signed by Activity Monitor X. Nothing is installed."

# A running copy quits first, so the new one can replace it.
osascript -e 'quit app id "com.henryqw.activitymonitorx"' 2>/dev/null || true
rm -rf "$APP"
ditto "$NEW" "$APP" || fail "Cannot write to /Applications. Sign in as an administrator and try again."

echo "The helper records as root. Type your administrator password to install it."
# Root-owned, as is each folder above it, on every Mac; /usr/local can belong to the user (D92).
sudo mkdir -p /Library/PrivilegedHelperTools
sudo mkdir -p /usr/local/bin
# New names first: a copy that fails the check never replaces the helper that runs.
sudo install -m 755 -o root -g wheel "$NEW/Contents/MacOS/amxd" /Library/PrivilegedHelperTools/amxd.new
sudo install -m 755 -o root -g wheel "$NEW/Contents/MacOS/amx" /usr/local/bin/amx.new
if ! signed /Library/PrivilegedHelperTools/amxd.new "$LABEL" || ! signed /usr/local/bin/amx.new com.henryqw.activitymonitorx.amx; then
    sudo rm -f /Library/PrivilegedHelperTools/amxd.new /usr/local/bin/amx.new
    fail "The helper is not signed by Activity Monitor X. The app is installed, the helper is not."
fi
sudo mv -f /Library/PrivilegedHelperTools/amxd.new /Library/PrivilegedHelperTools/amxd
sudo mv -f /usr/local/bin/amx.new /usr/local/bin/amx

# From this script, not from the app: the property list says what root runs. The same as
# Packaging/com.henryqw.activitymonitorx.daemon.plist.
sudo tee "$PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Library/PrivilegedHelperTools/amxd</string>
	</array>
	<key>MachServices</key>
	<dict>
		<key>$LABEL</key>
		<true/>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ProcessType</key>
	<string>Background</string>
</dict>
</plist>
EOF
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
# bootout returns before the old helper exits; a bootstrap before that fails (EIO).
while sudo launchctl print "system/$LABEL" >/dev/null 2>&1; do sleep 0.2; done
sudo launchctl bootstrap system "$PLIST"

open "$APP"
echo "Activity Monitor X is installed. The helper records the history from now on."
}

main
