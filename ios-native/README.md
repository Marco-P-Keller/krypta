# Krypta — native iOS-App

Der Neubau von Krypta in Swift und SwiftUI. Er spricht dasselbe Protokoll
wie die Flutter-App, läuft aber über **iCloud (CloudKit)** statt Firebase:
native Geräte chatten untereinander, Geräte mit der Flutter-App (Firebase)
erreichen sie nicht mehr. Einrichtung, Datenmodell und was sich an der
Sicherheit ändert: [`CloudKit/README.md`](CloudKit/README.md).

## Aufbau

| Teil | Inhalt |
|---|---|
| `KryptaCore/Sources/KryptaCore` | Protokoll: X3DH, Double Ratchet, Replay-Schutz, Steuernachrichten, Passwort-Nachrichten, Sicherheitsnummern. CryptoKit plus libsodium (XChaCha20-Poly1305, Argon2id). |
| `KryptaCore/Sources/KryptaMessenger` | Messenger-Logik ohne Oberfläche: Kontakte, Anfragen, Senden, Empfangen, Löschfristen. Server hinter `Relay`, Speicher hinter `Vault`. |
| `Krypta/` | Die App: SwiftUI, CloudKit-Relay, Schlüsselbund, verschlüsselter Dateitresor, Rechner-Tarnung, Tresor-Passwort, Screenshot-Schutz, Push, Übernahme der Flutter-Daten. |
| `CloudKit/` | Schema der öffentlichen Datenbank (`schema.ckdb`) und wie man es einspielt. |
| `KryptaNotifications/` | Notification Service Extension: „Neue Nachricht von Mami" statt „Neue Nachricht", ohne Inhalt. |
| `Shared/` | Was App und Extension teilen (Index der Mitteilungen im Schlüsselbund). |
| `KryptaUITests/` | Rundgang, Chat im Demo-Modus, Übernahme aus Flutter, Tresor-Passwort, Mitteilungen. |

## Loslegen

```sh
brew install xcodegen      # einmalig
cd ios-native
xcodegen generate          # erzeugt Krypta.xcodeproj aus project.yml
open Krypta.xcodeproj
```

Vor dem ersten Start auf einem Gerät: iCloud-Container anlegen und Schema
einspielen, siehe [`CloudKit/README.md`](CloudKit/README.md). Im Simulator
mit einem Apple-Account anmelden, sonst lässt sich Krypta nicht einrichten.

## Tests

