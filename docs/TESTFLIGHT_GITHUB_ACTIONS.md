# TestFlight über GitHub Actions – ohne eigenen Mac

Der Workflow `.github/workflows/ios-testflight.yml` baut die iOS-App auf einem
von GitHub gehosteten macOS-Runner, signiert sie und lädt sie nach TestFlight
hoch. Es wird kein lokaler Rechner und kein Xcode benötigt – nur ein Browser.

Ablauf im Workflow:

1. Flutter einrichten, `flutter pub get`, `pod install`
2. `flutter analyze` + `flutter test` (abschaltbar)
3. Version aus `pubspec.yaml`, Build-Nummer automatisch
4. Signatur vorbereiten (App-Store-Connect-API-Key)
5. `flutter build ios --no-codesign` → `xcodebuild archive` → `xcodebuild -exportArchive`
6. Upload nach TestFlight per `xcrun altool`
7. IPA + dSYMs als Build-Artefakt, Schlüsselmaterial vom Runner löschen

---

## 1. Voraussetzungen in App Store Connect

Das muss **einmalig** im Browser erledigt sein:

- Die Bundle ID **`com.calcchat.ww`** ist unter
  [developer.apple.com → Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
  registriert.
- Für diese Bundle ID ist die Capability **Push Notifications** aktiviert –
  `ios/Runner/RunnerRelease.entitlements` setzt `aps-environment = production`.
  Fehlt die Capability, schlägt das Signieren fehl.
- In [App Store Connect](https://appstoreconnect.apple.com/apps) existiert ein
  **App-Datensatz** für diese Bundle ID. Ohne App-Datensatz wird der Upload mit
  *"No suitable application records were found"* abgelehnt.

## 2. App-Store-Connect-API-Key erstellen

1. [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
2. Reiter **Team Keys** → **+**
3. Name z. B. `GitHub Actions`, Rolle **App Manager** (für Cloud-Signing
   nötig; **Developer** reicht nicht, weil dabei Zertifikate erzeugt werden)
4. **Generate** → die `.p8`-Datei herunterladen.
   **Der Download ist nur ein einziges Mal möglich.**
5. Notieren: **Key ID** (10 Zeichen, steht in der Tabelle) und
   **Issuer ID** (UUID, steht über der Tabelle)

## 3. GitHub Secrets setzen

Repo → **Settings → Secrets and variables → Actions → Secrets → New repository secret**

| Secret | Inhalt |
|---|---|
| `ASC_KEY_ID` | Key ID, z. B. `A1B2C3D4E5` |
| `ASC_ISSUER_ID` | Issuer ID, z. B. `69a6de70-…` |
| `ASC_KEY_P8` | **Inhalt** der `.p8`-Datei |

Für `ASC_KEY_P8` einfach die `.p8` in einem Texteditor öffnen und alles
einfügen – inklusive `-----BEGIN PRIVATE KEY-----` und
`-----END PRIVATE KEY-----`. Base64-kodiert (ein- oder mehrzeilig) wird
ebenfalls akzeptiert; der Workflow erkennt beides automatisch.

### Optionale Variablen

Reiter **Variables** (nicht Secrets). Nur nötig, wenn von den Defaults
abgewichen werden soll:

| Variable | Default | Zweck |
|---|---|---|
| `APPLE_TEAM_ID` | `B97SQSQBMR` | Apple Developer Team |
| `IOS_BUNDLE_ID` | `com.calcchat.ww` | Bundle Identifier |
| `IOS_BUILD_NUMBER_OFFSET` | `69` | Basis für die Build-Nummer |

## 4. Build starten

Repo → **Actions** → **iOS TestFlight** → **Run workflow**

> Der Button erscheint erst, wenn die Workflow-Datei im **Default-Branch**
> (`main`) liegt.

Eingaben:

| Feld | Bedeutung |
|---|---|
| `build_purpose` | steht im Titel des Laufs, damit man Läufe später auseinanderhält |
| `build_number` | leer lassen für automatisch |
| `revoke_oldest_dev_cert` | nur anhaken, wenn der Build am Zertifikatslimit scheitert – siehe Abschnitt 6 |
| `run_tests` | `true` = analyze + test vorher ausführen |
| `upload` | `false` = nur bauen, nicht hochladen (zum Testen der Pipeline) |

Alternativ startet der Workflow automatisch beim Push eines Tags `v*`:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Nach dem Upload dauert Apples Verarbeitung typischerweise 5–30 Minuten, danach
taucht der Build in TestFlight auf. Die Freigabe an Tester passiert weiterhin
in App Store Connect.

## 5. Build-Nummern

TestFlight lehnt eine Build-Nummer ab, die für dieselbe Version schon
hochgeladen wurde. Der Workflow berechnet deshalb:

```
Build-Nummer = IOS_BUILD_NUMBER_OFFSET + GITHUB_RUN_NUMBER
```

`GITHUB_RUN_NUMBER` zählt pro Workflow monoton hoch, die Nummer steigt also
automatisch. Der Default-Offset `69` stammt aus dem damaligen Stand von
`pubspec.yaml`. Der erste erfolgreiche Actions-Upload war Build `84`
(Version 4.1.0) am 2026-08-23.

Kollidiert eine Nummer trotzdem – etwa weil parallel über Codemagic gebaut
wurde – gibt es zwei Wege:

- einmalig eine freie Nummer im Feld `build_number` eintragen, oder
- die Variable `IOS_BUILD_NUMBER_OFFSET` dauerhaft erhöhen.

## 6. Signatur: automatisch oder manuell

**Standard (nichts weiter zu tun):** Sind nur die drei `ASC_*`-Secrets gesetzt,
läuft der Build mit **automatischem Cloud-Signing**. Xcode legt Zertifikat und
Provisioning-Profil über den API-Key bei Apple selbst an. Kein `.p12`, kein
Mac, kein Keychain-Export.

### Wenn „maximum number of certificates" kommt

Apple führt **zwei getrennte Kontingente**, und die Fehlermeldung sagt nicht,
welches voll ist:

- **Distribution**-Zertifikate — davon gibt es wenige pro Team. Die legt man
  bewusst an, sie werden selten voll.
- **Development**-Zertifikate — die legt `xcodebuild archive` beim
  automatischen Signieren **selbst** an, jedes Mal, wenn ein Runner signiert,
  der das noch nie getan hat. Ein CI-Runner ist bei jedem Lauf eine frische
  Maschine, also füllt sich dieser Topf von allein.

Praktisch heißt das: Im Developer-Portal sieht unter *Certificates* alles frei
aus (dort schaut man auf Distribution), und der Build scheitert trotzdem — weil
der Development-Topf voll ist. Genau dieser Fall trat am 2026-08-22 auf.

Dagegen gibt es beim manuellen Start die Checkbox **„Zuerst das älteste
Apple-Development-Zertifikat widerrufen"**. Sie ist standardmäßig aus und
greift nur im automatischen Modus. Angehakt läuft vor dem Build
`scripts/asc_certs.py revoke-oldest --min-count 2`.

Was das Skript garantiert (abgesichert durch `scripts/test_asc_certs.py`):

- Es fasst **ausschließlich** Development-Zertifikate an. Ein Distribution-
  Zertifikat zu widerrufen würde jede Release-Signatur des Teams brechen —
  auch die von Marcos anderen Apps.
- Es widerruft nie das einzige vorhandene Zertifikat.
- Unterhalb von `--min-count` passiert nichts, denn dann ist nichts voll.

Den aktuellen Stand ohne jede Änderung ansehen:

```bash
export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=AuthKey_XXX.p8
python3 -m pip install 'pyjwt[crypto]'
python3 scripts/asc_certs.py list
python3 scripts/asc_certs.py revoke-oldest --dry-run   # zeigt nur, ändert nichts
```

Alternative ohne Widerruf: auf manuelles Signing umstellen (siehe unten). Dann
legt die CI überhaupt keine Zertifikate mehr an.

**Manuell (optional):** Sobald zusätzlich die folgenden Secrets gesetzt sind,
schaltet der Workflow automatisch auf manuelles Signing um:

| Secret | Inhalt |
|---|---|
| `IOS_DIST_CERT_P12` | Distribution-Zertifikat als `.p12`, Base64-kodiert |
| `IOS_DIST_CERT_PASSWORD` | Passwort des `.p12` |
| `IOS_PROVISIONING_PROFILE` | App-Store-Provisioning-Profil (`.mobileprovision`), Base64-kodiert |

### `.p12` ohne Mac erzeugen

Geht mit `openssl` auf jedem System (Linux, WSL, Windows mit Git Bash):

```bash
# 1) Privaten Schlüssel + Certificate Signing Request erzeugen
openssl genrsa -out ios_dist.key 2048
openssl req -new -key ios_dist.key -out ios_dist.csr \
  -subj "/emailAddress=DEINE@MAIL.TLD/CN=Krypta Distribution/C=DE"

# 2) ios_dist.csr im Browser hochladen:
#    developer.apple.com → Certificates → + → Apple Distribution
#    danach die erzeugte ios_distribution.cer herunterladen

# 3) .cer + Key zu .p12 zusammenführen
openssl x509 -in ios_distribution.cer -inform DER -out ios_dist.pem -outform PEM
openssl pkcs12 -export -legacy \
  -inkey ios_dist.key -in ios_dist.pem -out ios_dist.p12 \
  -passout pass:EIN_PASSWORT

# 4) Base64 für das GitHub-Secret
openssl base64 -A -in ios_dist.p12
```

Das Provisioning-Profil wird unter *Profiles → + → App Store Connect* erzeugt,
heruntergeladen und ebenfalls Base64-kodiert:

```bash
openssl base64 -A -in Krypta_AppStore.mobileprovision
```

## 7. Troubleshooting

| Fehler | Ursache / Lösung |
|---|---|
| `Secrets ASC_KEY_ID, ASC_ISSUER_ID und ASC_KEY_P8 fehlen` | Schritt 3 nachholen |
| `No suitable application records were found` | App-Datensatz in App Store Connect fehlt (Schritt 1) |
| `The provided entity includes an attribute with a value that has already been used` | Build-Nummer schon vergeben → `build_number` setzen oder Offset erhöhen |
| `No profiles for 'com.calcchat.ww' were found` | Bundle ID nicht registriert, oder API-Key hat nicht die Rolle *App Manager* |
| `Your account has reached the maximum number of certificates` | Meist der **Development**-Topf, nicht Distribution — im Portal sieht deshalb alles frei aus. Workflow mit angehakter Checkbox „ältestes Development-Zertifikat widerrufen" neu starten, siehe Abschnitt 6 |
| `resource fork, Finder information, or similar detritus not allowed` | Extended Attributes – der Workflow ruft `scripts/strip_xattrs_ios.sh` bereits auf, Details in `docs/IOS_ARCHIVE_CODESIGN.md` |
| `Missing Push Notification Entitlement` | Capability *Push Notifications* für die Bundle ID aktivieren |
| `The train version 'X' is closed for new build submissions` (90186)<br>`CFBundleShortVersionString must contain a higher version` (90062) | `version:` in `pubspec.yaml` liegt nicht über der höchsten Version bei App Store Connect. Der Schritt *Version gegen App Store Connect prüfen* fängt das seit 2026-08-23 vorab ab und nennt die Zahl |
| `Invalid Export Compliance Code` (90592) | `ITSEncryptionExportComplianceCode` fehlt in `ios/Runner/Info.plist`, obwohl die App nicht-ausgenommene Verschlüsselung erklärt. Code siehe unten |
| `The bundle uses a bundle name or display name that is already taken` (90129) | Der Tarn-Name gehört einer fremden App. **Achtung: dieser Fehler kommt erst NACH dem Upload**, in Apples Verarbeitung — der Workflow ist da längst grün. Der Schritt *Version gegen App Store Connect prüfen* fängt das seit 2026-08-23 vorab ab, siehe Abschnitt 10 |

## 9. Version und Exportkonformität

Beides prüft der Workflow inzwischen **vor** dem Bauen, weil beides sonst erst
beim Upload auffällt — am 2026-08-23 nach 26 Minuten mit fertigem, signiertem
IPA.

`scripts/asc_app_state.py` fragt den echten Stand bei App Store Connect ab:

```bash
export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=AuthKey_XXX.p8
export BUNDLE_ID=com.calcchat.ww
python3 scripts/asc_app_state.py show               # Versionen + Exportkonformität
python3 scripts/asc_app_state.py check --version 3.0.1
```

**Version:** `version:` in `pubspec.yaml` muss über der höchsten Version liegen,
die App Store Connect für diese Bundle ID kennt — App-Store- *und*
TestFlight-Versionen zählen. Achtung: diese Historie steht nicht im Repo. Die
pubspec sagte lange `1.0.0`, während unter derselben Bundle ID bereits `3.0.0`
veröffentlicht war.

**Exportkonformität:** `ITSAppUsesNonExemptEncryption` ist in der `Info.plist`
absichtlich **nicht gesetzt**.

Vorher stand dort `<true/>`, mit dem Kommentar, die Frage werde in App Store
Connect beantwortet. Genau das verhindert diese Kombination aber: steht der
Schlüssel auf `true` und daneben kein `ITSEncryptionExportComplianceCode`,
lehnt `altool` den Upload direkt ab (ITMS-90592) — der Fragebogen kommt nie.
Aufgefallen ist das nie, weil frühere Builds von einem Mac aus über Xcode
hochgeladen wurden, das interaktiv fragt; die CI validiert strenger.

Ohne den Schlüssel fragt Apple pro Build in App Store Connect nach der
Verschlüsselung. Der Build lädt hoch und steht in TestFlight zunächst als
*Missing Compliance*, bis die Fragen dort beantwortet sind.

**Diese Fragen müssen beantwortet werden, bevor an Tester verteilt werden
kann.** Für Krypta ist die Sache nicht trivial: die App implementiert das
Signal-Protokoll als Kernfunktion, das fällt nicht unter die einfachen
Ausnahmen (nur Authentifizierung, nur Betriebssystem-Verschlüsselung, Schlüssel
unter 56 Bit). Üblich ist dann der Mass-Market-Weg mit einer Selbsteinstufung
beim BIS, die einmal gemacht und jährlich erneuert wird.

Den Wert **nicht** auf `false` setzen, nur damit der Upload durchgeht. Das ist
eine Erklärung gegenüber der US-Exportkontrolle, keine Build-Einstellung.

Liegt später eine Konformitätsdokumentation bei Apple vor, kommt deren Code in
die `Info.plist`, und der Fragebogen entfällt:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
<key>ITSEncryptionExportComplianceCode</key>
<string>DEN-CODE-AUS-APP-STORE-CONNECT</string>
```

Ob eine solche Erklärung hinterlegt ist, zeigt `asc_app_state.py show` unter
*Exportkonformitäts-Erklärungen* (Stand 2026-08-23: keine).

Zum Eingrenzen von Build-Problemen: Workflow mit `upload = false` starten. Dann
läuft alles bis zur fertigen `.ipa`, die als Artefakt am Run-Ergebnis hängt,
ohne dass eine Build-Nummer bei Apple verbraucht wird.

## 8. Verhältnis zu Codemagic

`codemagic.yaml` bleibt unverändert und funktionsfähig. Beide Pipelines können
parallel bestehen; sie müssen sich lediglich keine Build-Nummer teilen (siehe
Abschnitt 5). Soll Codemagic abgelöst werden, kann `codemagic.yaml` gelöscht
werden, sobald der Actions-Workflow einmal erfolgreich durchgelaufen ist.

## 9. Sicherheitshinweise

- Der `.p8`-Key, die Keychain und installierte Profile werden am Ende jedes
  Runs vom Runner gelöscht – auch wenn der Build fehlschlägt (`if: always()`).
- Für das Signing-Keychain wird ein Wegwerf-Passwort aus Run-ID und
  Run-Attempt verwendet; es wird nirgends persistiert.
- Der Workflow läuft mit `permissions: contents: read`.
- `GoogleService-Info.plist` liegt im Repo und enthält keine geheimen
  Schlüssel – Firebase-Zugriff wird über Security Rules kontrolliert.
- Der API-Key hat Zugriff auf das gesamte Developer-Team. Bei Verdacht auf
  Kompromittierung: Key in App Store Connect widerrufen und neu erzeugen.

## 10. Der Anzeigename

`CFBundleDisplayName` und `CFBundleName` sind das, was auf dem Home-Screen, im
App-Switcher, in den Einstellungen und im Teilen-Menü steht.

**Stand 2026-08-24: bewusst der Produktname „Krypta ECC", kein Tarn-Name.**
Entschieden von Daniel. Begründung: Die App ist im App Store ohnehin öffentlich
als *Krypta ECC* gelistet — ein Rechner-Name auf dem Home-Screen hätte also nur
eine halbe Tarnung gebracht, dafür aber bestehende Kunden verwirrt, die ihre App
wiedererkennen wollen. Der Taschenrechner vor der Code-Eingabe bleibt, ist damit
aber eine Zugangssperre und keine Tarnung.

Wer das umdrehen will, muss auch den Store-Eintrag umbenennen lassen (nur Marco),
sonst entsteht wieder dasselbe halbe Ergebnis.

### Namenskollisionen (ITMS-90129)

Was hier auch immer steht, darf keiner **fremden** App gehören. Sonst lehnt Apple
den Build ab — mit *"The bundle uses a bundle name or display name that is already
taken"*.

**Das Tückische:** `altool` prüft den Namen nicht. Der Lauf meldet
`VERIFY SUCCEEDED` und `UPLOAD SUCCEEDED`, die GitHub-Action wird grün, und erst
Apples serverseitige Verarbeitung lehnt danach ab. Sichtbar wird das nur in App
Store Connect unter *Build-Uploads* (Status „Fehlgeschlagen") und per E-Mail. Ein
Fehlversuch kostet einen kompletten Lauf.

Am 2026-08-23 genau so passiert: Build 84 lief mit `Calc` (gehört Michael
Wesemann) und `Rechner` in der deutschen Lokalisierung (gehört **Apple selbst**)
— zwei Kollisionen auf einmal.

Deshalb prüft der Workflow das vorab:

```bash
python3 scripts/asc_app_state.py check-names
```

Das sammelt **alle** Namen, unter denen die App erscheinen kann — die
Basis-`Info.plist` und jede `*.lproj/InfoPlist.strings` — und fragt den
öffentlichen App-Store-Katalog nach exakten Treffern. Der **eigene**
App-Store-Name gilt nicht als Konflikt; deshalb geht „Krypta ECC" durch, obwohl
der Katalog dafür einen Treffer liefert (Connexa GmbH, also wir).

Einen Namen vorab prüfen, ohne etwas zu ändern:

```bash
python3 scripts/asc_app_state.py check-names --own-name "Krypta ECC"   --info-plist ios/Runner/Info.plist --lproj-dir ios/Runner
```

**Grenze der Prüfung:** Der Katalog kennt nur *veröffentlichte* Apps. Ein
reservierter, noch unveröffentlichter Name taucht dort nicht auf. Ein Treffer ist
also ein sicheres Nein, kein Treffer ein starkes — aber kein garantiertes — Ja.
