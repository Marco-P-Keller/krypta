# iOS / Apple conformance pass — 2026-08-21

Scope: make the iOS build pass App Store Connect validation, stop the app from
announcing itself on the home screen, and remove the two classes of defect that
produced build 68 (unverifiable UIKit state, floating toolchain).

Baseline commit: `2ba4960` (v1.0.0+69). No Dart behaviour was changed; the
messenger, crypto and delivery paths are untouched. `flutter analyze lib` clean,
363 tests green.

**Swift cannot be compiled on this machine (no Xcode).** Every Swift change
below is small and local, but the first real compile happens on Codemagic. The
device checklist at the end is not optional.

---

## 1. Upload blockers (fixed)

### 1.1 App icons carried an alpha channel — ITMS-90717

All 37 PNGs in `AppIcon.appiconset` were RGBA (PNG colour type 6). App Store
Connect rejects the marketing icon for this, *after* the whole build has run.

Every pixel's alpha was already 255, verified before touching anything, so the
conversion to RGB is pixel-for-pixel identical — nothing about the artwork
changed. The re-encode also drops ~40% of the bytes (`1024.png`: 259077 →
168464).

The catalogue also declared `mac`, `watch` and `watch-marketing` idioms from
whatever generator produced it. An iOS-only target has no use for them and
`actool` warns about the unassigned children, so `Contents.json` was rewritten
to the standard iPhone + iPad + `ios-marketing` set and the 24 PNGs no entry
referenced any more were deleted. 13 icons remain, every one referenced.

### 1.2 No privacy manifest

`ios/Runner/PrivacyInfo.xcprivacy` did not exist. Added, and wired into the
Runner target's Resources build phase — a manifest that is only on disk does
not ship.

Contents were derived from the code, not guessed:

- `NSPrivacyAccessedAPITypes` is **empty**, and that is a finding in itself:
  `ios/Runner/*.swift` and `lib/**` use no required-reason API — no
  `UserDefaults`, no file timestamps, no disk space, no boot time. The engine
  and the plugins declare their own usage in their own manifests.
- `NSPrivacyTracking` false, no tracking domains. Nothing links an identifier
  with third-party data.
- Collected data types: anonymous Firebase auth UID (`signInAnonymously`, so no
  email/name/phone anywhere), the FCM token under `fcmTokens/{uid}`, and the
  message payloads relayed through Firestore. The payloads are end-to-end
  encrypted and unreadable to the operator, but they do leave the device, so
  they are declared.

**Marco / Daniel:** these three entries must match the App Store Connect "App
Privacy" answers. Apple compares them.

### 1.3 Six OneDrive collision copies were committed

`ios/Flutter/Generated 2.xcconfig`, `Generated 3.xcconfig`,
`flutter_export_environment 2.sh`, `3.sh`, `Flutter 2.podspec`,
`ios/Podfile 2.lock`.

The originals are all generated and correctly gitignored — the numbered copies
OneDrive writes on a sync collision slipped past those exact-name rules.
Removed from the repo, and `.gitignore` now covers the numbered variants. A
Codemagic preflight step fails the build if a new one is ever committed.

## 2. The disguise was broken by the bundle name (fixed)

`CFBundleDisplayName` and `CFBundleName` both read **"Krypta ECC"**. The app
presents a calculator until the passcode is entered — and the springboard, the
app switcher, Settings.app, the battery list and the share sheet all showed the
real product name the whole time. The cover only ever worked if nobody looked
at the home screen.

Now `Calc`, localized through `Runner/en.lproj` + `Runner/de.lproj`
`InfoPlist.strings` (`Rechner` in German), with `de` added to the project's
`knownRegions` and `CFBundleLocalizations` declaring both languages.
`AndroidManifest.xml` had the same problem and now reads `@string/app_name`,
with `values/` and `values-de/`.

The product name inside the app (`AppConstants.appName`, the settings screen,
the about box) is unchanged — it is only visible after unlock, which is the
point.

> **The name is a judgement call — say so if you disagree.** "Calc" avoids
> being literally identical to Apple's own "Calculator" (guideline 4.1) while
> still reading as a calculator in both languages. Changing it is one line each
> in `ios/Runner/*.lproj/InfoPlist.strings` and
> `android/app/src/main/res/values*/strings.xml`.

