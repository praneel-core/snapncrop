#!/bin/bash
# One-time: creates a self-signed code-signing certificate called "Snapncrop Local Dev" in your
# login keychain, so every rebuild of Snapncrop has the SAME signature and macOS keeps the
# Screen Recording permission. The certificate never leaves your Mac and is only trusted for
# code signing. macOS will ask for your login password / keychain access during this.
set -euo pipefail
NAME="Snapncrop Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "'$NAME' already exists. Nothing to do."; exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# -legacy / -certpbe keep the .p12 readable by macOS's `security` tool (LibreSSL or OpenSSL 3).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/openssl.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# Homebrew's OpenSSL 3/4 needs -legacy so macOS's `security` can read the file; macOS's own
# LibreSSL doesn't know that flag, so fall back to the plain command.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" \
  -passout pass:snapncrop -name "$NAME" 2>/dev/null || \
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" \
  -passout pass:snapncrop -name "$NAME"

security import "$TMP/id.p12" -k "$KEYCHAIN" -P snapncrop -T /usr/bin/codesign
# Trust it for code signing only (this step shows a macOS password prompt).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Done. Verify with: security find-identity -p codesigning"
echo "The first ./build.sh may ask whether codesign can use the key: click 'Always Allow'."
