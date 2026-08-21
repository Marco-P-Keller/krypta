# Krypta Security Audit 2026-05 — Area 4: Storage & Key Management

**Status:** Code complete, awaiting Daniel review.
**Test count:** 351/351.
**Codex rounds:** 2 (R2 clean).

---

## Findings

### H1-Storage — Catastrophic data loss in `pruneOrphanChatFiles` (HIGH)

**Attack/Bug:** On boot, `pruneOrphanChatFiles(_chats.map((c) => c.id).toSet())` deletes every `msg_*` and `ratchet_*` file whose chat id is not in the set. `loadChats()` returns `[]` BOTH when the user genuinely has no chats AND when `chats.enc` decryption fails transiently (rotation crash window, hardware unwrap glitch, etc.). In the failure case, the boot path was wiping ALL ratchet sessions on disk → all sessions lost, all chats unrecoverable.

**Fix:**
1. `pruneOrphanChatFiles` requires explicit `chatsListIsTrustworthy` flag; defaults to no-op when false.
2. `EncryptedLocalStore.hasPersistedChatsBlob()` checks the **filesystem** for `chats.enc` (NOT the cache — Codex R1 P1 caught that the cache check is empty in exactly the failure mode we needed to detect).
3. Boot path computes trustworthy ⇔ `(chats.enc does not exist on disk) || (loaded ≥1 chat)`.

The risky case — `chats.enc present on disk + decrypt failed + empty in-memory list` — is now correctly classified as untrustworthy → no prune fires.

Files: `lib/services/storage/encrypted_local_store.dart`, `lib/features/messenger/logic/messenger_provider.dart`.

### Side-fix — Security gate v1-grep was too broad

Codex R1 P1: the v1-format guard in `.github/workflows/security-gate.yml` matched `'v': 1` everywhere in `lib/`, including `qr_display_sheet.dart`'s legitimate QR payload version. CI would fail every push. Restricted scope to `lib/features/messenger` + `lib/security` and added negative filters for legitimate v1 *deserializers* (`fromMap`, `legacy`, `v1\b`, version-comparator literals).

---

## Re-verified (no action)

- **B5** — `_generation` fence in `wipeAll` invalidates in-flight saves.
- **H5 from 26.04.** — `rotateStorageKey` two-phase marker + recovery — still in place, plus my Run 1 H2-Crypto AAD-binding now also flows through rotation.
- Hardware-key wrapping migration on init (M4 from 26.04.) — silent fallback to software is intentional.

---

## Codex loop (2 rounds)

| R | Findings | Resolution |
|---|----------|------------|
| 1 | P1: yaml v1-grep matches QR / P1: cache-based blob check fails in target scenario | Both fixed |
| 2 | (clean) | "did not identify any discrete, introduced issues" |

---

## Stop-criterion

✅ R2 clean.
✅ 351/351 tests pass.
✅ analyzer clean.
