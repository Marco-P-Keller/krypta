# Firebase Cloud Functions — Stand und offene Punkte

Stand 2026-08-22.

Es gibt zwei Functions in `firebase/functions/index.js`:

| Function | Typ | Zweck |
|---|---|---|
| `onNewMessage` | Firestore-Trigger auf `messages/{recipientId}/inbox/{messageId}` | Push-Benachrichtigung an den Empfänger |
| `cleanupExpiredMessages` | Scheduler, stündlich | Löscht Nachrichten älter als 24 h |

Der Server sieht nie Klartext — beide arbeiten ausschließlich auf Ciphertext
bzw. Metadaten.

---

## Was hier geändert wurde

**Node 18 → Node 22.** Google hat die Runtime `nodejs18` abgeschaltet. Solange
sie in `firebase.json` und `package.json` stand, **war überhaupt kein Deploy
möglich** — unabhängig davon, ob der Code stimmt. Das war der eigentliche
Grund, warum die Functions nie live gingen.

Mit hochgezogen: `firebase-functions` 4.9 → 6.6, `firebase-admin` 12 → 13.
Der v1-API-Import ist jetzt explizit (`require("firebase-functions/v1")`),
weil der Wurzel-Import in v6 mehrdeutig geworden ist.

**Geprüft, nicht nur geschrieben:** `npm install` läuft durch, `node --check`
ist sauber, und das Modul lädt tatsächlich mit beiden Exports
(`npm run check` im Functions-Verzeichnis wiederholt das).

Die Logik der beiden Functions ist **unverändert** — bewusst. Ein
Runtime-Upgrade und eine Verhaltensänderung im selben Schritt macht es
unmöglich zu sagen, woran es lag, wenn danach etwas klemmt.

---

## Die Push-Nachricht und die Tarnung

**Behoben am 2026-08-23.** `onNewMessage` verschickte vorher:

```
Calc — New Message
You have a new encrypted message
```

Die App gibt sich als Rechner aus und heißt auf dem Home-Screen „Calc" bzw.
„Rechner". Ein Rechner, der auf dem Sperrbildschirm verschlüsselte Nachrichten
ankündigt, hebt die Tarnung genau in dem Moment auf, für den sie gedacht ist —
wenn jemand anderes auf das Display schaut. Der Code enthielt bereits die
richtige Vorsichtsmaßnahme für Metadaten (keine Sender-ID im Payload, weil
FCM-Payloads bei Google geloggt werden); nur der sichtbare Text war übersehen
worden.

**Geändert am 2026-09-03 auf Daniels Wunsch.** Aus `Tippen zum Öffnen` wurde:

```
KRYPTA ECC
Du hast eine neue Nachricht erhalten
```

Bewusst ohne `title` — iOS zeigt den App-Namen ohnehin darüber, eine zweite
Zeile wäre nur weitere Fläche.

**Was der neue Text preisgibt.** Ein Blick auf den Sperrbildschirm verrät
jetzt, **dass** etwas angekommen ist, nicht mehr nur, dass die App
Aufmerksamkeit will. Unter einem Anzeigenamen, der seit `d62998f` ohnehin
„Krypta ECC" lautet, ist das ein kleiner Schritt — die Begründung von 2026-08-23
oben stand auf der Annahme eines Rechner-Namens, und die gilt für iOS nicht
mehr. Auf **Android** heißt die App weiterhin „Calc"; dort kostet der Satz
mehr, und falls Android je ausgeliefert wird, gehört das noch einmal
abgewogen. Absender, Inhalt und Vorschau bleiben draußen — die müssten durch
FCM, und das protokolliert Google.

**Ein Text für beide Fälle, und der Server kann es nicht besser.** Daniel
wollte zwischen „neue Nachricht" und „Anfrage erhalten" unterscheiden. Eine
Kontaktanfrage ist aber ein ganz normales Inbox-Dokument; die Markierung `_rq`
liegt **innerhalb** des Chiffrats. Damit die Function den Unterschied sähe,
müsste der Absender ein Klartextfeld ans Dokument hängen — und damit erführe
Firebase genau, wann zwischen zwei Konten eine neue Verbindung entsteht. Das
ist die Sorte Metadatum, die diese App nicht hergibt. Der saubere Weg wäre
eine **iOS Notification Service Extension**, die auf dem Gerät entschlüsselt
und den Text dort ersetzt; das braucht ein neues Xcode-Target und einen Mac.

**Warum dieser Weg und nicht der stille Push.** Naheliegend wäre gewesen, den
`notification`-Block ganz zu streichen und nur `content-available` zu schicken.
Das ist für die Tarnung sauberer, hätte hier aber nichts gebracht: der
Client-Handler ist leer. `firebaseMessagingBackgroundHandler` in
`lib/services/notification/notification_service.dart` tut nichts, `onMessage`
und `onMessageOpenedApp` ebenfalls nicht. Ein stiller Push hätte also
schlicht *gar keine* Wirkung gehabt, und zusätzlich drosselt iOS stille Pushes.

