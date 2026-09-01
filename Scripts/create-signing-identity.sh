#!/usr/bin/env bash

# Create the local self-signed code-signing identity that `make install` uses.
#
# Why this exists: an ad-hoc signature's designated requirement is the binary's
# own CDHash, so every rebuild produces a different code identity. Keychain
# "Always Allow" decisions are stored against that requirement, which means an
# ad-hoc build has to re-ask for every credential after every build.
#
# Signing with a certificate instead gives a designated requirement based on the
# certificate's identifier and subject, which does not change when the binary
# does. Approving a credential once then holds across rebuilds.
#
# This certificate is self-signed and local. It is not an Apple Developer ID and
# it does not enable distribution or notarization. It exists so a locally built
# copy of Pace has a stable identity on this machine.

set -euo pipefail

identity_name=${1:-Pace Local Signing}
keychain=${PACE_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}

if security find-certificate -c "$identity_name" "$keychain" >/dev/null 2>&1; then
    echo "identity=$identity_name"
    echo "created=false"
    exit 0
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/pace-signing.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

# A code-signing certificate needs the codeSigning extended key usage and the
# digitalSignature key usage. Without both, codesign refuses the identity.
cat >"$work_dir/openssl.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no

[subject]
CN = PACE_IDENTITY_NAME
O = Pace

[extensions]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONFIG
/usr/bin/sed -i '' "s/PACE_IDENTITY_NAME/$identity_name/" "$work_dir/openssl.cnf"

# 20 years, so a local development identity does not expire mid-project.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 7300 \
    -config "$work_dir/openssl.cnf" \
    -keyout "$work_dir/key.pem" \
    -out "$work_dir/cert.pem" >/dev/null 2>&1

# macOS's Security framework cannot read the AES-256 PKCS#12 encryption that
# current OpenSSL defaults to, so the bundle is written with the older
# algorithms it does understand.
/usr/bin/openssl pkcs12 -export \
    -inkey "$work_dir/key.pem" \
    -in "$work_dir/cert.pem" \
    -name "$identity_name" \
    -passout pass:pace \
    -certpbe PBE-SHA1-3DES \
    -keypbe PBE-SHA1-3DES \
    -macalg sha1 \
    -out "$work_dir/identity.p12" >/dev/null 2>&1

# -T codesign lets codesign use the private key without prompting each time.
security import "$work_dir/identity.p12" \
    -k "$keychain" \
    -P pace \
    -T /usr/bin/codesign \
    -A >/dev/null

# Trust the certificate for code signing in the user's own trust domain. The
# admin domain would need sudo, and a local development identity does not need
# to be trusted system-wide.
if ! security add-trusted-cert -r trustRoot \
    -p codeSign \
    -k "$keychain" \
    "$work_dir/cert.pem" >/dev/null 2>&1; then
    echo "note: could not add a trust setting; codesign may warn" >&2
fi

echo "identity=$identity_name"
echo "created=true"
