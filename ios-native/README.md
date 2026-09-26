# Krypta — native iOS-App

Der Neubau von Krypta in Swift und SwiftUI. Er spricht dasselbe Protokoll
wie die Flutter-App: Swift- und Flutter-Geräte chatten miteinander über
dasselbe Firebase-Projekt.

## Aufbau

| Teil | Inhalt |
|---|---|
| `KryptaCore/Sources/KryptaCore` | Protokoll: X3DH, Double Ratchet, Replay-Schutz, Steuernachrichten, Passwort-Nachrichten, Sicherheitsnummern. CryptoKit plus libsodium (XChaCha20-Poly1305, Argon2id). |
| `KryptaCore/Sources/KryptaMessenger` | Messenger-Logik ohne Oberfläche: Kontakte, Anfragen, Senden, Empfangen, Löschfristen. Server hinter `Relay`, Speicher hinter `Vault`. |
| `Krypta/` | Die App: SwiftUI, Firestore-Relay, Schlüsselbund, verschlüsselter Dateitresor, Rechner-Tarnung. |
| `KryptaUITests/` | Rundgang durch die App, Chat im Demo-Modus. |

## Loslegen

```sh
brew install xcodegen      # einmalig
cd ios-native
xcodegen generate          # erzeugt Krypta.xcodeproj aus project.yml
open Krypta.xcodeproj
```

## Tests

```sh
# Protokoll und Messenger (macOS, ohne Simulator, ~2 s)
cd ios-native/KryptaCore && swift test

# Kompatibilität mit der Flutter-Fassung, in beide Richtungen
KRYPTA_GEN_VECTORS=1 flutter test test/interop   # Dart erzeugt Nachrichten
(cd ios-native/KryptaCore && swift test)          # Swift liest sie, antwortet
flutter test test/interop                         # Dart liest die Antworten

# Oberfläche (Simulator)
xcodebuild -project Krypta.xcodeproj -scheme Krypta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Demo-Modus

In Debug-Builds startet `-KryptaDemo` (Scheme → Arguments) die App gegen
einen Server im Speicher, mit zwei echten Messengern im selben Prozess als
Kontakten. Kein Firebase, kein Schlüsselbund.

## Noch offen gegenüber der Flutter-App

- Push-Benachrichtigungen (FCM/APNs)
- Tresor-Passwort als zusätzliche Sperre, Fehlversuch-Zähler mit Löschung
- Schutz vor Bildschirmfotos (die Gegenseite wird bereits benachrichtigt)
- Key-Transparency-Log und Gossip (`_kt`)
- Weitere Sprachen (bisher Deutsch)
- Übernahme vorhandener Daten aus der Flutter-App (derzeit Neueinrichtung)
