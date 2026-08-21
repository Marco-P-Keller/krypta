# TestFlight-Runbook — Daniel macht die Builds selbst

Stand 2026-08-22, nach Sichtung von Marcos aktuellem `main`.

**Kurzfassung: Marco hat mehr gebaut als „du kannst Builds hochladen".** Es
gibt zwei GitHub-Actions-Workflows, die beide per Knopfdruck laufen und beide
keinen eigenen Mac brauchen. Einer davon löst den Blocker, der seit Juni
offen ist.

---

## Was sich seit dem letzten Stand geändert hat

- **Das Repo heißt jetzt `krypta`** (vorher `kryptarich`). GitHub leitet den
  alten Namen weiter, beide Links funktionieren — deshalb läuft das lokale
  Repo unter dem alten Namen weiter, ohne Probleme.
- **Alle unsere Commits sind in `main`.** Marco hat `audit/2026-05` und
  `fix/build61-delivery` gemerged und die Branches danach aufgeräumt. Nichts
  ist verloren — `6451ca9`, `d713eb5`, `909a139`, `b724d71` und `2ba4960` sind
  alle in `main` enthalten, nachgeprüft.
- **Die Pipeline ist von Codemagic auf GitHub Actions umgezogen.**
  `codemagic.yaml` liegt noch im Repo, ist aber nicht mehr der aktive Weg.
- Marco hat nebenbei einen echten Bug gefixt: in `file_helper_native.dart`
  fehlte ein `await`, wodurch das umgebende `try/catch` Fehler gar nicht
  abgefangen hat.

## Die zwei Workflows

Beide unter **Actions** im Repo, beide mit **„Run workflow"**-Knopf
(`workflow_dispatch`).

### `Firebase Rules` — das ist der wichtige

Deployt `firebase/firestore.rules` ins Projekt `kryptaecc`. Läuft auf einem
Ubuntu-Runner über ein Dienstkonto, komplett ohne lokalen Firebase-CLI-Login.

**Das ist der Blocker, der seit Juni offen ist.** Ohne deployte Rules schlägt
das Nachrichten-Senden fehl, egal welcher Build drauf ist — der X3DH-Fix vom
Juni läuft dann ins Leere. Bisher hieß es immer „nur Marco kann das".
**Jetzt kannst du das selbst.**

Läuft zusätzlich automatisch, sobald sich `firebase/firestore.rules` auf
`main` ändert.

### `iOS TestFlight` — der Build

Baut auf einem `macos-latest`-Runner und lädt nach TestFlight hoch.
Signatur über App-Store-Connect-API-Key (Cloud-Signing), **kein Mac und kein
Zertifikat auf deinem Rechner nötig**.

Drei Eingabefelder beim Start:
- **Build-Nummer** — leer lassen. Dann bildet der Workflow sie automatisch
  aus Offset + Run-Nummer. Du musst `pubspec.yaml` *nicht* mehr hochzählen.
- **run_tests** — anlassen (`flutter analyze` + `flutter test` vor dem Build).
- **upload** — an = hochladen, aus = nur bauen. Zum reinen Ausprobieren, ob
  der Build überhaupt durchläuft, ruhig erst mal ausschalten.

Läuft außerdem automatisch bei einem Tag `v*`.

---

## Ablauf

### Schritt 0 — Prüfen, ob die Secrets schon gesetzt sind

Beide Workflows brauchen hinterlegte Zugangsdaten. Ob Marco die schon gesetzt
hat, ist von außen nicht sichtbar — **schau in Actions nach, ob die Workflows
schon mal grün gelaufen sind.** Falls nicht:

- `Firebase Rules` braucht das Secret `FIREBASE_SERVICE_ACCOUNT`
  → Anleitung: `docs/FIREBASE_RULES_DEPLOY.md`
- `iOS TestFlight` braucht `ASC_KEY_ID`, `ASC_ISSUER_ID` und den API-Key
  → Anleitung: `docs/TESTFLIGHT_GITHUB_ACTIONS.md`

Beide Anleitungen hat Marco geschrieben und sie sind gründlich. Falls die
Secrets fehlen, ist das der einzige Punkt, an dem du ihn noch brauchst — er
muss dir entweder die Werte geben oder sie selbst eintragen.

### Schritt 1 — Rules deployen

Actions → **Firebase Rules** → **Run workflow**.

Mach das **zuerst und unabhängig vom Build**. Es dauert eine Minute, braucht
keinen iOS-Build und beantwortet endlich die Frage, die seit Juni offen ist.
Der Workflow zeigt vorher an, was er vorhat, und bricht mit klarer Meldung ab,
wenn das Dienstkonto nicht stimmt.

### Schritt 2 — Meine iOS-Änderungen dazu

Liegt auf dem lokalen Branch **`ios/apple-conformance`**, abgezweigt von
Marcos aktuellem `main`, ~60 Dateien, noch nicht committed.

Ich habe geprüft: **null Überschneidung** mit dem, was Marco seit `2ba4960`
geändert hat. Er hat nur Workflows, Docs, eine Zeile in
`file_helper_native.dart` und doppelte Testdateien angefasst — keine einzige
Datei, die ich bearbeitet habe.

