#!/bin/sh
# objective_c.framework comes from Flutter native_assets, not Xcode/CocoaPods, so archives
# omit its dSYM and Organizer / symbol upload warns. dsymutil adds a bundle with matching UUID.
set -e
ROOT="$(cd "${SRCROOT}/.." && pwd)"
FW=""
for base in \
  "${CODESIGNING_FOLDER_PATH}" \
  "${TARGET_BUILD_DIR}/${WRAPPER_NAME}" \
  "${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}" \
  "${BUILT_PRODUCTS_DIR}/Runner.app"
do
  [ -z "$base" ] && continue
  candidate="${base}/Frameworks/objective_c.framework/objective_c"
  if [ -f "$candidate" ]; then
    FW="$candidate"
    break
  fi
done
if [ -z "$FW" ]; then
  candidate="${ROOT}/build/native_assets/ios/objective_c.framework/objective_c"
  [ -f "$candidate" ] && FW="$candidate"
fi
if [ -z "$FW" ]; then
  exit 0
fi
if [ -z "${DWARF_DSYM_FOLDER_PATH}" ]; then
  exit 0
fi
mkdir -p "${DWARF_DSYM_FOLDER_PATH}"
OUT="${DWARF_DSYM_FOLDER_PATH}/objective_c.framework.dSYM"
rm -rf "${OUT}"
echo "note: native_assets_dsym: ${FW} -> ${OUT}"
dsymutil "${FW}" -o "${OUT}"