```sh
# Protokoll und Messenger (macOS, ohne Simulator, ~2 s)
cd ios-native/KryptaCore && swift test

# Kompatibilität mit der Flutter-Fassung, in beide Richtungen
KRYPTA_GEN_VECTORS=1 flutter test test/interop   # Dart erzeugt Nachrichten, KT-Ketten, Flutter-Speicher
(cd ios-native/KryptaCore && swift test)          # Swift liest sie, antwortet
flutter test test/interop                         # Dart liest die Antworten

# Oberfläche (Simulator)
xcodebuild -project Krypta.xcodeproj -scheme Krypta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Demo-Modus

In Debug-Builds startet `-KryptaDemo` (Scheme → Arguments) die App gegen
einen Server im Speicher, mit zwei echten Messengern im selben Prozess als
Kontakten. Kein iCloud, kein Schlüsselbund.

## Mitteilungen

Auf dem Sperrbildschirm steht, **von wem** eine Nachricht kommt — wie in
Nachrichten der Name als Titel, darunter „Neue Nachricht" —, nie, was
drinsteht.

1. Der Absender legt in die Nachricht (`p.nt`) einen Anhänger: acht
   Zufallsbytes plus HMAC mit einem Schlüssel, den nur die beiden kennen
   (Diffie-Hellman der Identitäten). Er ändert sich mit jeder Nachricht und
   nennt niemanden. Kontaktanfragen tragen einen Anhänger aus dem Schlüssel
   der Empfängerin, Steuernachrichten (zugestellt, gelesen …) einen leeren.
2. Das Relay legt den Anhänger als Feld `tag` in den CloudKit-Eintrag, bei
   leerem Anhänger mit `alert = 0`. Das Abo der Empfängerin
   (`CloudKitRelay.subscribeToInbox`) meldet nur Einträge mit `alert = 1` und
   reicht `tag` mit `mutable-content` weiter — früher erledigte das die Cloud
   Function (`pushPlan`).
3. Die Extension prüft ihn gegen den Index im geteilten Schlüsselbund
   (Schlüssel, Name und Kennung je Kontakt, geschrieben von der App), setzt
   den Text, stapelt je Absender und zählt die Zahl am App-Symbol hoch.
4. Ein Tippen auf die Mitteilung öffnet nach Rechner, Face ID und Passwort
   direkt den Chat. Ist die App offen, erscheint ein Banner nur für einen
   anderen als den offenen Chat, nie über Rechner oder Sperre.

Ohne Anhänger (oder wenn die Extension nicht rechtzeitig fertig wird) steht
dort „Du hast eine neue Nachricht erhalten". Zu deployen gibt es nichts: das
Abo legt die App beim Entsperren selbst an.

In den Einstellungen: Mitteilungen an/aus, „Absender nennen" an/aus. Ohne
Namen stapelt iOS auch nicht je Absender — sonst verriete die Zahl der Stapel,
wie viele Leute geschrieben haben.

## Sealed Sender

Im Eintrag auf dem Server steht nicht, **wer** schreibt — nur, an wen, wann
und wie viel.

1. Jede Nachricht trägt den eigenen Zustellschlüssel verschlüsselt mit
   (`_dk`), der QR-Code auch (`dk`). Flutter ignoriert beides.
2. Kennt der Absender den Schlüssel der Empfängerin, legt er nur den Umschlag
   ab (`sealed`): Absender, Nachrichtenkennung und Ratchet-Nachricht stecken
   darin (`SealedSender`, X25519 + XChaCha20-Poly1305 an die Identität der
   Empfängerin).
3. Mit Absender laufen nur noch Anfragen über die Kennung (per QR-Code ist
   schon die Anfrage versiegelt).

Mit Firebase schrieb der versiegelte Weg ohne Anmeldung, und eine Regel
prüfte den Zustellschlüssel. In CloudKit gehört jeder Eintrag einem
iCloud-Konto: Apple sieht also, welcher Apple-Account schreibt, auch wenn der
Eintrag es nicht sagt. Den Schlüssel prüft niemand mehr; der Rückfallweg der
Engine (Server lehnt ab → mit Absender) tritt nicht mehr ein. Siehe
[`CloudKit/README.md`](CloudKit/README.md#sicherheit-was-sich-gegenüber-firebase-ändert).

## Post-Quanten-Handschlag

Ab iOS 26 hängt an jedem signierten Vorabschlüssel ein ML-KEM-768-Schlüssel
(`pqpk`, signiert als `pqs`, gebunden an `spkId`). Der Absender kapselt
dagegen, und das Geheimnis fließt in die Ableitung ein:
`HKDF(DH1 ‖ DH2 ‖ DH3 ‖ SS, "KryptaPQXDH-v1")` — hybrid wie Signals PQXDH.
Wer heute mitschneidet, müsste später X25519 **und** ML-KEM brechen. Das
Chiffrat reist hinter dem Ephemeral in `ek` (32 + 1088 Bytes), weil `p` laut
Regeln höchstens zehn Felder hat.

Hat ein Kontakt einmal ML-KEM gezeigt (`Contact.postQuantum`), nimmt die
Engine keinen Handschlag ohne mehr an und baut keinen ohne auf — ein Server,
der `pqpk` aus dem Bündel entfernt, bekommt keine schwächere Sitzung,
sondern gar keine. Mit Flutter und iOS < 26 bleibt der Handschlag klassisch.

Tests: `swift test` überspringt die ML-KEM-Fälle auf macOS < 26; vollständig
im Simulator:

```sh
cd ios-native/KryptaCore
xcodebuild test -scheme KryptaCore-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Gerät

- Identität und Tresorschlüssel sind nur bei **entsperrtem** iPhone lesbar
  (`WhenUnlockedThisDeviceOnly`), die Tresordateien ebenso
  (`completeUnlessOpen`). Ein gesperrtes Gerät gibt die Chats auch Forensik-
  Werkzeugen nicht heraus. Startet iOS die App bei gesperrtem Gerät, wartet sie
  aufs Entsperren, statt die Einrichtung anzubieten.
- Keine Tastaturen von Drittanbietern.
- Kopierte Nachrichten bleiben auf dem Gerät (keine universelle
  Zwischenablage) und verschwinden nach einer Minute, die Kennung nach fünf.

## Haptik

Schlicht und nur, wo es zählt: Senden, Kopieren, leise beim Eintreffen im
offenen Chat, Erfolg beim Entsperren und Hinzufügen, Fehler bei falschem
Passwort oder nicht zugestellter Nachricht, ein kurzer Ruck beim Löschen und
Blockieren. Der Rechner tippt bei jeder Taste gleich weich, Geheimcode
eingeschlossen. Aus mit der iOS-Einstellung „Systemhaptik".

## Screenshot-Schutz

