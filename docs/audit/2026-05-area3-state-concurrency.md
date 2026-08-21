# Krypta Security Audit 2026-05 — Area 3: State & Concurrency

**Status:** Code complete, awaiting Daniel review.
**Test count:** 351/351.
**Codex rounds:** 1 (clean — *"did not identify any discrete introduced issue"*).

---

## Findings

### H1-State — Receive race in `_decryptWithRatchet` (HIGH)

**Attack:** Two concurrent receive paths (realtime listener `_handleInbox` + polled fetch `_processPolledMessage`) both call `_decryptWithRatchet(chatId, ...)`. Both read the ratchet state at the same chain key, both decrypt, both write divergent post-states. The chain is corrupted; later messages fail to decrypt under whichever divergent state survived the race.

**Fix:** Generalized the H1-Proto send mutex to a per-chat **ratchet mutex** covering ALL ratchet-mutating code paths (sends, controls, decrypts, session re-init). Concurrent operations on the same chat queue; operations on different chats run in parallel.

**Symbol rename:** `_sendChainPerChat` → `_ratchetMutexPerChat`. `_underSendMutex` is preserved as a thin alias for clarity at send call sites; `_underRatchetMutex` is the canonical name.

Files: `lib/features/messenger/logic/messenger_provider.dart`.

### Pre-existing race protections re-verified

The 26.04. audit already addressed many concurrency issues. Re-verified intact:

- **A3** — `_deletingChats` set blocks send/receive during deleteChat.
- **B2** — Inbox listener exponential-backoff reconnect on onError + onDone.
- **B3** — Settings re-auth single-flight + persistent fail counter.
- **B4** — `_decryptWithRatchet` partial-init scrub (memory + disk).
- **B5** — `_generation` fence in `EncryptedLocalStore` invalidates in-flight saves on `wipeAll`.

---

## Codex loop (1 round, fully clean)

R1 verbatim: *"I did not identify any discrete introduced issue in the staged or untracked changes that would clearly break existing behavior or block the patch."*

---

## Stop-criterion

✅ 0 P1/P2/P3 from Codex on Area 3 code, single round.
✅ 351/351 tests pass.
✅ `flutter analyze lib/` clean.
