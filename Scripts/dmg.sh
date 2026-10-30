#!/bin/sh
# Pack ".build/Activity Monitor X.app" into .build/AMX-<VERSION>.dmg, with a link to /Applications to drag it onto.
set -e
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
DMG=".build/AMX-$VERSION.dmg"
STAGE="$(mktemp -d)"
ditto ".build/Activity Monitor X.app" "$STAGE/Activity Monitor X.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from --format UDZO --volumeName "Activity Monitor X" "$STAGE" "$DMG" >/dev/null
rm -rf "${STAGE:?}"
echo "$DMG"