## 3. Declared a background mode the app does not implement (fixed)

`UIBackgroundModes` contained `fetch`. There is no
`performFetchWithCompletionHandler`, no `BGTaskScheduler`, no
`setMinimumBackgroundFetchInterval` — anywhere. An unused background mode is a
guideline 2.5.4 rejection. Removed; `remote-notification` stays, because silent
pushes are what actually wake the app for a new message.

Purpose strings were also rewritten and localized. "Authenticate to unlock the
app" says nothing about *why*; reviewers read these.

## 4. Swift robustness (fixed)

Three defects in `AppDelegate.swift`, all in the class of bug that produced
build 68 — UIKit/Security state that is assumed rather than checked.

**4.1 Force-unwrapped `SecAccessControlCreateWithFlags` → crash.**
`createHardwareBoundKey()` did `SecAccessControlCreateWithFlags(...)!`. That
call returns nil on any device or configuration that rejects the flag
combination, and it runs straight off a Flutter method channel — so the app
would crash instead of returning `false` and falling back to software wrapping,
which the function's `Bool` return value already models. Now a `guard`.

**4.2 The app-switcher black cover could stack and never come off.**
`applicationWillResignActive` added a tag-9999 view every time;
`applicationDidBecomeActive` removed exactly one, because `viewWithTag` returns
only the first match. iOS can deliver `willResignActive` more than once before
the next `didBecomeActive` (Siri over the app, a call banner, notification
centre followed by the switcher). Every unbalanced pair left one more opaque
black view on the window, and the leftovers sit on top: a permanently black app
with no way back. Removal is now idempotent — every tagged view comes off, and
resign clears leftovers before adding its own.

**4.3 Four leaked `CFError`s.** `SecKeyCreateRandomKey`,
`SecKeyCreateEncryptedData` and `SecKeyCreateDecryptedData` were each handed an
`Unmanaged<CFError>?` out-param that was never consumed. Each carries a +1
retain the caller owns. Now released.

They are released *without logging*, on purpose. This app hides behind a
calculator; a "Krypta"/"Secure Enclave" line in the device log would hand that
away to anyone who opens Console.app.

## 5. Build pipeline (fixed)

`codemagic.yaml` pins `flutter: 3.41.4` (what the repo analyses and tests
against locally) instead of floating `stable`, and declares `xcode` explicitly.
Build 68 shipped a layout the repo could not explain; a floating toolchain is
how that stays possible.

> **Marco:** replace `xcode: latest` with the exact version once you have had
> one green build, so the next one is actually reproducible.

A preflight step now fails fast, before any build time is spent, on: committed
OneDrive duplicates, an app icon with an alpha channel, and a privacy manifest
missing from the Resources build phase. It runs locally too — paste the script
block into `bash` from the repo root.

---

## 6. Open — needs a decision, or an account nobody here has

### 6.1 Export compliance still blocks every external TestFlight build

`ITSAppUsesNonExemptEncryption` is `true` and there is no
`ITSEncryptionExportComplianceCode`. Correct as a declaration — the app really
does use non-exempt encryption — but every build will sit in export-compliance
review until the questionnaire is answered once in App Store Connect and the
resulting code is either kept there or added to `Info.plist`.

This is an account action, not a code change. **Open since June, and it gates
external testers.**

### 6.2 The typography is fetched from Google's CDN at runtime

`lib/theme/app_typography.dart` uses `google_fonts` with **no bundled font
asset** — `pubspec.yaml` declares no `fonts:` section and there is no `assets/`
directory. Every fresh install therefore reaches out to `fonts.gstatic.com` on
first launch to download Inter, and writes it unencrypted into the app
container.

For a messenger that hides behind a calculator this is worse than a style
choice: it is a network beacon to Google from an app that otherwise only talks
to Firebase, and `fonts.gstatic.com` is not covered by the ATS pinning in
`Info.plist`.

Two ways out, both a visible change, which is why neither was done
unilaterally:

- **Bundle Inter** as an asset — identical look, no network, ~1 MB heavier.
- **Use the system font** (SF Pro on iOS, Roboto on Android) — the actual
  HIG-native answer, smallest binary, but the app will look different.