Die Nachrichten selbst kommen ohnehin nicht über den Push, sondern über
`lib/security/transport/privacy_polling.dart`. Der Push ist reine
Aufmerksamkeit, kein Transportweg — deshalb kostet ein anderer Text auch keine
Zustellung.

**Nicht lokalisiert.** Sauber ginge das über APNs `loc-key` plus
`Localizable.strings` in jedem `.lproj`, und jede dieser Dateien müsste ins
Xcode-Projekt eingehängt werden — ohne Mac nicht blind zu machen. Alle
aktuellen Nutzer sind deutschsprachig, deshalb Deutsch als ehrlicher Default
statt eines halben Mechanismus.

**Strengere Variante, falls die Tarnung wichtiger ist als überhaupt
benachrichtigt zu werden:** `notification` ganz weglassen und nur Daten
schicken. Es geht keine Nachricht verloren — das Polling holt sie —, der
Nutzer erfährt nur erst beim Öffnen davon.

---

## Offen: 1st Gen vs. 2nd Gen

Beide Functions sind 1st Gen. 2nd Gen (`firebase-functions/v2`,
`onDocumentCreated` / `onSchedule`) wäre die heute empfohlene Form.

**Kein Drop-in.** Eine bereits als 1st Gen deployte Function lässt sich nicht
in place umstellen — sie muss gelöscht und unter demselben Namen neu angelegt
werden. In der Lücke gehen Events verloren. Von hier aus ist der deployte
Zustand von `kryptaecc` nicht einsehbar, deshalb bewusst als eigener,
späterer Schritt stehengelassen.

Ein Detail, das dabei für 2nd Gen spricht: `cleanupExpiredMessages` braucht
als 1st-Gen-Scheduler eine App-Engine-App im Projekt (für Cloud Scheduler).
Fehlt die, scheitert der Deploy dieser Function. 2nd Gens `onSchedule`
braucht das nicht. Falls der erste Deploy genau daran scheitert, ist das der
Grund — und dann lohnt der Umstieg sofort.

---

## Deploy

Seit 2026-08-24 ist Daniel im Firebase-Projekt, der Deploy hängt also nicht
mehr allein an Marco.

Wichtig in beiden Wegen: **nicht** `firebase deploy` ohne `--only`. Der würde
auch Rules und Indexes mitnehmen; das ist in `docs/FIREBASE_RULES_DEPLOY.md`
bewusst getrennt gehalten.

### Weg 1 — GitHub Actions (bevorzugt)

`.github/workflows/firebase-functions.yml`, Actions → **Firebase Functions**
→ Run workflow. Braucht keinen lokalen Rechner und keinen Firebase-Login.

Auswahl im Dialog:

| Eingabe | Zweck |
|---|---|
| `beide` | Standard — beide Functions |
| `onNewMessage` | nur der Push-Trigger |
| `cleanupExpiredMessages` | nur das 24-Stunden-Aufräumen |

Der Lauf prüft vorher `npm ci` und `npm run check`, damit ein Deploy nicht
mitten drin an einem Syntaxfehler scheitert, und listet danach auf, was
tatsächlich im Projekt liegt.

**Bewusst nur manuell**, nie automatisch auf Push: ein Functions-Deploy legt
Trigger und einen Scheduler an, dauert Minuten und wirkt sofort auf das
Live-Projekt mit echten Nutzern.

**Bewusst ohne `--force`.** Liegen in `kryptaecc` Functions, die es in
`firebase/functions` nicht gibt, will die CLI sie löschen. Ohne `--force`
lässt sie sie stehen und meldet es nur. Marco hat einmal „die noch nötigen
Functions bzw. deren Integration" erwähnt — falls dort etwas liegt, von dem
dieses Repo nichts weiß, darf ein Deploy von hier es nicht wegräumen.

#### Dienstkonto

Derselbe Secret-Name wie beim Rules-Workflow: `FIREBASE_SERVICE_ACCOUNT`.
Anlegen wie in `docs/FIREBASE_RULES_DEPLOY.md` Abschnitt 1 beschrieben — nur
mit mehr Rollen, weil ein Functions-Deploy deutlich mehr anfasst als das
Veröffentlichen von Regeln:

- **Cloud Functions Admin** (`roles/cloudfunctions.admin`)
- **Service Account User** (`roles/iam.serviceAccountUser`) — sonst darf das
  Dienstkonto die Laufzeit-Identität der Function nicht setzen
- **Cloud Build Editor** (`roles/cloudbuild.builds.editor`) — der Quellcode
  wird serverseitig gebaut
- **Artifact Registry Administrator** (`roles/artifactregistry.admin`) — dort
  landet das gebaute Image
- **Cloud Scheduler Admin** (`roles/cloudscheduler.admin`) — nur für
  `cleanupExpiredMessages`
- **Service Usage Admin** (`roles/serviceusage.serviceUsageAdmin`) — um beim
  ersten Lauf die nötigen APIs zu aktivieren
- **Firebase Admin** (`roles/firebase.developAdmin`)

