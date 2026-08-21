#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Krypta ECC — Pre-Release Security Verification
# ─────────────────────────────────────────────────────────────────────────────
# Comprehensive check before any release build. Runs ALL security gates plus
# additional release-specific checks (build verification, APK analysis).
#
# Must pass with 0 failures before:
#   - Publishing to App Store / Play Store
#   - Creating a release tag
#   - Distributing to beta testers
#
# Usage:
#   ./scripts/pre_release_check.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() {
  echo -e "  ${GREEN}[PASS]${NC} $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo -e "  ${RED}[FAIL]${NC} $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
  echo -e "  ${YELLOW}[WARN]${NC} $1"
  WARN_COUNT=$((WARN_COUNT + 1))
}

echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Krypta ECC — Pre-Release Security Verification${NC}"
echo -e "${BOLD}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# ─── Phase 1: Run Security Gate ───────────────────────────────────────────────

echo -e "${BOLD}Phase 1: Security Gate${NC}"
echo ""

if bash scripts/security_gate.sh 2>&1; then
  pass "Security gate passed"
else
  fail "Security gate failed — fix issues before release"
  echo ""
  echo -e "  ${RED}Pre-release check ABORTED — security gate must pass first.${NC}"
  exit 1
fi

echo ""

# ─── Phase 2: Version & Branch Check ─────────────────────────────────────────

echo -e "${BOLD}Phase 2: Version & Branch${NC}"

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo "  Current branch: $BRANCH"

if [[ "$BRANCH" == "main" || "$BRANCH" == release/* ]]; then
  pass "On release-eligible branch ($BRANCH)"
else
  warn "Not on main or release/* branch ($BRANCH)"
fi

# Check for uncommitted changes
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
  pass "No uncommitted changes"
else
  fail "Uncommitted changes detected — commit before release"
fi

# Check for untracked files in lib/
UNTRACKED=$(git ls-files --others --exclude-standard lib/ 2>/dev/null | head -5)
if [ -z "$UNTRACKED" ]; then
  pass "No untracked files in lib/"
else
  warn "Untracked files in lib/: $UNTRACKED"
fi

echo ""

# ─── Phase 3: Dependency Audit ────────────────────────────────────────────────

echo -e "${BOLD}Phase 3: Dependency Audit${NC}"

# Check for outdated dependencies
if flutter pub outdated 2>&1 | grep -q "All dependencies are up to date"; then
  pass "All dependencies up to date"
else
  warn "Some dependencies may be outdated — run 'flutter pub outdated'"
fi

# Check pubspec.lock exists and is committed
if [ -f "pubspec.lock" ]; then
  if git ls-files --error-unmatch pubspec.lock > /dev/null 2>&1; then
    pass "pubspec.lock is tracked in git"
  else
    fail "pubspec.lock is not tracked in git — commit it"
  fi
else
  fail "pubspec.lock missing"
fi

echo ""

# ─── Phase 4: Build Verification ─────────────────────────────────────────────

echo -e "${BOLD}Phase 4: Build Verification${NC}"

# Verify release build succeeds
echo "  Building release APK..."
if flutter build apk --release 2>&1 | tail -5 | grep -q "Built build/"; then
  pass "Release APK build successful"

  # Check APK size (warn if unusually large)
  APK_SIZE=$(stat -f%z build/app/outputs/flutter-apk/app-release.apk 2>/dev/null || \
             stat -c%s build/app/outputs/flutter-apk/app-release.apk 2>/dev/null || echo "0")
  APK_MB=$((APK_SIZE / 1048576))

  if [ "$APK_MB" -lt 200 ]; then
    pass "APK size: ${APK_MB}MB (under 200MB limit)"
  else
    warn "APK size: ${APK_MB}MB — unusually large, investigate"
  fi
else
  fail "Release APK build failed"
fi

echo ""

# ─── Phase 5: ProGuard / R8 Check ────────────────────────────────────────────

echo -e "${BOLD}Phase 5: Code Shrinking${NC}"

if grep -q "minifyEnabled true\|isMinifyEnabled = true" android/app/build.gradle 2>/dev/null || \
   grep -q "minifyEnabled true\|isMinifyEnabled = true" android/app/build.gradle.kts 2>/dev/null; then
  pass "Code minification (ProGuard/R8) enabled for release"
else
  warn "Code minification not detected — verify build.gradle release config"
fi

echo ""

# ─── Phase 6: Platform Security Config ───────────────────────────────────────

echo -e "${BOLD}Phase 6: Platform Security${NC}"

# Android: check for debuggable flag
if grep -q "android:debuggable=\"true\"" android/app/src/main/AndroidManifest.xml 2>/dev/null; then
  fail "android:debuggable=true in AndroidManifest — MUST be removed for release"
else
  pass "AndroidManifest does not have debuggable=true"
fi

# Android: check for network security config or cleartext
if grep -q "usesCleartextTraffic=\"true\"" android/app/src/main/AndroidManifest.xml 2>/dev/null; then
  fail "usesCleartextTraffic=true in AndroidManifest — MUST be false for release"
else
  pass "Cleartext traffic not allowed"
fi

# iOS: check for ATS exceptions (allow arbitrary loads)
if grep -q "NSAllowsArbitraryLoads" ios/Runner/Info.plist 2>/dev/null; then
  if grep -A1 "NSAllowsArbitraryLoads" ios/Runner/Info.plist 2>/dev/null | grep -q "true"; then
    warn "NSAllowsArbitraryLoads=true in Info.plist — verify this is needed"
  fi
fi

echo ""

# ─── Summary ──────────────────────────────────────────────────────────────────

echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed:${NC}  $PASS_COUNT"
echo -e "  ${RED}Failed:${NC}  $FAIL_COUNT"
echo -e "  ${YELLOW}Warned:${NC} $WARN_COUNT"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo -e ""
  echo -e "  ${RED}${BOLD}PRE-RELEASE CHECK FAILED${NC}"
  echo -e "  Fix all ${RED}[FAIL]${NC} items before releasing."
  echo -e "  Review all ${YELLOW}[WARN]${NC} items."
  echo -e ""
  echo -e "  Refer to SECURITY_RELEASE_CHECKLIST.md for the full manual checklist."
  echo -e ""
  exit 1
else
  echo -e ""
  echo -e "  ${GREEN}${BOLD}PRE-RELEASE CHECK PASSED${NC}"
  if [ "$WARN_COUNT" -gt 0 ]; then
    echo -e "  Review ${YELLOW}[WARN]${NC} items before final release."
  fi
  echo -e ""
  echo -e "  Next steps:"
  echo -e "  1. Complete the manual SECURITY_RELEASE_CHECKLIST.md"
  echo -e "  2. Tag the release: git tag -a v<version> -m 'Release <version>'"
  echo -e "  3. Push: git push origin v<version>"
  echo -e ""
  exit 0
fi