Recommend the system font: Marco asked for native, and the calculator disguise
is more convincing in the platform's own typeface.

### 6.3 Build numbers are still manual

Codemagic does not increment the build number; it comes from `pubspec.yaml`.
Left that way deliberately — the whole team refers to releases by that number
("build 68 came back broken"), so it should stay a reviewed value in git rather
than a counter nobody can predict. The rule is now in the `codemagic.yaml`
header: **bump `pubspec.yaml` before re-running the workflow**, or App Store
Connect rejects the upload.

### 6.4 Round 2 (2026-08-21, later) — the 3 missing dimensions, done and verified

Section 6.4 originally said the audit workflow died at 3 of 10 agents and
listed a pile of unverified claims. A second Ultracode pass (5 dimensions,
every finding adversarially re-verified against the actual current files —
not just re-asserted) closed that out. Full findings, including the ones that
turned out to be *wrong*, live in the workflow journal; this is the summary
that matters for shipping. See the two new files in `docs/app-store/` for the
Guideline 2.3.1 deliverables this produced.

**Korrektur — das war KEIN False Positive.** Frühere Fassungen dieses
Dokuments führten `private var screenshotEventSink`, gelesen von
`ScreenshotStreamHandler`, als „bekannten False Positive, nicht erneut
melden". Begründung damals: das Muster existiere seit `91664b2` und Build 61
sei damit auf TestFlight gegangen, also kompiliere es.

**Der Compiler sagt etwas anderes.** Der erste echte Xcode-Build (GitHub
Actions, 2026-08-22) brach damit ab:

```
Swift Compiler Error: 'screenshotEventSink' is inaccessible due to
'private' protection level — AppDelegate.swift:636 und :642
```

Der Denkfehler: aus „ein früherer Build ging auf TestFlight" folgt nicht,
dass *dieser* Code kompiliert — der Rückschluss auf den damaligen Dateistand
war nie überprüft. Swifts `private` gilt für den **Typ** (plus dessen
Extensions), nicht für die Datei; ein anderer Typ in derselben Datei kommt
nicht heran. `ScreenshotStreamHandler` ist eine eigene Klasse, also braucht
das Feld `fileprivate`. Behoben.

Lehre für dieses Repo: Solange Swift hier nicht kompiliert werden kann, ist
Empirie aus der Build-Historie **kein** Ersatz für den Compiler — ein
Agentenfund zu Access Control gehört geprüft, nicht wegargumentiert.

#### Guideline 2.3.1 (the calculator disguise) — viable, disclosure path drafted

This was the one item that could have sunk the whole submission and was never
audited before. Verified against Apple's *live* guideline text (fetched
directly) and against three calculator-vault apps currently live on the US
App Store that do the same thing: **a calculator-disguised messenger is not
what 2.3.1 exists to reject.** The guideline's own text requires hidden
functionality to be "described with specificity in the Notes for Review...
and accessible for review" — that disclosure, not a better hiding job, is the
compliant path, and it's a currently-accepted, currently-shipping category
when done openly.

Two deliverables came out of this, both in `docs/app-store/`:
- `2026-08-app-review-notes-draft.md` — the private App Store Connect "Notes
  for Review" text, with bracketed placeholders for Marco's actual review
  build. Explains the disguise to Apple's reviewer honestly and tells them
  exactly how to reach the messenger.
- `2026-08-public-listing-draft.md` — 2.3.1's other half. The Notes field only
  covers "clear to App Review"; the *public* product page has to independently
  satisfy "clear to end users," and nothing in this repo drafted that before.

**Two real things this surfaced that need a decision, not just paperwork:**

1. **The decoy code is dead code.** `code_detector.dart` genuinely verifies a
   decoy-code hash, but `setup_screen.dart`'s onboarding never calls
   `saveDecoyCode()` (only Secret Code and Delete Code exist as setup steps),
   `calculator_screen.dart` explicitly discards a `CodeResult.decoy` match
   ("Decoy mode removed — treat as no match"), and `app.dart`'s `_AppScreen`
   enum has no decoy state and never imports `decoy_messenger_screen.dart`.
   The decoy chat UI exists on disk, fully built, orphaned. **Do not describe
   the decoy feature to Apple** (the review-notes draft already isolates this
   in a clearly marked optional paragraph) until it's actually wired up and
   verified on a real build — restoring it is a product decision for Daniel,
   not something done unilaterally here.