Sichtbare Änderungen, die du vor dem Commit anschauen solltest:
- Home-Screen-Name ist **Calc** / **Rechner** statt „Krypta ECC"
- Send-Button, Stift-Icon und Timer-„×" haben größere Tap-Flächen
- Taschenrechner-Tasten skalieren Text bei großen Schriftgrößen herunter

**Keine davon wurde visuell verifiziert** — in der Session, in der sie
entstanden, gab es kein Browser-Tool. `flutter analyze` ist clean und die
Tests sind grün; das schließt Compile-Fehler aus, keine Rendering-Regression.

### Schritt 3 — Build starten

Actions → **iOS TestFlight** → **Run workflow**, Build-Nummer leer lassen.

Beim allerersten Mal ruhig **upload = aus** setzen, nur um zu sehen, ob der
Build durchläuft. **Das ist der erste echte Swift-Compile überhaupt** — alle
Änderungen in `AppDelegate.swift` (Screenshot-Masking-Geometrie,
Secure-Enclave-Guard, CFError-Release, idempotente Blackview-Entfernung)
wurden nie kompiliert, auf Windows gibt es kein Xcode. Wenn es hier bricht,
ist das erwartbar und die Fehlermeldung sagt genau wo.

### Schritt 4 — Export-Compliance in App Store Connect

Nach dem Upload steht der Build auf **„Missing Compliance"** und geht nicht an
Tester raus. Grund: `ITSAppUsesNonExemptEncryption` ist `true` (korrekt) und
es gibt keinen Compliance-Code.

Zwei Wege:
1. **Für euren internen Test jetzt:** App Store Connect bietet für interne
   Tester einen Weg, der die Export-Compliance-Prüfung umgeht. Wenn die Option
   auftaucht — für dich und Marco reicht das völlig.
2. **Für externe Tester / App Store später:** Der Fragebogen muss richtig
   beantwortet werden und hat rechtliche Konsequenzen (US-Exportrecht, ggf.
   Selbstklassifizierung bei der BIS plus Jahresbericht). **Das ist keine
   Entscheidung, die ich für euch treffe.** Nicht raten und durchklicken.

### Schritt 5 — Gerätetest

Reihenfolge wichtig, Punkt 2 ist der, an dem Build 68 gescheitert ist:

1. **App-Icon** auf dem Home-Screen: kein schwarzer oder weißer Kasten.
2. **UI-Position:** starten, drehen hoch → quer → hoch, App wechseln und
   zurück. *Bei Build 68 war die ganze UI nach unten/rechts verschoben.*
3. **Name:** Home-Screen, App-Switcher, Einstellungen zeigen **Calc** /
   **Rechner**. Steht dort „Krypta ECC", ist die Tarnung kaputt.
4. **Blackview:** fünfmal in den Hintergrund und zurück, einmal davon über
   Siri oder ein Anruf-Banner. Die App darf **nie** schwarz zurückkommen.
5. **Screenshot** im Chat ist schwarz. Zeigt er echten Inhalt, hat der
   eingebaute Rückfall gegriffen — so gewollt, aber melden.
6. **Face ID** entsperrt noch (der Secure-Enclave-Pfad wurde angefasst).
7. **Tap-Flächen:** Nachricht senden, Timer-„×" antippen. Nie visuell geprüft.

### Schritt 6 — Zustelltest

Jetzt sinnvoll, weil die Rules aus Schritt 1 deployt sind:

- Frischer Chat nach beidseitigem Löschen
- Session-Heal ohne Zutun der Gegenseite
- Ratchet-Kette 5× hin und her
- Offline-Nachzustellung, Neustart-Persistenz

**Diagnose bei Fehlschlag:** Erscheint ein Doc unter `messages/{UID}/inbox`?
Ja → Empfangs-/Entschlüsselungsproblem im Client. Nein → Rules oder Auth.

---

## Offen

- **UIScene / iOS 27 (P1).** Ab der SDK-Version nach iOS 26 startet eine
  UIKit-App ohne UIScene-Adoption gar nicht mehr — Hard-Crash beim Start.
  Krypta ist nicht migriert. Betrifft diesen Build **nicht**, aber der erste
  Build, dessen Runner-Xcode die iOS-27-SDK zieht, bricht ohne jede
  Codeänderung. Marcos Workflow nutzt `macos-latest` und `channel: stable` —
  beide bewegen sich von selbst. Details in
  `docs/audit/2026-08-ios-apple-conformance.md` §6.4.
- **Meine Preflight-Checks hängen in `codemagic.yaml`**, also am toten Strang.
  Die Prüfungen (Icon-Alpha, PrivacyInfo im Bundle, OneDrive-Duplikate) sollten
  nach `ios-testflight.yml` portiert werden, sonst greifen sie nie.
- **Flutter-Version driftet.** Marcos Workflow nutzt `channel: stable` (auf dem
  Runner offenbar 3.47, laut seinem eigenen Kommentar), lokal läuft 3.41.4.
  Das ist genau die Art Nicht-Reproduzierbarkeit, die Build 68 ermöglicht hat.
- **`Podfile.lock`** ist weiterhin veraltet und enthält `cryptography_flutter`
  nicht. Der CI-`pod install` gleicht das beim Bauen aus, im Git bleibt es
  ungeprüft.
- **Codex-Review** für die Konformitäts-Änderungen wurde auf deine Ansage
  übersprungen.
