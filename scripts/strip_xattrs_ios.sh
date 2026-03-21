#!/bin/sh
# Removes extended attributes that break `codesign` during Archive / flutter build ipa.
# Fixes: "resource fork, Finder information, or similar detritus not allowed" on objective_c.framework
#
# Usage:
#   ./scripts/strip_xattrs_ios.sh
# Whole project (optional, can confuse Pods — then run: cd ios && pod install):
#   STRIP_PROJECT=1 ./scripts/strip_xattrs_ios.sh

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export COPYFILE_DISABLE=1

echo "Stripping xattrs from build/native_assets/ios/ (objective_c.framework)..."
if [ -d "$ROOT/build/native_assets/ios" ]; then
  xattr -cr "$ROOT/build/native_assets/ios" 2>/dev/null || true
fi

echo "Stripping xattrs from build/native_assets/..."
if [ -d "$ROOT/build/native_assets" ]; then
  xattr -cr "$ROOT/build/native_assets" 2>/dev/null || true
fi

echo "Stripping xattrs from pub-cache native packages..."
PUB_HOSTED="${HOME}/.pub-cache/hosted"
if [ -d "$PUB_HOSTED" ]; then
  find "$PUB_HOSTED" -maxdepth 4 -type d \( \
    -name 'objective_c-*' -o -name 'native_toolchain_c-*' -o \
    -name 'hooks_runner-*' -o -name 'code_assets-*' \
  \) 2>/dev/null |
    while IFS= read -r dir; do
      xattr -cr "$dir" 2>/dev/null || true
    done
fi

if [ "${STRIP_PROJECT:-}" = "1" ]; then
  echo "STRIP_PROJECT=1 — stripping entire project tree (slow; if Pods break: cd ios && pod install)..."
  xattr -cr "$ROOT" 2>/dev/null || true
fi

echo "Done. Prefer building outside iCloud Desktop/Documents (e.g. ~/Developer)."
