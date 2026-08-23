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

Jetzt steht dort `COVER_NOTIFICATION`, ein einzelner Body ohne Titel:

```
RECHNER
Tippen zum Öffnen
```

Bewusst ohne `title` — iOS zeigt den App-Namen ohnehin darüber, eine zweite
Zeile wäre nur weitere Fläche, die in der Rolle bleiben muss.

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

Muss Marco machen — auf `kryptaecc` hat sonst niemand die Rechte.

```
firebase deploy --only functions --project kryptaecc
```

Wichtig: **nicht** `firebase deploy` ohne `--only`. Der würde auch Rules und
Indexes mitnehmen; das ist in `docs/FIREBASE_RULES_DEPLOY.md` bewusst
getrennt gehalten.

Beim ersten Deploy werden Firestore-Trigger und Scheduler neu angelegt — das
kann ein paar Minuten dauern und verlangt, dass die nötigen APIs im Projekt
aktiviert sind (Cloud Functions, Cloud Build, Artifact Registry, Cloud
Scheduler, Eventarc). Die Firebase CLI bietet an, sie zu aktivieren.

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
