# Release Notes — Branch `security/hardening`

**Stand:** 23. April 2026
**Commits:** `f7d6a25` bis `8a109c6`

---

## Was wurde gemacht

### Kryptografie & Protokoll

- **Mandatory AAD (Associated Authenticated Data)**: Alle E2E-Nachrichten werden jetzt mit `senderPublicKey || recipientPublicKey` als AAD verschlüsselt. Verhindert Cross-Conversation Replay-Angriffe.
- **Argon2id v2**: Passwortbasierte Verschlüsselung nutzt jetzt Argon2id (19 MiB, 2 Iterationen). Legacy PBKDF2 (v1) wird abgelehnt.
- **Double Ratchet Pruning**: Übersprungene Nachrichtenschlüssel werden jetzt timestamp-basiert nach 7 Tagen gelöscht (statt insertion-order). Max. 200 übersprungene Keys als DoS-Schutz.
- **Ed25519 PreKey-Signaturen**: Signed PreKeys werden mit Ed25519 signiert und verifiziert. v1-Bundles ohne Signatur werden komplett abgelehnt.
- **Key Transparency Log**: SHA-256 Hash-Chain mit Ed25519-signierten Commitments, monotone Epochs.
- **Sealed Sender**: Absender-Identität wird im verschlüsselten Payload versteckt, Server routet nur per Delivery Token.
- **Message Padding**: Traffic-Analyse-Schutz — Nachrichten werden auf nächste Power-of-2 aufgefüllt (min. 256 Bytes).
- **Sensitive Buffer**: Explizites Nullen von Key-Material nach Gebrauch.

### Tresor-Passwort & Zugangscodes

- **Persistent Fail Counter**: Fehlversuche beim Tresor-Passwort überleben App-Neustarts.
- **Exponentielles Lockout**: Warnung nach 2 Versuchen, zunehmende Sperrzeit, Emergency Wipe nach max. Versuchen.
- **Code-Kollisionsprüfung**: Zugangscodes können nicht doppelt vergeben werden.

### Screenshot-Schutz & Erkennung

- **Android**: `FLAG_SECURE` standardmäßig an. Screenshot-Erkennung via `ScreenCaptureCallback` (API 34+) + `ContentObserver` als Fallback.
- **iOS**: Blur-Overlay im App Switcher. Screenshot-Erkennung via `userDidTakeScreenshotNotification`.
- **SnackBar-Benachrichtigung**: "Es wurde versucht, einen Screenshot zu machen" (Schutz an) / "Es wurde ein Screenshot gemacht" (Schutz aus).

### Device Integrity

- **Root/Jailbreak-Erkennung**: su-Binaries, Magisk, Cydia, Substrate, Sandbox-Bypass.
- **Frida-Erkennung**: Prüft `/proc/self/maps` (Android) und Frida-Dylibs (iOS).
- **Debugger-Erkennung**: TracerPid-Check auf Release-Builds.
- **Hardware Key Wrapping**: Datenbank-Key wird per StrongBox (Android) / Secure Enclave (iOS) gebunden.

### Verschlüsselte Control Messages

- Delete-for-Everyone, Read Receipts und Delivery Receipts laufen jetzt über den verschlüsselten Kanal (nicht mehr plain Firestore ACKs).

### Memory Scrub

- Entschlüsselter Chat-Inhalt wird nach Inaktivität automatisch aus dem RAM gelöscht.

### Bugfixes (Commit `8a109c6`)

- `NSPhotoLibraryUsageDescription` in Info.plist hinzugefügt (fehlte für QR-Scanner).
- TextEditingController Memory Leaks in 6 Dialogen gefixt (settings, chat_settings, message_bubble, new_chat).
- `maxLines: 1` für Chat-Name im AppBar (Overflow-Schutz).
- Encryption-Tests an neue AAD-Parameter angepasst (294/294 Tests bestanden).

---

## Was noch zu tun ist vor TestFlight

### Pflicht (blockiert Release)

- [ ] **Export Compliance Fragebogen**: App deklariert `ITSAppUsesNonExemptEncryption = true` (Signal Protocol). Bei der Submission in App Store Connect muss der Encryption Export Compliance Fragebogen ausgefüllt werden.
- [ ] **export_options.plist**: Codemagic referenziert `/Users/builder/export_options.plist`. Sicherstellen, dass diese Datei auf dem Build-Server existiert oder in der Codemagic-Konfiguration generiert wird.
- [ ] **iOS-Testbuild auf echtem Gerät**: Die Security-Features (Secure Enclave, Biometrics, Screenshot-Schutz, Blur-Overlay) können nicht im Simulator getestet werden. Mindestens ein Test auf einem echten iPhone mit iOS 16+.
- [ ] **Security Release Checklist durchgehen**: Siehe `SECURITY_RELEASE_CHECKLIST.md` — alle Punkte abhaken.
- [ ] **Code Signing verifizieren**: Development Team `B97SQSQBMR` und Bundle ID `com.calcchat.ww` korrekt konfiguriert. Provisioning Profile muss Push Notifications und Keychain Sharing enthalten.

### Empfohlen

- [ ] **Avatar-Gradient-Farben vereinheitlichen**: `chat_screen.dart`, `chat_tile.dart` und `chat_settings_sheet.dart` haben leicht unterschiedliche Gradient-Arrays — Avatare sehen auf verschiedenen Screens leicht anders aus.
- [ ] **Hardcoded Color `0xFF30D158`** in `tutorial_screen.dart` durch Theme-Farbe ersetzen.
- [ ] **Firebase-Regeln reviewen**: Sicherstellen, dass Firestore Security Rules die neuen verschlüsselten Control Messages korrekt abdecken.

### Hinweise

- **Minimum iOS Version**: 16.0 (korrekt in Podfile + pbxproj). `AppFrameworkInfo.plist` zeigt 13.0, das ist der Flutter-Framework-Default und hat keinen Einfluss.
- **Alle Secure Enclave APIs** sind iOS 13.0+ kompatibel — kein Problem mit dem 16.0 Deployment Target.
- **294 Tests bestehen**, `flutter analyze lib/` zeigt 0 Issues.
- **Codemagic Workflows**: `ios-testflight` (Release → TestFlight) und `ios-debug` (Debug Build) sind konfiguriert.
