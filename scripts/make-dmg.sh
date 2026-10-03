#!/usr/bin/env bash
# Packages dist/NeckReminder.app into a drag-to-Applications DMG.
#   scripts/make-dmg.sh dist/NeckReminder-1.0.0-universal.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist/NeckReminder.dmg}"
STAGE="$(mktemp -d)"
cp -R dist/NeckReminder.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "NeckReminder" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
rm -rf "$STAGE"
echo "==> $OUT"
