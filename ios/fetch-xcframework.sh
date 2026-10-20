#!/usr/bin/env bash
#
# fetch-xcframework.sh — vendor MubeenDeviceSDK.xcframework into ios/Frameworks/.
#
# In-repo path: ios/fetch-xcframework.sh
#
# This is a MAINTAINER script, run at SDK-bump time. The result is COMMITTED (2.1 MB),
# so clients never run this and `pod install` never hits the network for the binary.
# The SPM path does not use it at all — SwiftPM downloads and verifies the same zip
# itself from ios/mubeen_flutter/Package.swift.
#
#   ./fetch-xcframework.sh [version]     # default: the VERSION below
#
# After running: bump `url:` + `checksum:` in ios/mubeen_flutter/Package.swift and
# `s.version` in ios/mubeen_flutter.podspec, then commit ios/Frameworks/ with them.

set -euo pipefail

VERSION="${1:-2.0.0}"
URL="https://github.com/mubeen-ai/Mubeen-IOS-SDK-public/releases/download/${VERSION}/MubeenDeviceSDK.xcframework.zip"

# Same constant as `checksum:` in ios/mubeen_flutter/Package.swift. SwiftPM's binaryTarget
# checksum is the SHA-256 of the zip itself, so one value serves both resolvers.
# On a version bump, get the new one from `swift package compute-checksum <zip>` (or
# `shasum -a 256`) and update BOTH places.
EXPECTED_SHA256="5d50d72934d9759f025cbfe7e8282ad28a3d15547be5e7bbb9ba65db065147f1"

cd "$(dirname "$0")"          # ios/
DEST="Frameworks"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> Downloading MubeenDeviceSDK ${VERSION}"
echo "    ${URL}"
if ! curl -fSL --retry 3 --retry-delay 2 -o "$tmp/sdk.zip" "$URL"; then
    echo "ERROR: download failed. Check the release tag '${VERSION}' exists and is public." >&2
    exit 1
fi

if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$tmp/sdk.zip" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp/sdk.zip" | awk '{print $1}')"
else
    echo "ERROR: neither shasum nor sha256sum is available; refusing to vendor an unverified binary." >&2
    exit 1
fi

if [ "$actual" != "$EXPECTED_SHA256" ]; then
    cat >&2 <<EOF
================================================================================
CHECKSUM MISMATCH — REFUSING TO VENDOR THIS BINARY
  url      : ${URL}
  expected : ${EXPECTED_SHA256}
  actual   : ${actual}

Either the release asset was re-uploaded (GitHub allows replacing an asset on an
existing tag) or the download was tampered with. Do NOT "just update the constant":
confirm with the SDK owner which build is authoritative first.
================================================================================
EOF
    exit 1
fi
echo "==> Checksum OK (${actual})"

mkdir -p "$tmp/unpacked"
unzip -q "$tmp/sdk.zip" -d "$tmp/unpacked"

# The release zip may contain the .xcframework at the root or nested one level.
src="$(find "$tmp/unpacked" -maxdepth 3 -type d -name 'MubeenDeviceSDK.xcframework' -print -quit)"
if [ -z "$src" ]; then
    echo "ERROR: no MubeenDeviceSDK.xcframework found inside the archive. Contents:" >&2
    find "$tmp/unpacked" -maxdepth 2 >&2
    exit 1
fi

# Sanity-check it is a real xcframework before replacing the committed copy.
if [ ! -f "$src/Info.plist" ]; then
    echo "ERROR: ${src} has no Info.plist — not a valid xcframework." >&2
    exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/MubeenDeviceSDK.xcframework"
mv "$src" "$DEST/"

echo "==> Vendored to $(pwd)/$DEST/MubeenDeviceSDK.xcframework"
echo "    Slices:"
find "$DEST/MubeenDeviceSDK.xcframework" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sed 's/^/      /'
echo
echo "Next: bump url/checksum in mubeen_flutter/Package.swift and s.version in"
echo "mubeen_flutter.podspec, then commit ios/Frameworks/ together with them."