2. **The delete code has no confirmation and no "wiping" transition.**
   Pressing "=" after the delete code runs three ~200ms Argon2id checks (by
   design, for timing safety), then silently replaces the calculator with a
   first-run setup screen — indistinguishable from a fresh install to anyone
   who doesn't know what just happened. Not a code fix in this pass (touching
   the wipe path without a device to test on is exactly the kind of change
   this session is being deliberately conservative about), but the review-notes
   draft carries a mandatory, impossible-to-miss warning as the only available
   mitigation for the App Store submission itself.

Also worth knowing, lower stakes: a lone reviewer testing alone can't
populate the chat list (self-add is explicitly blocked, both client- and
provider-side) — the review notes flag this so an empty chat list doesn't
read as broken. And Apple did once pull a similar calculator-vault app
(2018, "Private Photos (Calculator%)") after child-safety press pressure —
not a routine App Review catch, and Krypta's actual purpose differs, but it's
why the public listing draft avoids any "hide this from someone" framing in
favor of adult privacy/security positioning.

**Refuted, worth knowing so it doesn't get re-proposed:** a finding claimed
the hidden emergency-wipe code is the *only* account/data-deletion path in
the app, which would be a Guideline 5.1.1(v) discoverability problem. False —
Settings already has an unconditional "Danger Zone" section with a plainly
labeled "Emergency Delete" button, reachable through completely normal
in-app navigation after a real unlock, wired to the same
`EmergencyWipeService.wipeEverything()` (local wipe + Firestore data
deletion + Firebase Auth account deletion). No gap here.

#### UIScene / `UIApplicationSceneManifest` — real, high-severity, NOT fixed here

**This is the most important open item in the whole audit.** Confirmed via
Flutter's own breaking-changes documentation (fetched live) and corroborated
by an Apple engineer's forum reply: starting with the SDK release that
follows iOS 26 (i.e. iOS 27, expected fall 2026), **any UIKit-hosted app
built with that SDK — Flutter apps included — must adopt the UIScene
lifecycle or it will not launch at all.** Not a warning, not a review
rejection: a hard assertion crash on first launch, for every user, on any
build compiled with that SDK.

Krypta does not qualify for Flutter's automatic migration (Flutter 3.41 only
auto-migrates an *unmodified* `AppDelegate.swift`, and Krypta's is heavily
customized — screenshot-masking, Secure Enclave key ops, the security method
channel). Nothing has migrated it. `codemagic.yaml`'s `xcode: latest` means
this isn't a "someday" risk: the day Codemagic's default image picks up an
Xcode shipping the iOS 27 SDK, the *next build* fails to launch with zero
code change and zero advance warning.

**Deliberately not fixed in this pass.** The fix means moving plugin
registration and the security method/event-channel wiring out of
`didFinishLaunchingWithOptions` into a new `didInitializeImplicitFlutterEngine`
callback — a real restructuring of the most security-sensitive file in the
app, which per Flutter's own docs changes initialization-order semantics
enough that "touching `FlutterViewController` in `didFinishLaunchingWithOptions`
can now crash." Getting this migration wrong could break the screenshot mask,
the Secure Enclave path, or the app's ability to launch at all, on the *next*
build — before iOS 27 even ships. That is not a change to make without Xcode,
without a device, and without Marco and Codex both in the loop. Flagging this
as the top-priority item for the next session where Marco has build access,
not attempting it blind here.

#### `Podfile.lock` is stale — a second, quieter reproducibility gap

Same class of problem this session already fixed for Flutter/Xcode, just
undiscovered until now: `ios/Podfile.lock` hasn't been regenerated since
2026-03-21 and **doesn't contain `cryptography_flutter` at all** — the pod
providing Krypta's hardware-accelerated crypto backend (BoringSSL/CryptoKit)
was added to `pubspec.yaml` a month *after* the lock file's last commit and
has never been through `pod install`. Four other pods (`cloud_firestore`,
`firebase_auth`, `firebase_core`, `firebase_messaging`, `mobile_scanner`) are
also version-mismatched against what `pubspec.lock` currently resolves.

