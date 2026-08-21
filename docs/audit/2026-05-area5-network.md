# Krypta Security Audit 2026-05 — Area 5: Network

**Status:** Code complete, awaiting Daniel review.
**Test count:** 351/351.
**Codex rounds:** 1 (clean).

---

## Findings

### H1-Network — Firestore rules missing for `deliveryTokens` and `keyCommitments` (HIGH)

**Bug:** `firebase/firestore.rules` had no `match` block for either `/deliveryTokens/{userId}` or `/keyCommitments/{userId}/log/{epochId}`. The catch-all `match /{document=**} { allow read, write: if false; }` therefore denied EVERY operation on those collections in production.

**Consequences:**
- **Sealed sender broken:** `getDeliveryToken(...)` always returned null → senders never included a delivery token → routing fell back to direct-UID, defeating the sealed-sender layer.
- **Key Transparency broken:** `publishKeyCommitment(...)` failed silently → no commitments ever landed on the server → `ConsistencyChecker` gossip had nothing to verify against → split-view detection inert.

**Fix:** Added explicit rules:
- `deliveryTokens/{userId}`: read by anyone authenticated (sender needs to fetch recipient's token); write only by owner; field allowlist (`token`, optional `updatedAt`); size bounds.
- `keyCommitments/{userId}/log/{epochId}`: read by anyone authenticated (gossip); create only by owner with required fields (`e`, `k`, `p`, `ts`, `s`, `sp`); no updates (append-only); deletes by owner only (emergency wipe).

Files: `firebase/firestore.rules`.

### H2-Network — Existing rules require `updatedAt == request.time`, code never set it (HIGH)

**Bug:** Pre-existing rules for `publicKeys/{userId}`, `prekeys/{userId}`, and `fcmTokens/{userId}` all check `request.resource.data.updatedAt == request.time`. The Dart calls (`registerPublicKey`, `publishPreKeyBundle`, `registerFcmToken`) never set `updatedAt` → rule evaluates `undefined == time` → false → write denied.

This means the entire identity registration / prekey publication / FCM registration pipeline was rejected by the rules in production. The catch-all silently denying these is the same class of issue as H1-Network — broken rules-vs-code coupling that nothing observable in dev caught.

**Fix:** Added `'updatedAt': FieldValue.serverTimestamp()` to every offending write. Plus my new `publishDeliveryToken` writes the same field for consistency.

Files: `lib/services/firebase/firestore_service.dart`.

### M-Network (DOCUMENTED RESIDUALS)

**M1-Network — `getPublicKey` is TOFU.** A malicious server could substitute the recipient's identity public key on first fetch. Mitigated by out-of-band Safety Number verification (existing flow). Listed because the binding is implicit, not enforced in code.

**M2-Network — `getDeliveryToken` is unauthenticated routing.** Server can swap a recipient's token to redirect messages elsewhere. Confidentiality intact (recipient's identity priv not held by attacker, so message un-decryptable on the wrong device); availability impacted (sender thinks message delivered, recipient never gets it).

**M3-Network — `deleteAllUserData` is a single batch.** Firestore batch limit is 500 ops. Users with > 500 messages would partially fail. Acknowledge.

**L1-Network — Privacy polling jitter window 10–30s.** Old finding M9 from 26.04. recommended ±60s for stronger statistical timing resistance. Tradeoff: bandwidth/latency vs. privacy. Design choice retained.

**L2-Network — Read receipt jitter 1–10s.** Old finding M from 26.04. recommended 2–15s. Same tradeoff.

---

## Native pinning

Out-of-scope for this Dart audit — native pinning is configured in:
- `android/app/src/main/res/xml/network_security_config.xml`
- `ios/Runner/Info.plist` (`NSPinnedDomains`)

The Dart-level no-op pinning was already removed (H2 from 26.04. — `lib/main.dart` line 32-38 documents the removal).

---

## Codex loop (1 round, clean)

R1: *"did not identify any discrete introduced issues that would clearly break existing behavior or security guarantees"*.

---

## Stop-criterion

✅ R1 clean.
✅ 351/351 tests pass.
✅ analyzer clean.

**Two HIGH bugs that were silently breaking production functionality** are now fixed.
