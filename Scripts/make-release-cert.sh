#!/bin/bash
# Creates the release signing identity as a PKCS#12 file for the release workflow (D91): RELEASE_CERT_P12 (base64) and
# RELEASE_CERT_PASSWORD. It writes only to a new temporary folder, never to the repository or a keychain.
set -euo pipefail

NAME="Activity Monitor X Release Signing"
# System LibreSSL: its default p12 encryption is readable by `security import`.
OPENSSL=/usr/bin/openssl

out=$(mktemp -d)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
umask 077
export P12_PASS
P12_PASS=$("$OPENSSL" rand -hex 16)

"$OPENSSL" req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem"

"$OPENSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -name "$NAME" -out "$out/release.p12" -passout env:P12_PASS

echo "Identity '$NAME' is in $out/release.p12."
echo "Keep a copy in your password manager: a new identity changes the release signature. Then delete the folder."
echo
echo "Secret RELEASE_CERT_PASSWORD:"
echo "$P12_PASS"
echo
echo "Secret RELEASE_CERT_P12:"
base64 -i "$out/release.p12"