Ehrlich gesagt: diese Liste zusammenzuklicken ist mühsam, und eine fehlende
Rolle zeigt sich erst mitten im Deploy. Wer es schneller will, gibt dem
Dienstkonto **Editor** plus **Service Account User** — das deckt alles ab, ist
aber deutlich mehr Recht als nötig. Falls das Dienstkonto ohnehin nur für
diesen einen Zweck existiert und der Schlüssel im Repo-Secret liegt, ist das
vertretbar; sauberer bleibt die Einzelliste.

### Weg 2 — lokal von einem Rechner

Setzt einen interaktiven Browser-Login voraus, geht also nur in einem echten
Terminal (nicht in einer nicht-interaktiven Shell):

```
npx firebase-tools login
npx firebase-tools deploy --only functions --project kryptaecc
```

Dafür braucht der eingeloggte **Google-Account** dieselben Rechte wie oben
das Dienstkonto. „Zum Projekt hinzugefügt" allein reicht nicht — mit der
Rolle *Viewer* scheitert der Deploy an `Permission denied`.

### Was beim ersten Deploy passiert

Firestore-Trigger und Scheduler werden neu angelegt; das dauert einige
Minuten. Die nötigen APIs müssen im Projekt aktiviert sein (Cloud Functions,
Cloud Build, Artifact Registry, Cloud Scheduler, Eventarc) — die CLI bietet
an, das zu erledigen, wenn die Rechte reichen.

Scheitert genau `cleanupExpiredMessages`, ist fast sicher die fehlende
App-Engine-App im Projekt der Grund (siehe Abschnitt *1st Gen vs. 2nd Gen*).
Dann erst einmal nur `onNewMessage` deployen, damit der Push läuft, und die
Umstellung auf 2nd Gen als eigenen Schritt planen.

### Was der Deploy NICHT repariert

Die Nachrichten selbst laufen nicht über die Functions. `firestore.rules`
lässt den Absender direkt in `messages/{empfänger}/inbox/` schreiben, und
`lib/security/transport/privacy_polling.dart` holt diese Inbox alle 10 bis 30
Sekunden ab. `onNewMessage` verschickt nur die Benachrichtigung.

Nach dem Deploy kommt also der **Hinweis** an, dass etwas da ist. Kommt eine
Nachricht danach immer noch nicht im Chat an, liegt die Ursache woanders —
dann ist die Frage an Marco, welche Function die Zustellung machen soll und
wo ihr Code liegt.

### Damit Push auf iOS überhaupt ankommt

Der Deploy allein genügt nicht. Die Kette ist:

1. `aps-environment` im Entitlement — vorhanden
   (`ios/Runner/Runner.entitlements`, `RunnerRelease.entitlements`)
2. **APNs-Auth-Key (`.p8`) in der Firebase Console hinterlegt**, unter
   Projekteinstellungen → Cloud Messaging → die iOS-App. Fehlt der, kann FCM
   iOS überhaupt nicht erreichen — unabhängig von den Functions
3. Regel für `fcmTokens` live, sonst lehnt der Catch-all das Speichern des
   Tokens ab (`firebase/firestore.rules`)
4. `onNewMessage` deployt

**Punkt 2 ist die aktuelle Blockade — geprüft, nicht vermutet.** Im
Function-Log steht bei jedem Sendeversuch:

```
onNewMessage: Push notification failed: Invalid APNs credential.
```

Zuletzt gesehen am 2026-09-03 um 09:26 UTC. Die Function läuft also, **findet
den Geräte-Token** und scheitert erst beim Zustellen an APNs. Punkt 1, 3 und 4
sind damit erledigt; es fehlt ausschließlich der `.p8`.

Der Weg dorthin: **erzeugen** lässt sich der Schlüssel nur im
Apple-Entwicklerkonto (Zertifikate, IDs & Profile → Schlüssel → neuer
Schlüssel mit Haken bei „Apple Push Notifications service"), und dafür braucht
es **Admin-Rechte** — vermutlich Marco. Die `.p8` gibt es **nur einmal** zum
Herunterladen. **Hochladen** darf Daniel als Editor selbst, unter
Projekteinstellungen → Cloud Messaging → die iOS-App, zusammen mit **Key-ID**
(steht neben dem Schlüssel) und **Team-ID** (oben rechts im Entwicklerkonto).
Danach wirkt es sofort, ohne neuen Build und ohne neuen Deploy. Zu beachten: in
`lib/services/notification/notification_service.dart` liegt der ganze
Anmeldevorgang in einem `try`, das den Fehler nur in Debug-Builds ausgibt —
schlägt einer dieser Schritte fehl, passiert sichtbar **gar nichts**.

---

## Noch nicht gebaut

Marco hat „die noch nötigen Functions bzw. deren Integration" erwähnt, ohne
zu sagen welche. Aus dem Code heraus fehlt nichts, was die App aktiv
aufruft — die beiden vorhandenen decken Push und TTL ab, alles andere läuft
direkt über Firestore mit den Rules als Schutz.

Was sich aus dem Audit als sinnvolle Ergänzung anbietet, aber niemand
bestellt hat: serverseitige Rate-Limits und ein Inbox-Kontingent gegen
Flooding. Das ist im Repo als „Scope 2" dokumentiert und wäre echter
Anti-Abuse-Gewinn — aber erst nach einer Ansage, welche Grenzen gelten
sollen.
