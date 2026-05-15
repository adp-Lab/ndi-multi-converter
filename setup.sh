#!/bin/bash
# ndi-multi-converter — setup.sh
# Creates 3 additional signed NDI Scan Converter instances (copies 2, 3, 4)
# each broadcasting a distinct NDI source name.
# https://github.com/adp-Lab/ndi-multi-converter

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ORIGINAL="/Applications/NDI Scan Converter.app"
CERT_NAME="NDI Local Signing"
ENTITLEMENTS="$(cd "$(dirname "$0")" && pwd)/entitlements-ndi.plist"

echo ""
echo -e "${BOLD}ndi-multi-converter setup${NC}"
echo "─────────────────────────────────────────"
echo ""

# ── Prerequisites ──────────────────────────────────────────────────────────────

check_prerequisites() {
    # NDI Scan Converter installed?
    if [ ! -d "$ORIGINAL" ]; then
        echo -e "${RED}Error: NDI Scan Converter not found at:${NC}"
        echo "  $ORIGINAL"
        echo ""
        echo "Download and install NDI Tools from: https://ndi.video/tools/"
        exit 1
    fi

    # Entitlements file present?
    if [ ! -f "$ENTITLEMENTS" ]; then
        echo -e "${RED}Error: entitlements-ndi.plist not found next to setup.sh${NC}"
        exit 1
    fi

    # Find OpenSSL 3 (Homebrew — LibreSSL that ships with macOS is not compatible)
    if [ -x "/opt/homebrew/bin/openssl" ]; then
        OPENSSL="/opt/homebrew/bin/openssl"
    elif [ -x "/usr/local/bin/openssl" ]; then
        OPENSSL="/usr/local/bin/openssl"
    else
        echo -e "${RED}Error: OpenSSL 3 not found.${NC}"
        echo "macOS ships LibreSSL which is not compatible. Install OpenSSL via Homebrew:"
        echo ""
        echo "  brew install openssl"
        echo ""
        echo "If you don't have Homebrew: https://brew.sh"
        exit 1
    fi

    # Confirm it's real OpenSSL (not LibreSSL)
    if ! "$OPENSSL" version 2>/dev/null | grep -q "^OpenSSL"; then
        echo -e "${RED}Error: $OPENSSL is not OpenSSL (got $("$OPENSSL" version)).${NC}"
        echo "Install OpenSSL via: brew install openssl"
        exit 1
    fi

    echo -e "NDI Scan Converter: ${GREEN}found${NC}"
    echo -e "OpenSSL:            ${GREEN}$("$OPENSSL" version | cut -d' ' -f1-2)${NC}"
    echo ""
}

# ── Signing certificate ─────────────────────────────────────────────────────────

create_cert() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
        echo -e "Certificate '${CERT_NAME}': ${GREEN}already exists${NC}"
        return
    fi

    echo "Creating self-signed code signing certificate..."

    "$OPENSSL" req -x509 -newkey rsa:2048 \
        -keyout /tmp/ndi-key.pem \
        -out /tmp/ndi-cert.pem \
        -days 3650 -nodes \
        -subj "/CN=$CERT_NAME" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=codeSigning" 2>/dev/null

    "$OPENSSL" pkcs12 -export \
        -out /tmp/ndi-signing.p12 \
        -inkey /tmp/ndi-key.pem \
        -in /tmp/ndi-cert.pem \
        -passout pass:"ndi" -legacy 2>/dev/null

    security import /tmp/ndi-signing.p12 \
        -k ~/Library/Keychains/login.keychain-db \
        -P "ndi" -T /usr/bin/codesign

    security add-trusted-cert -d -r trustRoot -p codeSign \
        -k ~/Library/Keychains/login.keychain-db \
        /tmp/ndi-cert.pem

    rm -f /tmp/ndi-key.pem /tmp/ndi-cert.pem /tmp/ndi-signing.p12

    if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
        echo -e "Certificate '${CERT_NAME}': ${GREEN}created${NC}"
    else
        echo -e "${RED}Certificate creation failed.${NC}"
        echo "Try the manual steps in the README (Keychain Access GUI method)."
        exit 1
    fi
}

