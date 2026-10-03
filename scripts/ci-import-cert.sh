#!/usr/bin/env bash
# CI helper: imports a signing certificate into a temporary keychain.
# Env: P12 (base64 .p12), P12_PASSWORD, IDENTITY (certificate name), RUNNER_TEMP.
set -euo pipefail
KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
echo "$P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
rm "$RUNNER_TEMP/cert.p12"
if [[ "$IDENTITY" != "Developer ID"* ]]; then
  # A self-signed certificate must be trusted for code signing on this runner.
  security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$RUNNER_TEMP/cert.pem"
  sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$RUNNER_TEMP/cert.pem"
fi
security find-identity -p codesigning "$KEYCHAIN"
