#!/bin/bash
# Builds a zip you can attach to a GitHub Release so others don't have to build from source.
#   ./scripts/make_release.sh
# Output: build/Snapncrop-<version>-<arch>.zip  (plus its SHA-256 checksum)
#
# The app is signed ad-hoc (not with your personal certificate) and is NOT notarized, so macOS Gatekeeper
# will warn people on first launch. See "Download" in the README for the steps they need.
# Built for this Mac's architecture only (arm64 on Apple Silicon); a universal build needs full Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
ARCH="$(uname -m)"
ZIP="build/Snapncrop-${VERSION}-${ARCH}.zip"

SNAPNCROP_SIGN_IDENTITY="-" ./build.sh

rm -f "$ZIP"
ditto -c -k --keepParent build/Snapncrop.app "$ZIP"      # ditto keeps the bundle intact (plain zip can break signatures)

echo
echo "Created $ZIP"
shasum -a 256 "$ZIP"
echo "Next: attach it to a release at https://github.com/praneel-core/snapncrop/releases/new"
