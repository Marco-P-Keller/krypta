# Vom Screenshot-Schutz zum Screenshot-Hinweis (2026-08-25)

**Branch:** `dev-Daniele`
**Status:** implementiert, 459 Tests grün, `flutter analyze lib test` ohne Fehler
**Vorgänger:** [`2026-06-screenshot-protection-fix.md`](2026-06-screenshot-protection-fix.md) — überholt

---

## Warum der Schutz weg ist

Der iOS-Schutz aus Build 62 bettete den gesamten Fensterinhalt unter die
„secure canvas" eines versteckten `isSecureTextEntry`-Textfelds. Das ist
undokumentiertes Verhalten, kein API-Vertrag — und **ab iOS 26.6 trägt es
nicht mehr**. Daniel hat das auf dem Gerät gesehen: Screenshot ausgelöst, Chat
im Bild, Schalter in den Einstellungen weiterhin auf „an".

Danach folgten Watchdog, Geometrie-Prüfungen, ein Reparaturlauf nach jedem
Wechsel in den Vordergrund und ein Diagnose-Bildschirm, um herauszufinden,
welcher Layer-Kandidat noch funktioniert — rund 550 Zeilen Swift, die einen
Zustand absichern sollten, den das Betriebssystem nicht mehr zusagt.

**Verhindern lässt sich ein Screenshot auf iOS ohnehin nicht.** Es gibt keine
API, die den Auslöser abfängt; das System meldet die Aufnahme erst *danach*.
Das Schwärzen des Inhalts war der einzige Hebel, und der ist weggefallen.

Die ehrliche Antwort ist deshalb nicht ein weiterer Reparaturversuch, sondern
der Verzicht auf ein Versprechen, das die App nicht halten kann.

## Was stattdessen passiert

Screenshot und Bildschirmaufnahme werden **erkannt und beiden Seiten gemeldet**
— wie bei Snapchat, und wie Signal es bei Aufnahmen tut. Im Chatverlauf steht
dann mittig ein Hinweis:

- „Du hast einen Screenshot gemacht" / „*Name* hat einen Screenshot gemacht"
- „Du hast eine Bildschirmaufnahme gestartet" / „*Name* hat eine
  Bildschirmaufnahme gestartet"

Der Hinweis ist kein Schutz, und er gibt sich auch nicht als einer aus. Er
stellt Symmetrie her: wer mitliest, weiß nicht weniger als der, der aufnimmt.

## Umsetzung

**Ereignis:** `SystemEventKind { screenshot, screenRecording }` auf dem
`Message`-Modell. Persistiert wird nur die Art (`sysEvent`), **nicht der Text** —
der wird beim Rendern aus der Lokalisierung erzeugt und folgt damit einem
späteren Sprachwechsel. `decryptedContent` landet dafür nie auf der Platte.

**Übertragung:** eine Kontrollnachricht (`'screenshot'` / `'recording'`) über
denselben verschlüsselten Kanal wie „gelesen" oder „akzeptiert". Kein neuer
Pfad, keine neue Metadatenspur auf dem Server.

**Erkennung:**
- iOS: `userDidTakeScreenshotNotification` und
  `UIScreen.capturedDidChangeNotification` — beide dokumentiert.
- Der Screenshot-Strom meldet jetzt konstant `false`: blockiert wurde nichts,
  und genau das ist die Aussage. Das Ereignis selbst ist die Nachricht.

**Eine Aufnahme, eine Meldung.** Eine Aufnahme läuft weiter, während man
durch die App navigiert; der Chat-Bildschirm wird dabei jedes Mal neu gebaut
und der Zustandsstrom liefert den laufenden Zustand erneut. Ohne Buchhaltung
sähe die Gegenseite für *eine* Aufnahme bei jedem Öffnen des Chats erneut
„Bildschirmaufnahme gestartet". Deshalb beobachtet `PlatformSecurityService`
die Aufnahme durchgehend — nicht nur, solange ein Chat offen ist — und vergibt
je Aufnahme eine Nummer (`captureSession`); `RecordingNoticePolicy` merkt sich
je Chat die zuletzt gemeldete. Die Grenze ist bewusst asymmetrisch gesetzt: bei
voller Buchhaltung fliegt der älteste Eintrag raus, eine Meldung doppelt ist
harmloser als eine Aufnahme, von der niemand erfährt.

Der Fall „die Aufnahme lief schon, bevor der Chat geöffnet wurde" ist dabei
der wichtigste — genau der heimliche. Er wird gemeldet.

**Android bleibt geschützt.** `FLAG_SECURE` ist eine echte Zusage des Systems.
Wo das Betriebssystem wirklich blockiert, ist Blockieren besser als Melden.

**Einstellung:** aus „Screenshot-Schutz" wird „Screenshot-Hinweis". Aus heißt:
die Erkennung läuft gar nicht erst, und niemand erfährt etwas — auch die
Gegenseite nicht. Der Speicherschlüssel heißt weiterhin historisch
`screenshotProtection`; ein Umbenennen würde die Einstellung bestehender Nutzer
zurücksetzen, und das wäre der schlechtere Tausch.

## Entfernt

| Ort | Was |
|---|---|
| `ios/Runner/AppDelegate.swift` | Maskierung, Watchdog, Geometrieprüfung, Diagnose, `SecureMaskField`, Aufnahme-Abdeckung — 982 → 436 Zeilen |
| `lib/services/platform/platform_security_service.dart` | `refreshScreenshotProtectionState`, `diagnoseScreenshotMask`, `forceSecureMaskCandidate`, Parameter `captureNotice` |
| `lib/features/settings/presentation/screenshot_diagnostics_screen.dart` | ganze Datei |
| `.github/workflows/ios-testflight.yml` | Eingabe `diagnostics`, `--dart-define=KRYPTA_DIAG` |
| `android/.../MainActivity.kt` | `isScreenshotProtectionActive` (auf Android nie nötig) |
| 7 × `lib/l10n/app_*.arb` | 7 Texte, die einen Schutz beschrieben, den es nicht mehr gibt |

## Tests

`test/core/recording_notice_policy_test.dart` (7 Fälle) deckt die
Meldebuchhaltung ab, `test/core/system_event_test.dart` (9) das Modell.

`test/security/screenshot_protection_test.dart` neu geschrieben: Ein- und
Ausschalten der Erkennung, beide Ereignisströme, und zwei Fälle, in denen die
Plattform **nicht** antwortet. Dort gilt bewusst „aus" bzw. „keine Aufnahme" —
eine erfundene Aufnahme würde der Gegenseite eine Meldung schicken, die nie
stattgefunden hat.
