#!/bin/sh
# Pack ".build/Activity Monitor X.app" into .build/AMX-<VERSION>.dmg, with a link to /Applications to drag it onto and a
# note that says to install with the install line: a dragged app has no helper (D92).
set -e
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
DMG=".build/AMX-$VERSION.dmg"
STAGE="$(mktemp -d)"
ditto ".build/Activity Monitor X.app" "$STAGE/Activity Monitor X.app"
cp "Packaging/dmg/Read me first.txt" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from --format UDZO --volumeName "Activity Monitor X" "$STAGE" "$DMG" >/dev/null
rm -rf "${STAGE:?}"
echo "$DMG"
