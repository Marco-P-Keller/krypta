# App Store Connect — "App Review Information → Notes" draft

Produced 2026-08-21 by the iOS/Apple conformance audit
(`docs/audit/2026-08-ios-apple-conformance.md`), verified against Apple's live
App Store Review Guidelines (fetched directly, not from memory) and against
two currently-live, publicly-accepted calculator-vault apps on the US App
Store, so this reflects what Apple currently enforces, not received wisdom.

**Why this exists at all:** Guideline 2.3.1 requires hidden/undocumented
functionality to be "described with specificity in the Notes for Review
section of App Store Connect... and accessible for review" — generic
descriptions are explicitly rejected. Krypta's calculator disguise is exactly
the kind of thing that clause is about. The compliant path is not hiding it
better; it's disclosing it here, plainly, so App Review can find and test the
real app. Multiple calculator-disguised vault apps are live on the App Store
today doing exactly this (e.g. "Calculator Lock - Secure Vault",
"Calculator+ Private Vault") — this is an accepted, currently-live category
when disclosed, not a loophole.

Everything between the `=====` lines is meant to be pasted into Apple's
"Notes" field once the bracketed placeholders are filled in. Nothing outside
those lines should go to Apple. No real passcode value appears anywhere below
— every code is a `[BRACKETED PLACEHOLDER]` for Marco to fill in against the
actual review build/device.

---

=====START OF TEXT FOR APP STORE CONNECT=====

KRYPTA — Notes for App Review

In-app product name (shown after unlock, in Settings/About): "Krypta ECC".
On-device cover identity shown on the Home Screen, in the App Switcher, and in
Settings.app: "Calc" / "Rechner" (German).

This is a privacy- and security-focused end-to-end encrypted messenger
(Signal-protocol-style E2EE), in the same general category as apps like
Signal or Threema. To protect a user if someone else picks up their unlocked
phone, the app opens on a fully working calculator and uses a passcode-style
access pattern — the same pattern used by several apps already published and
currently live on the App Store under "secure vault / private notes /
calculator lock" (for example: "Calculator Lock - Secure Vault", "Calculator+
Private Vault"). We are disclosing this openly here, per Guideline 2.3.1,
instead of trying to hide it from App Review. The disguise is aimed only at a
casual glance from another person who might pick up the phone — never at
Apple or at this review process.

HOW TO REACH THE MESSENGER
1. Launch the app. It opens on an ordinary-looking calculator.
2. Type this exact code, then press "=": [ENTER THE CODE YOU CONFIGURED FOR
   THIS REVIEW BUILD, e.g. 1234=]
3. The screen replaces itself with the real encrypted messenger (chat list,
   Settings, etc.). Inside, it identifies itself as "Krypta ECC" in
   Settings/About — that is expected and correct, not a mismatch.
[MARCO: if Face ID/Touch ID or a second "vault password" screen appears
between steps 2 and 3, add one sentence here describing exactly what the
reviewer should do, matching how this specific review build/device is
configured — e.g. "Face ID is disabled on this review device" or "when
prompted, use device passcode fallback."]

PLEASE DO NOT ENTER ANY OTHER CODE
A second, different numeric code on this same calculator screen permanently
and irreversibly deletes all local data and the account (an emergency "duress
wipe" — a safety feature found in other privacy-focused apps too). There is
no confirmation dialog, and it cannot be undone.
The ONLY code that is safe to enter is the exact one given in step 2 above.
Please do not try other numbers "to see what happens."
If this is triggered by accident, the app will not crash — it will show a
"Secret Code" / "Delete Code" setup screen, because the app has just erased
itself back to a first-run state, including the code you were given. If you
see that screen, please stop testing and contact us at [SUPPORT CONTACT
EMAIL — MARCO TO FILL IN] and we will issue a fresh review build and code
right away.

[OPTIONAL — DELETE THIS PARAGRAPH UNLESS THE DECOY-CODE FEATURE HAS BEEN
RESTORED AND VERIFIED WORKING ON THIS EXACT REVIEW BUILD. As of this audit it
is NOT: the code-checking logic can detect a decoy code, but no onboarding
step ever lets a user set one (`saveDecoyCode()` is never called), and even if
one were set, the calculator screen explicitly discards a decoy match and
falls through to ordinary arithmetic — there is currently no screen a decoy
code leads to. Describing it to Apple before it demonstrably works on a real
build would misrepresent the app. If restored and verified, use: "A third,
different code opens a harmless demo/decoy screen preloaded with sample data
— it is not the real messenger described above, and is safe to explore if
you'd like to see it: [DECOY CODE IF APPLICABLE, e.g. 9999=]."]

[OPTIONAL: The chat list will start empty — a second identity (via QR code or
a manually entered contact ID) is needed to create a conversation, so a single
reviewer working alone may not be able to send a message end-to-end. Let us
know if a short screen-recording of a live conversation between two devices
would help.]

WHY IT WORKS THIS WAY
This calculator-cover-plus-passcode pattern is an established, currently-
accepted App Store category (vault / secure-notes / calculator-lock apps),
not a way of hiding functionality from Apple. The disguise never operates
against App Review — only against a casual bystander with physical access to
an unlocked phone. Happy to answer any questions.

=====END OF TEXT FOR APP STORE CONNECT — EVERYTHING BELOW IS INTERNAL, DO NOT PASTE=====

## Internal checklist before submitting (not for Apple)

- [ ] Restore or drop the decoy paragraph. Currently the decoy code is
  two-thirds dead code: `setup_screen.dart` never calls `saveDecoyCode()`
  (onboarding only has a Secret Code and a Delete Code step),
  `calculator_screen.dart` explicitly discards `CodeResult.decoy` ("Decoy
  mode removed — treat as no match"), and `app.dart`'s `_AppScreen` enum has
  no decoy state and never imports `decoy_messenger_screen.dart`. The decoy
  chat UI and its l10n strings exist on disk but nothing routes to them. This
  is a product decision (restore the feature, or formally drop it), not an
  App Store compliance fix — flagging it here rather than making that call.
- [ ] Fill in the Face ID / vault-password bracket in step 3 to match the
  actual review device/build.
- [ ] Fill in a real support contact for the "if triggered by accident" line.
- [ ] Draft the **public** App Store product page (Name/Subtitle/Description)
  to also plainly describe Krypta as a privacy/security messenger — this
  repo has no fastlane/metadata directory and no draft of that text anywhere.
  2.3.1's "clear to end users" half depends on the public listing, not just
  these Notes; both currently-live comparison apps name the vault/hidden
  function directly in their public description, not only in review notes.
- [ ] Recheck total character count against App Store Connect's Notes field
  limit after filling in all brackets and deciding on the optional
  paragraphs.
- [ ] Awareness, not a blocker: Apple has, at least once (2018, "Private
  Photos (Calculator%)"), pulled a long-accepted calculator-vault app
  following press/child-safety pressure over its use by minors to hide
  content from parents — not a routine App Review catch. Krypta's actual
  purpose differs (an adult E2EE messenger, not a photo-hiding tool), but
  keep marketing copy framed around adult privacy/security use cases and use
  a conservative age rating (17+ is typical for unrestricted user-to-user
  messaging apps) rather than anything that reads as "hide this from someone."
