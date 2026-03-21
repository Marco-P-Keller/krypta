#!/bin/sh
# Run before Flutter xcode_backend.sh (build + embed_and_thin).
# codesign rejects extended attributes: "resource fork, Finder information, or similar detritus not allowed"
export COPYFILE_DISABLE=1

# Project root (parent of ios/)
ROOT="$(cd "${SRCROOT}/.." && pwd)"

# --- Same fix as: xattr -cr .../build/native_assets/ios/ ---
NA_IOS="${ROOT}/build/native_assets/ios"
if [ -d "$NA_IOS" ]; then
  xattr -cr "$NA_IOS" 2>/dev/null || true
fi

# Parent folder (other platforms / metadata)
NA="${ROOT}/build/native_assets"
if [ -d "$NA" ]; then
  xattr -cr "$NA" 2>/dev/null || true
fi

# Pub cache packages that feed native asset builds
PUB_HOSTED="${HOME}/.pub-cache/hosted"
if [ -d "$PUB_HOSTED" ]; then
  find "$PUB_HOSTED" -maxdepth 4 -type d \( \
    -name 'objective_c-*' -o \
    -name 'native_toolchain_c-*' -o \
    -name 'hooks_runner-*' -o \
    -name 'code_assets-*' \
  \) 2>/dev/null | while IFS= read -r _xdir; do
    xattr -cr "$_xdir" 2>/dev/null || true
  done
fi

# Optional: set STRIP_PROJECT_XATTRS=1 in Xcode scheme "Environment Variables" to mimic:
#   xattr -cr /path/to/kryptaapp/
# Use only if needed; then run "cd ios && pod install" if Pods act up.
if [ "${STRIP_PROJECT_XATTRS:-}" = "1" ] && [ -d "$ROOT" ]; then
  echo "flutter_codesign_prep: STRIP_PROJECT_XATTRS=1 — stripping xattrs on project root (may be slow)"
  xattr -cr "$ROOT" 2>/dev/null || true
fi
