#!/usr/bin/env bash
# Creates a free, self-signed code-signing certificate for CI builds.
#
# Why: macOS remembers privacy permissions per *signing identity*.
# Ad-hoc signed builds get a new identity on every build, so after each update macOS
# forgets the permission. Signing every build with the same self-signed certificate keeps
# it stable. (Gatekeeper still treats the app as from an unidentified developer — that
# only goes away with a paid Apple Developer ID + notarization.)
#
# Usage: scripts/create-signing-cert.sh ["Certificate Name"] [output-dir]
# Then add the three printed values as GitHub repository secrets.
set -euo pipefail

NAME="${1:-NeckReminder Self-Signed}"
OUT="${2:-signing-cert}"
mkdir -p "$OUT"
cd "$OUT"

PASSWORD="$(openssl rand -base64 18 | tr -d '/+=')"

cat > cert.cnf <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf 2>/dev/null

# macOS' keychain import wants the legacy PKCS#12 algorithms; OpenSSL 3 needs -legacy for that.
LEGACY=()
if openssl version | grep -q '^OpenSSL 3'; then LEGACY=(-legacy); fi
openssl pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -inkey key.pem -in cert.pem -name "$NAME" \
    -out cert.p12 -passout "pass:$PASSWORD"
base64 < cert.p12 | tr -d '\n' > cert.p12.base64
rm -f key.pem cert.cnf

cat <<MSG

Created $OUT/cert.p12 (valid for 10 years).

Add these GitHub repository secrets (Settings › Secrets and variables › Actions):

  MACOS_CERTIFICATE_P12       contents of $OUT/cert.p12.base64
  MACOS_CERTIFICATE_PASSWORD  $PASSWORD
  MACOS_SIGNING_IDENTITY      $NAME

Keep cert.p12 and the password private (a password manager is a good place) and do not
commit this folder. If you lose them, create a new certificate — macOS will then ask
for permissions once more.
MSG