# ── Framework fix ───────────────────────────────────────────────────────────────
# The original NDI Scan Converter has a non-standard framework layout (flat files
# instead of symlinks). codesign --deep requires proper symlinks to sign cleanly.

fix_framework_symlinks() {
    local fw="$1/Contents/Frameworks/NDICommon.framework"

    rm -f  "${fw}/NDICommon"
    rm -rf "${fw}/Resources"
    rm -rf "${fw}/Versions/Current"

    ln -s "A"                        "${fw}/Versions/Current"
    ln -s "Versions/Current/NDICommon"  "${fw}/NDICommon"
    ln -s "Versions/Current/Resources"  "${fw}/Resources"
}

# ── Create one copy ─────────────────────────────────────────────────────────────

create_copy() {
    local num=$1
    local dest="/Applications/NDI Scan Convert ${num}.app"
    local bundle_id="com.newtek.NDIScanConverter${num}"
    local ndi_name="Scan Convert ${num}"

    echo ""
    echo -e "${BOLD}Copy $num${NC}: $dest"

    [ -d "$dest" ] && rm -rf "$dest"
    cp -R "$ORIGINAL" "$dest"

    # Binary edit: replace NDI source name at both positions in the universal binary.
    # "Scan Converter" is 14 bytes; replacement must be exactly 14 bytes.
    python3 - <<PYEOF
import sys

binary  = "$dest/Contents/MacOS/NDI Scan Converter"
target  = b'Scan Converter'          # 14 bytes
replace = b'${ndi_name}'             # 14 bytes
positions = [36434, 130642]

data = bytearray(open(binary, 'rb').read())
for pos in positions:
    found = bytes(data[pos:pos+14])
    if found != target:
        print(f"ERROR at position {pos}: expected {target!r}, got {found!r}")
        sys.exit(1)
    data[pos:pos+14] = replace

open(binary, 'wb').write(data)
print(f"  Binary edit: Scan Converter → ${ndi_name}")
PYEOF

    # Update bundle identifier
    /usr/bin/sed -i '' \
        "s/com.newtek.Application-Mac-NDI-ScanConverter/$bundle_id/g" \
        "$dest/Contents/Info.plist"
    echo "  Bundle ID:   $bundle_id"

    # Fix framework layout for clean codesign
    fix_framework_symlinks "$dest"

    # Sign
    codesign --force --deep \
        --sign "$CERT_NAME" \
        --identifier "$bundle_id" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        "$dest" 2>/dev/null

    # Verify
    if codesign --verify --strict "$dest" 2>/dev/null; then
        echo -e "  Signature:   ${GREEN}valid ✓${NC}"
    else
        echo -e "  Signature:   ${YELLOW}applied (strict verify warning — functional)${NC}"
    fi

    # Reset any stale TCC entry so first launch prompts cleanly
    tccutil reset ScreenCapture "$bundle_id" 2>/dev/null || true
    echo "  TCC:         reset (will prompt once on first launch)"
}

# ── Main ────────────────────────────────────────────────────────────────────────

check_prerequisites
create_cert

for num in 2 3 4; do
    create_copy $num
done

echo ""
echo "─────────────────────────────────────────"
echo -e "${GREEN}${BOLD}Done. 4 NDI Scan Converter instances ready.${NC}"
echo ""
echo "NDI source names (on the network):"
echo "  HOSTNAME (Scan Converter)    ← original, already has permission"
echo "  HOSTNAME (Scan Convert 2)"
echo "  HOSTNAME (Scan Convert 3)"
echo "  HOSTNAME (Scan Convert 4)"
echo ""
echo -e "${BOLD}Required: grant Screen Recording once per new app${NC}"
echo "  1. Open each app from /Applications"
echo "  2. Grant permission when macOS asks"
echo "  3. Permission persists — you will not be asked again"
echo ""
