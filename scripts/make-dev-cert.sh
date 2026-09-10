#!/bin/zsh
# Creates a self-signed "Slant Dev" code signing certificate in the login keychain and
# trusts it for code signing. build.sh picks it up automatically, so rebuilt apps keep
# the same designated requirement and macOS keeps their Screen Recording grant.
set -euo pipefail
if security find-identity -v -p codesigning | grep -q '"Slant Dev"'; then
  echo "Slant Dev certificate already present"; exit 0
fi
DIR=$(mktemp -d)
cat > "$DIR/ext.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Slant Dev
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -days 3650 -config "$DIR/ext.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -out "$DIR/dev.p12" -passout pass:slant -name "Slant Dev" -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -out "$DIR/dev.p12" -passout pass:slant -name "Slant Dev"
security import "$DIR/dev.p12" -k ~/Library/Keychains/login.keychain-db -P slant -T /usr/bin/codesign -A
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$DIR/cert.pem"
rm -rf "$DIR"
security find-identity -v -p codesigning | grep "Slant Dev"