This means every Codemagic run today silently regenerates `Podfile.lock` at
build time to something nobody has reviewed — worse than an unpinned
toolchain, because it *looks* pinned. Not something fixable from this
machine (no CocoaPods/macOS here).

> **Marco, before the next TestFlight build:** clean checkout, `flutter pub
> get && cd ios && pod install`, review the diff, commit `Podfile.lock` alone
> in its own commit.

Two smaller, related gaps found while checking this, both outside this
repo's reach to fix: `cryptography_flutter` 2.3.4's own iOS podspec ships a
`PrivacyInfo.xcprivacy` but never bundles it (the `resource_bundles` line is
commented out, unmodified template default) — low risk since this plugin
doesn't appear to touch required-reason APIs directly, but worth an upstream
issue. And `mobile_scanner`'s `GoogleMLKit`/`MLKitCommon` dependency chain
has one closed GitHub issue about missing privacy-manifest declarations;
checked it directly — it does **not** document an actual App Store rejection
as an earlier draft of this finding claimed, and the version history suggests
it was already resolved upstream before the version this repo pins. Not a
confirmed problem, just something to watch on Marco's first real upload.

Once Marco has one confirmed-green Codemagic build: pin `xcode: latest` to
the exact version Codemagic resolved it to (`26.4.1` as of this audit — see
`docs.codemagic.io/specs-macos/xcode-26-4/`, confirmed live), and pin
`cocoapods: default` to an explicit version too (currently resolves to
`1.16.2`, one minor behind current). Same reproducibility reasoning as the
Flutter pin already applied.

#### File protection class — corrected *upward*, not fixed here either

An early pass called the lack of an explicit iOS file-protection class
"mostly theatre" for the `.enc` blobs, reasoning that the AES key is already
gated behind `first_unlock_this_device` Keychain access, so ciphertext
protection would be redundant. **That reasoning was wrong, and the correction
matters:** file data protection and Keychain accessibility evict on different
triggers — Keychain's "after first unlock" state survives every *subsequent*
lock until reboot, while `NSFileProtectionComplete`'s class key is evicted
~10 seconds after every lock event. That "locked, but unlocked at least once
since boot" state is exactly the one real-world forensic extraction tools
(GrayKey/Cellebrite-class) routinely operate in on a seized phone — the
dominant real-world scenario for an app whose whole point is surviving
exactly that. Upgrading the `.enc` files to `NSFileProtectionComplete` would
meaningfully close that window; the Keychain-held key remaining separately
accessible doesn't make it redundant.

**Not implemented in this pass.** This needs a small native Swift shim
(`FileManager.setAttributes([.protectionKey: .complete], ...)` reachable from
`file_helper_native.dart`) — genuinely new native security surface, not a
mechanical fix, and not verifiable without a device. Flagging as a real,
credible P2 for a dedicated future pass with Marco and Codex, not attempting
it blind alongside everything else in this one.

The Secure-Enclave-key-vs-Keychain accessibility split (`WhenUnlocked` vs
`AfterFirstUnlock`) that a previous pass flagged as an inconsistency to fix —
**do not fix it.** Verified: `app.dart`'s `KryptaShell._initialize()` reads
`storage.isSetupComplete()` unconditionally on startup, and iOS can
background-launch a terminated app through the same Dart `main()` to handle
an FCM push while the device is locked. Under the stricter `WhenUnlocked`
class that read would fail in exactly that scenario. `AfterFirstUnlock` here
matches Apple's own documented guidance for Keychain items that must survive
a locked-device remote-notification handoff. The SE key's stricter class is
correct *because* it's only ever touched interactively — a different access
pattern, not an inconsistency.

#### Hit targets — mostly fixed, verified against the installed Flutter SDK source

- **Send button** (chat_screen.dart, ~36×36pt visible, was the bare
  GestureDetector hit box too): fixed — 44×44pt tap target, 36pt visual
  circle unchanged, confirmed independently by the workflow's own re-read of
  the file after the fix landed.
- **Chat-rename pencil icon** (chat_settings_sheet.dart): `IconButton` with
  `VisualDensity.compact` was shrinking its tap target from Flutter Material's
  48×48pt default down to 40×40pt — under the 44pt floor, derived directly
  from the installed Flutter 3.41.4 SDK source, not a guess. Fixed —
  `visualDensity` removed.
