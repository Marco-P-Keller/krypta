# Krypta Security Audit 2026-05 — Area 2: Protocol

**Status:** Code complete, awaiting Daniel review.
**Test count:** 351/351 (no new PoCs added — fixes covered by existing crypto tests + manual review).
**Codex rounds:** 1 (clean on Area 2 code).

---

## Findings

### H1-Proto — `_encryptWithRatchet` send-side race (HIGH)

**Attack:** Two concurrent `sendMessage()` calls on the same chat both read the ratchet state at the same chain key, both produce a message under the same chain-key advance, both increment `globalSendSeqNo` to the same value. Result: ratchet drops a message (duplicate message keys), recipient rejects the other as `REPLAY_SEQ`.

**Fix:** Per-chat single-flight mutex `_underSendMutex(chatId, body)` wraps `sendMessage` and `_sendControlMessage`. Concurrent calls on the same chat queue, calls on different chats run in parallel.

Files: `lib/features/messenger/logic/messenger_provider.dart` (+39 lines for mutex helper, send/control wrappers).

### H2-Proto — `payloadMap.toString()` strips types (HIGH)

**Attack/Bug:** `_firestore.sendEncryptedMessage(... encryptedPayload: payloadMap.map((k, v) => MapEntry(k, v.toString())))` collapsed `int` fields (`v`, `pv`, `ns`, `pn`) to strings on the wire. Receiver parsed back inconsistently — most code paths handled both, but the type ambiguity was a footgun for any new field added (e.g. the `_seq` int Run 1 added went through the encrypted inner payload, not this path, so no current breakage — but future additions would silently break).

**Fix:** Drop the `.toString()` map-coercion. Widen `sendEncryptedMessage` signature from `Map<String, String>` to `Map<String, dynamic>`. Firestore accepts JSON-compatible types natively.

Files: `lib/features/messenger/logic/messenger_provider.dart`, `lib/services/firebase/firestore_service.dart`.

### M1-Proto (DOCUMENTED RESIDUAL) — `ReplayGuard` MISSING_SEQ passthrough

**Issue:** v3 messages without `_seq` are accepted (intended back-compat for old v3 clients during the security/hardening rollout). A peer running custom-built Krypta could exploit this to bypass replay enforcement on v3 wires — but only against another peer they already share a session with (where they have the shared key and could replay anyway via direct ratchet message replay if AEAD didn't catch it).

**Status:** Acknowledged residual. Once both peers are confirmed on v3+`_seq` build (e.g. via wire signal), `ReplayGuard` should be tightened to reject MISSING_SEQ. Tracked for future audit.

---

## Codex loop (1 round)

R1: 0 P1 on Area 2 code. One P2 on `.github/workflows/security-gate.yml` (recurring SIGPIPE issue) — fixed in this round with a capture-then-test pattern that avoids `pipefail`+pipe interaction entirely.

---

## Stop-criterion

✅ 0 P1 from Codex on Area 2 code, single round.
✅ 351/351 tests pass.
✅ `flutter analyze lib/` clean.
✅ Existing replay-protection / sealed-sender / control-message tests unchanged green.

Awaiting Daniel review.
