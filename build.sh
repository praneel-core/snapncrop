#!/bin/bash
# Builds build/Snapncrop.app from the Swift package and signs it.
#   ./build.sh          build + sign
#   ./build.sh run      build + sign + launch (replaces a running copy)
#   ./build.sh install  build + sign + copy to ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Snapncrop.app"
IDENTITY="${SNAPNCROP_SIGN_IDENTITY:-Snapncrop Local Dev}"
BUNDLE_ID="com.praneelcore.snapncrop"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Snapncrop"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Snapncrop"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Signing: macOS ties the Screen Recording permission to the app's signature. A stable identity
# keeps the permission across rebuilds; ad-hoc signing (`-`) changes every build and resets it.
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
  echo "Signed with '$IDENTITY' (permission will survive rebuilds)."
else
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
  echo "WARNING: signing identity '$IDENTITY' not found; used AD-HOC signing."
  echo "         Screen Recording permission will reset after every rebuild."
  echo "         Fix once with: ./scripts/create_signing_cert.sh"
fi
codesign --verify --verbose=1 "$APP" 2>&1 | head -2
echo "Built $APP"

case "${1:-}" in
  run)
    pkill -x Snapncrop 2>/dev/null || true; sleep 0.3
    open "$APP" ;;
  install)
    pkill -x Snapncrop 2>/dev/null || true
    mkdir -p ~/Applications && rm -rf ~/Applications/Snapncrop.app
    cp -R "$APP" ~/Applications/ && echo "Installed to ~/Applications/Snapncrop.app" ;;
esac
