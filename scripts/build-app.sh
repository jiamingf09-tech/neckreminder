#!/usr/bin/env bash
# Builds dist/NeckReminder.app as a single universal (arm64 + x86_64) binary.
#
#   VERSION=1.2.3 BUILD_NUMBER=42 scripts/build-app.sh
#
# Signing: ad-hoc by default. Set CODESIGN_IDENTITY to sign with a keychain identity:
#   "Developer ID Application: …"  → hardened runtime + secure timestamp, ready for notarization
#   a self-signed certificate name → stable identity, so macOS keeps granted permissions
#                                    across updates (see create-signing-cert.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="NeckReminder"
BUNDLE_ID="${BUNDLE_ID:-io.github.jiamingf09.NeckReminder}"
VERSION="${VERSION:-2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCHS="${ARCHS:-arm64 x86_64}"
IDENTITY="${CODESIGN_IDENTITY:--}"

ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER) for: $ARCHS"
swift build -c release "${ARCH_FLAGS[@]}" --product "$APP_NAME"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

DIST="dist"
APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" -e "s/__BUNDLE_ID__/$BUNDLE_ID/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"

echo "==> Rendering icon"
mkdir -p .build/tools
if xcrun swiftc -O scripts/make-icon.swift -o .build/tools/make-icon \
   && .build/tools/make-icon "$DIST/AppIcon.iconset" \
   && iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"; then
    rm -rf "$DIST/AppIcon.iconset"
else
    echo "warning: icon generation failed; continuing without an icon" >&2
fi

echo "==> Signing with identity: $IDENTITY"
SIGN_FLAGS=(--force --options runtime --sign "$IDENTITY")
# Apple's timestamp service is for Developer ID; self-signed and ad-hoc builds skip it.
if [[ "$IDENTITY" == "Developer ID"* ]]; then SIGN_FLAGS+=(--timestamp); fi
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
echo "==> Done: $APP"
