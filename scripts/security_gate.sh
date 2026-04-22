#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Krypta ECC — Security Gate
# ─────────────────────────────────────────────────────────────────────────────
# Automated security checks that block builds and releases.
# Run before every commit, PR merge, and release build.
#
# Exit codes:
#   0 = all gates pass
#   1 = security gate failed (build MUST NOT proceed)
#
# Usage:
#   ./scripts/security_gate.sh          # full gate (analysis + tests + audit)
#   ./scripts/security_gate.sh --quick  # fast gate (analysis + critical tests only)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

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

QUICK_MODE=false
if [[ "${1:-}" == "--quick" ]]; then
  QUICK_MODE=true
fi

echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Krypta ECC — Security Gate${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# ─── Gate 1: Static Analysis ─────────────────────────────────────────────────

echo -e "${BOLD}Gate 1: Static Analysis${NC}"

if dart analyze lib/ 2>&1 | grep -q "No issues found"; then
  pass "dart analyze lib/ — no issues"
else
  fail "dart analyze lib/ — issues found"
  dart analyze lib/ 2>&1 | head -20
fi

echo ""

# ─── Gate 2: No Hardcoded Secrets ─────────────────────────────────────────────

echo -e "${BOLD}Gate 2: Secret Scanning${NC}"

# Check for hardcoded API keys, tokens, passwords
if grep -rn --include="*.dart" -E "(password|secret|apikey|api_key|token)\s*=\s*['\"][^'\"]{8,}" lib/ 2>/dev/null | \
   grep -v "StorageKeys\." | \
   grep -v "// " | \
   grep -v "key:" | \
   grep -v "krypta_" | \
   grep -v "factory\|fromMap\|toMap\|switch\|case\|enum\|class\|test\|mock\|example\|placeholder" | \
   head -5; then
  warn "Potential hardcoded secrets found — review manually"
else
  pass "No hardcoded secrets detected in lib/"
fi

# Check for print() statements (information leak in production)
if grep -rn --include="*.dart" "^\s*print(" lib/ 2>/dev/null | head -5; then
  fail "print() calls found in lib/ — use debugPrint or remove"
else
  pass "No print() calls in lib/"
fi

# Check for debugPrint that leaks error details with stack traces
if grep -rn --include="*.dart" 'debugPrint.*\$e' lib/ 2>/dev/null | \
   grep -v "// " | head -5; then
  warn "debugPrint with \$e found — may leak error details in debug builds"
else
  pass "No debugPrint with error details in lib/"
fi

echo ""

# ─── Gate 3: Crypto Protocol Enforcement ──────────────────────────────────────

echo -e "${BOLD}Gate 3: Crypto Protocol Enforcement${NC}"

# Verify v1 legacy message creation does not exist in protocol/ratchet code.
# Excludes QR display (which uses 'v': 1 for QR payload versioning, not message protocol).
if grep -rn --include="*.dart" "'v':\s*1" lib/security/ lib/services/ 2>/dev/null | \
   grep -v "test\|mock\|comment\|//" | head -5; then
  fail "v1 message format found in security/services code — all messages must be v2+"
else
  pass "No v1 message creation in security/services code"
fi

# Verify Double Ratchet encrypt uses AAD
if grep -n "\.encrypt(" lib/security/ratchet/double_ratchet.dart 2>/dev/null | \
   grep -v "aad:" | grep -v "//" | head -5 | grep -q .; then
  warn "Double Ratchet encrypt call may not use AAD — verify manually"
else
  pass "Double Ratchet cipher encrypt uses AAD"
fi

# Verify constant-time comparison exists
if grep -rn --include="*.dart" "_constantTimeEquals\|diff |= " lib/ 2>/dev/null | head -1 > /dev/null; then
  pass "Constant-time comparison patterns found"
else
  fail "No constant-time comparison found in lib/"
fi

# Verify SensitiveBuffer is used for key zeroing
if grep -rn --include="*.dart" "SensitiveBuffer.zeroBytes" lib/security/ratchet/double_ratchet.dart 2>/dev/null | head -1 > /dev/null; then
  pass "SensitiveBuffer.zeroBytes used in Double Ratchet"
else
  fail "Missing SensitiveBuffer.zeroBytes in Double Ratchet"
fi

echo ""

# ─── Gate 4: Key Transparency ────────────────────────────────────────────────

echo -e "${BOLD}Gate 4: Key Transparency${NC}"

if [ -f "lib/security/transparency/key_commitment.dart" ] && \
   [ -f "lib/security/transparency/key_transparency_log.dart" ] && \
   [ -f "lib/security/transparency/consistency_checker.dart" ]; then
  pass "Key Transparency modules present"
else
  fail "Key Transparency modules missing"
fi

if grep -rn --include="*.dart" "Ed25519" lib/security/transparency/key_commitment.dart 2>/dev/null | head -1 > /dev/null; then
  pass "Key commitments use Ed25519 signatures"
else
  fail "Key commitments missing Ed25519 signatures"
fi

echo ""

# ─── Gate 5: Device Security ─────────────────────────────────────────────────

echo -e "${BOLD}Gate 5: Device Security${NC}"

if [ -f "lib/security/device/device_integrity_policy.dart" ]; then
  pass "Device integrity policy module present"
else
  fail "Device integrity policy missing"
fi

if [ -f "lib/security/hardware/hardware_security_binding.dart" ]; then
  pass "Hardware security binding module present"
else
  fail "Hardware security binding missing"
fi

if [ -f "lib/security/memory/sensitive_buffer.dart" ]; then
  pass "Sensitive buffer module present"
else
  fail "Sensitive buffer module missing"
fi

echo ""

# ─── Gate 6: Tests ────────────────────────────────────────────────────────────

echo -e "${BOLD}Gate 6: Security Tests${NC}"

if [ "$QUICK_MODE" = true ]; then
  echo "  (Quick mode: running critical tests only)"
  # Run only the most critical security tests
  if flutter test test/security/key_transparency_test.dart \
                  test/security/sensitive_buffer_test.dart \
                  test/security/device_integrity_policy_test.dart \
                  2>&1 | tail -1 | grep -q "All tests passed"; then
    pass "Critical security tests pass"
  else
    fail "Critical security tests failed"
  fi
else
  # Run the full security test suite
  TEST_OUTPUT=$(flutter test test/security/ 2>&1)
  if echo "$TEST_OUTPUT" | tail -1 | grep -q "All tests passed"; then
    TEST_COUNT=$(echo "$TEST_OUTPUT" | tail -1 | sed -n 's/.*+\([0-9]*\).*/\1/p')
    pass "All ${TEST_COUNT:-???} security tests pass"
  else
    fail "Security tests failed"
    echo "$TEST_OUTPUT" | grep -E "\-[0-9]+:" | head -10
  fi

  # Verify minimum test count (should be 239+)
  if [ "${TEST_COUNT:-0}" -ge 200 ]; then
    pass "Test count (${TEST_COUNT:-0}) meets minimum threshold (200)"
  else
    warn "Test count (${TEST_COUNT:-0}) below expected threshold (200)"
  fi
fi

echo ""

# ─── Gate 7: Documentation ──────────────────────────────────────────────────

echo -e "${BOLD}Gate 7: Security Documentation${NC}"

if [ -f "THREAT_MODEL.md" ]; then
  pass "THREAT_MODEL.md present"
else
  fail "THREAT_MODEL.md missing"
fi

if [ -f "SECURITY_ARCHITECTURE.md" ]; then
  pass "SECURITY_ARCHITECTURE.md present"
else
  fail "SECURITY_ARCHITECTURE.md missing"
fi

if [ -f "SECURITY_INVENTORY.md" ]; then
  pass "SECURITY_INVENTORY.md present"
else
  fail "SECURITY_INVENTORY.md missing"
fi

if [ -f "SECURITY_RELEASE_CHECKLIST.md" ]; then
  pass "SECURITY_RELEASE_CHECKLIST.md present"
else
  fail "SECURITY_RELEASE_CHECKLIST.md missing"
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
  echo -e "  ${RED}${BOLD}SECURITY GATE FAILED — BUILD BLOCKED${NC}"
  echo -e "  Fix all ${RED}[FAIL]${NC} items before proceeding."
  echo -e ""
  exit 1
else
  echo -e ""
  echo -e "  ${GREEN}${BOLD}SECURITY GATE PASSED${NC}"
  if [ "$WARN_COUNT" -gt 0 ]; then
    echo -e "  Review ${YELLOW}[WARN]${NC} items before release."
  fi
  echo -e ""
  exit 0
fi
