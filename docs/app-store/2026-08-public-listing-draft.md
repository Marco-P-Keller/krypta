# App Store Connect — public product page draft

Companion to `2026-08-app-review-notes-draft.md`. Guideline 2.3.1 has two
addressees: "your app's functionality should be clear to end users **and**
App Review." The Notes draft covers App Review; this covers end users. Both
currently-live comparison apps checked during the audit ("Calculator Lock -
Secure Vault", "Calculator+ Private Vault") name the hidden function directly
in their public Name/Subtitle/Description, not only in review notes — this
draft follows that pattern.

This is a starting point for Marco to edit in App Store Connect, not a final
copy. Nothing here is pasted anywhere automatically.

---

**Name:** Krypta — Private Messenger

**Subtitle** (30 char max — pick one):
- "Encrypted chat, disguised"
- "Private E2EE messenger"

**Promotional text** (170 char max, editable without a new build):
> A real calculator on the outside. A Signal-protocol encrypted messenger
> inside, unlocked with your own passcode. Nothing is readable without it —
> not even by us.

**Description:**

> Krypta looks like an ordinary calculator — because it is one. It does
> real math, works like any calculator app, and shows nothing unusual on
> your Home Screen or in the App Switcher.
>
> Enter your own passcode on the calculator and it opens into Krypta's real
> purpose: a private messenger built on the same end-to-end encryption
> design as Signal (X3DH key agreement + Double Ratchet, XChaCha20-Poly1305).
> Every message is encrypted on your device and can only be read on the
> recipient's device — not on our servers, not by us.
>
> WHY A CALCULATOR
> If someone else picks up your unlocked phone, there's nothing to see —
> just a calculator. This is the same idea used by other well-known secure
> vault and private-notes apps, applied to messaging instead of file
> storage.
>
> WHAT'S INSIDE
> • End-to-end encrypted messaging (Signal-protocol design)
> • Your own passcode — set during setup, never sent anywhere
> • An emergency code that instantly and irreversibly wipes the app
> • Face ID / Touch ID support
> • No phone number or email required to use the app
>
> Krypta is built for people who want ordinary phone privacy — journalists,
> activists, or anyone who'd rather their messages stayed theirs.

**Keywords** (100 char max, comma-separated, no spaces after commas):
`encrypted,messenger,privacy,secure chat,e2ee,calculator,vault,signal protocol,private`

**Age rating:** 17+ typical for unrestricted user-generated content /
user-to-user communication apps — set via the standard App Store Connect
age-rating questionnaire, not a free-text field.

**Screenshots:** should show both halves honestly — the calculator screen,
and (labeled, e.g. "Unlocks into a private messenger") the chat UI. Do not
screenshot only the calculator; that alone would look like a functionality
mismatch against the description above.

---

## Notes for whoever finalizes this

- Every factual claim above should be re-checked against whatever ships:
  "no phone number or email required" is only true because auth is
  Firebase `signInAnonymously()` — if that ever changes, update this text
  first.
- Marketing language deliberately avoids "hide from someone" framing (see
  `docs/audit/2026-08-ios-apple-conformance.md` §category-press-legal risk)
  in favor of adult privacy/security positioning.
- Character limits above are current App Store Connect limits as of this
  writing — re-check them in App Store Connect itself before finalizing,
  they're not something this repo can verify.
