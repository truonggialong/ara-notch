#!/bin/bash
# Creates a self-signed code signing certificate named "AraNotch Dev" in your login keychain.
#
# Why: with a fixed certificate the app keeps the same identity across builds, so macOS keeps
# its Accessibility and other permissions. Scripts/build-app.sh uses it automatically.
#
# What it does, and nothing else:
#   1. makes a new private key and a certificate for it, in a temporary folder;
#   2. imports the two into your login keychain, letting /usr/bin/codesign use the key;
#   3. deletes the temporary folder.
# The certificate is only on this Mac and is only good for signing code locally.
# To undo: delete "AraNotch Dev" (certificate and key) in Keychain Access.
set -euo pipefail

NAME="${ARANOTCH_SIGN_IDENTITY:-AraNotch Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
    echo "A certificate named \"$NAME\" already exists. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
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
EOF

# Valid for ten years.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.conf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# The import wants one password-protected file; the password is random and thrown away.
PASSWORD="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign

echo
echo "Done. Code signing identities now:"
security find-identity -p codesigning | sed -n '1,6p'