Der Chat liegt in der Zeichenfläche eines Passwortfelds, die iOS aus
Bildschirmfotos, Aufnahmen und Spiegelungen herausnimmt; dort erscheint
„Inhalt geschützt". Undokumentiertes Verhalten: `ScreenshotProtection.isEffective`
prüft, ob die Fläche gefunden wurde, und die Einstellungen sagen ehrlich, wenn
nicht. Dann deckt die App bei laufender Aufnahme alles ab. Die Meldung an die
Gegenseite läuft in jedem Fall. Im Simulator unter iOS 26.1 geprüft
(Bildschirmfoto im Gerät ist leer); auf echten Geräten mit neuerem iOS
nachprüfen — die Flutter-Fassung hatte mit einer anderen Variante desselben
Tricks ab iOS 26.6 Probleme.

## Tresor-Passwort

Nach Rechner-Code und Face ID die letzte Tür. Argon2id wie die Codes,
Fehlversuche überstehen Neustarts, Pause 2 / 4 / 8 / 16 s, beim fünften Fehler
wird alles gelöscht. Festlegen, ändern, entfernen in den Einstellungen.

## Key Transparency

Wie `lib/security/transparency/`: jede Identität veröffentlicht eine signierte,
verkettete Liste (`KeyCommitment`-Einträge `kt-{uid}-{epoch}`), die Engine prüft die Kette jedes
Kontakts und tauscht in jeder Nachricht die Köpfe aus (`_kt`). Ein Widerspruch
erscheint im Chat und auf der Kontaktseite („Schlüsselprotokoll"). Swift prüft
Dart-Ketten und umgekehrt (Interop-Vektoren).

## Übernahme aus der Flutter-App

Beim ersten Start nach dem Update liest die App den Schlüsselbund von
flutter_secure_storage, den Datenbankschlüssel (auch den in der Secure Enclave
verpackten) und `Documents/krypta_store/*.enc` und übernimmt Identität,
Kennung, Codes, Tresor-Passwort samt Fehlversuchen, Einstellungen, Sprache,
Kontakte, Chats, Nachrichten, Sitzungen, Vorabschlüssel und Schlüsselprotokoll.
Die Tür bleibt dieselbe (gleicher Geheim- und Löschcode), die Kennung auch —
sie wird beim ersten Entsperren in CloudKit veröffentlicht. Kontakte, die noch
die Flutter-App benutzen, erreichen sie dort nicht. Danach werden die
alten Daten gelöscht. Nur Schlüsselbund ohne Datenordner heißt „App war
gelöscht" — dann wird wie in Flutter nur aufgeräumt.

Beweis: `test/interop/flutter_store_fixture_test.dart` schreibt einen echten
Speicher mit dem Dart-Code, `FlutterImportTests` übernimmt ihn und entschlüsselt
danach mit der alten Sitzung eine neue Nachricht von Bob.

## Sprachen

Deutsch, Englisch, Spanisch, Französisch, Italienisch, Niederländisch,
Portugiesisch (`Localizable.xcstrings`, auch in der Extension und für
Info.plist). Umschalten über Einstellungen → Sprache (iOS-Einstellungen der App).

## Test-Schalter (nur Debug)

| Argument | Wirkung |
|---|---|
| `-KryptaDemo` | Chat mit Beispielkontakten, Server im Speicher |
| `-KryptaOffline` | echte App gegen Server im Speicher, kein iCloud |
| `-KryptaReset` | alles Native löschen, wie frisch installiert |
| `-KryptaSeedFlutter <pfad>` | Flutter-Speicher aus `flutter_store.json` anlegen (Update-Test) |
| `-shield.off YES` | Screenshot-Schutz für diesen Start aus (Bildschirmfotos in `ScreensUITests`) |

## TestFlight

Ohne Mac: einen Tag `native-v<Version>-<Build>` pushen, z. B.
`git tag native-v5.0.0-109 && git push origin native-v5.0.0-109`. Der
Workflow `ios-native-testflight.yml` baut, signiert über den
App-Store-Connect-Key und lädt hoch; die Build-Nummer nimmt er als nächste
freie aus App Store Connect.

Vom Mac aus:

```sh
cd ios-native && xcodegen generate
xcodebuild -project Krypta.xcodeproj -scheme Krypta -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Krypta.xcarchive \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/Krypta.xcarchive \
  -exportPath build/ipa -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```

Vorher das CloudKit-Schema in **Production** ausrollen (CloudKit Console →
*Deploy Schema Changes…*): TestFlight- und App-Store-Builds sprechen mit
Production, nicht mit Development.

`ExportOptions.plist` lädt direkt hoch (`destination=upload`). Die Build-Nummer
(`CURRENT_PROJECT_VERSION` in `project.yml`) muss über der letzten in App Store
Connect liegen — auch über denen aus `ios-testflight.yml` (Flutter).