- **Info-bar clear ("×") button** (chat_screen.dart, the disappearing-message-
  timer / password-set pill): widened from an ~18×18pt hit area to 32×32pt,
  deliberately short of the full 44pt — this badge sits in a stack of info
  bars only a few points apart, and a full-size invisible tap area risked
  overlapping the next bar's own button. That risk is unverified without a
  device, so a smaller, safe increase was chosen instead. Worth a full 44pt
  pass once Marco can eyeball it on a real screen.
- **Calculator keypad, general AppBar icons**: checked and confirmed fine —
  keypad buttons compute to ~77–90pt diameter across real device widths
  (comfortably clear of 44pt), and every other AppBar `IconButton` gets
  Material's 48pt default with no override.

None of these three edits were visually verified — no browser/screenshot
tool was available this session. `flutter analyze` is clean and all 363
tests pass, which rules out compile/type errors, not a rendering regression.

#### Native feel — two closed as non-issues, one real optional-polish item open

- **`themeMode: ThemeMode.dark` hardcoded** — closed, verified correct, not a
  bug. Apple's own Calculator app is dark-only regardless of the system
  Light/Dark setting; matching that is the more authentic disguise choice.
- **No back-swipe gesture anywhere in the app** — closed, confirmed
  deliberate and correctly mitigated. There is genuinely no `Navigator`/
  `PageRoute` anywhere driving the app's 9-screen state machine (by design,
  to avoid OS-visible named-route/deep-link fingerprints), so the standard
  iOS edge-swipe gesture cannot exist — but every screen that needs one has
  an explicit, wired, working back-chevron button. Not worth a
  Navigator-based rewrite; that would reintroduce exactly the fingerprint the
  design avoids, for a gesture whose absence is already covered.
- **Open, optional polish, not urgent:** every screen transition in the app —
  including the highest-frequency one, opening a chat — uses the same plain
  cross-fade. Per Apple's HIG, iOS's own hierarchical-navigation convention is
  a horizontal push (new content slides in from the right), reserving fade for
  unrelated content swaps. Doesn't require reintroducing `Navigator` — the
  existing `AnimatedSwitcher`'s `transitionBuilder` can produce a
  `SlideTransition` just as easily. Left alone in this pass: it's a visible
  design change to the whole app's feel that needs Daniel's sign-off and
  visual verification, not something to change unilaterally alongside
  everything else here.

### 6.5 Android applicationId is still `com.example.kryptaapp`

Google Play rejects any `com.example.*` package. Irrelevant while the Android
build is sideloaded (private edition), blocking the moment it is not. Not
changed here: it would break existing installs and the Firebase Android app
registration.

---

## 7. Device checklist (Marco)

Swift was never compiled here. Before this goes to testers:

1. `flutter pub get && cd ios && pod install`, review the `Podfile.lock` diff,
   commit it separately (§6.4, "`Podfile.lock` is stale") — do this *first*,
   the rest of the checklist builds on top of it.
2. App icon renders on the home screen, no black or white box.
3. The home screen, app switcher and Settings.app show **Calc** / **Rechner** —
   never "Krypta ECC".
4. Launch, rotate portrait → landscape → portrait, switch apps and come back:
   the UI stays correctly positioned (build 68's failure).
5. Background and foreground the app **five times in a row**, including once
   via Siri or a call banner: the app must never come back black (4.2).
6. Screenshot inside a chat is black. If it shows real content the built-in
   fallback engaged — that is by design, but report it.
7. Face ID unlock still works (4.1 touched the Secure Enclave path).
8. Send a message and check the send button and the timer/password "clear"
   badge are comfortably tappable — neither was visually verified this
   session (§6.4, "Hit targets").
9. Upload passes validation with no ITMS-90717 and no ITMS-91053.

**Before an actual App Store (not TestFlight) submission**, also work through
`docs/app-store/2026-08-app-review-notes-draft.md` and
`2026-08-public-listing-draft.md` — both need Marco's real review-build
details filled into the bracketed placeholders, and the decoy-code paragraph
in the Notes draft must stay deleted until that feature is actually restored
(§6.4).
