# Krypta Security Audit 2026-05 — Area 6: Client & Business Logic

**Status:** Code complete, awaiting Daniel review.
**Test count:** 351/351.
**Codex rounds:** 0 — **Codex GPT-5.5 quota exhausted mid-Area 6**. See §"Codex limit" below.

---

## Findings

### M1-Client (alt: 26.04. L1) — Message-password TextField missing `obscureText`

**Bug:** `chat_screen.dart:174` — the `TextField` for the per-message password had no `obscureText: true`. Plaintext password visible while typing, defeating the point of password-protecting a single message.

**Fix:** Added `obscureText: true`, plus `enableSuggestions: false` and `autocorrect: false` to prevent OS-level password capture / suggestion.

Files: `lib/features/messenger/presentation/chat_screen.dart`.

### M2-Client (alt: 26.04. M7) — Clipboard auto-clear

**Bug:** Six call sites copy sensitive content (user IDs, safety numbers, message content) to the system clipboard with no time-bound clear. Clipboard-history apps and accessibility services can read these indefinitely.

**Fix:** New `lib/services/platform/clipboard_helper.dart` with `ClipboardHelper.copyEphemeral(text)` — schedules an auto-clear 60s after copy, only clears if the clipboard still contains our value (so we don't wipe what the user has since copied themselves). Replaced all 6 callsites:
- `chat_list_screen.dart` (user ID)
- `new_chat_screen.dart` (user ID)
- `qr_display_sheet.dart` (user ID)
- `message_bubble.dart` (message content)
- `chat_settings_sheet.dart` (safety number)
- `settings_screen.dart` (user ID)

Plus: `EmergencyWipeService` calls `ClipboardHelper.cancelPending()` before its final clipboard wipe so a stale auto-clear timer cannot fire after wipe.

Files: `lib/services/platform/clipboard_helper.dart` (new), 6 caller updates, `lib/services/emergency/emergency_wipe_service.dart`.

### Re-verified pre-existing protections

- **Vault password**: persistent fail counter, exponential lockout, emergency-wipe trigger after 5 attempts (B3 + dedicated screen).
- **Settings re-auth**: single-flight + same fail counter (B3).
- **Biometric fallback**: cascades to vault counter (H4 from 26.04.).
- **Calculator code detector**: Argon2-based (verified).

---

## Codex limit

The Codex GPT-5.5 review for this area was **interrupted by a usage cap**:

```
ERROR: You've hit your usage limit. Upgrade to Pro [...] or try again at 11:10 PM.
```

This audit run consumed approximately 20+ Codex rounds across Areas 1–6, which is enough to exhaust the daily Codex quota. **Areas 1–5 had full Codex adversarial review; Area 6 fixes have NOT been adversarially reviewed.** When the quota resets, a final Codex pass over the full diff is recommended before commit.

The Area 6 fixes are mechanically simple (UI-level: one `obscureText:` flag, one helper class, six call-site replacements) and do not change cryptographic invariants — the residual review-debt is correspondingly small.

---

## Stop-criterion

- ✅ 351/351 tests pass.
- ✅ `flutter analyze lib/` clean.
- ⚠️ Codex review: **deferred** (quota). Run a final `codex review --uncommitted` after the quota resets (~11:10 PM local) before merging.
