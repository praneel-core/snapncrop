#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode), SwiftPM needs to be
# told where Apple's "Testing" framework lives; this wrapper adds those flags.
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [ -d "$F/Testing.framework" ]; then
  swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" \
             -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
else
  swift test "$@"   # full Xcode installed: no extra flags needed
fi
