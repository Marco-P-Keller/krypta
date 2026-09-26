# Krypta über iCloud (CloudKit)

Die native App braucht kein Firebase mehr. Server ist die **öffentliche
Datenbank** des CloudKit-Containers `iCloud.com.calcchat.ww`: Apple stellt
Speicher, Anmeldung (der Apple-Account auf dem iPhone) und Mitteilungen.
Keine Cloud Functions, kein FCM, kein Google-SDK in der App.

Code: `Krypta/Services/CloudKitRelay.swift` (Server), `CloudAccount.swift`
(iCloud-Konto, Kennung), `PushService.swift` (Abo für Mitteilungen),
`Shared/PushPayload.swift` (Mitteilung lesen). Die Engine in `KryptaCore`
ist unverändert; sie sieht den Server nur als `Relay`.

## Einmal einrichten

1. **Container anlegen.** In Xcode: Target *Krypta* → *Signing & Capabilities*
   → *iCloud* → *CloudKit*, Container `iCloud.com.calcchat.ww` (mit **+**
   anlegen, falls es ihn noch nicht gibt). Die Entitlements stehen schon in
   `project.yml`. Alternativ im Developer-Portal unter *Identifiers → iCloud
   Containers* und bei der App-ID `com.calcchat.ww` iCloud/CloudKit
   einschalten.
2. **Schema einspielen** (Datensatztypen, Indizes, Rechte):

   ```sh
   # einmalig: Management-Token aus der CloudKit Console (Settings → Tokens)
   xcrun cktool save-token --type management

   xcrun cktool validate-schema --team-id B97SQSQBMR \
     --container-id iCloud.com.calcchat.ww --environment development \
     --file ios-native/CloudKit/schema.ckdb
   xcrun cktool import-schema --team-id B97SQSQBMR \
     --container-id iCloud.com.calcchat.ww --environment development \
     --file ios-native/CloudKit/schema.ckdb
   ```

   Oder von Hand in der [CloudKit Console](https://icloud.developer.apple.com)
   nach der Tabelle unten.
3. **In Production ausrollen:** CloudKit Console → *Deploy Schema Changes…*.
   **TestFlight und App Store benutzen Production**, Xcode-Builds Development.
   Ohne diesen Schritt findet ein TestFlight-Build keine Datensatztypen.

Mehr ist nicht zu tun: Das Abo für Mitteilungen legt die App selbst an.

## Datenmodell

Alle Typen liegen in der öffentlichen Datenbank. Datensatznamen gelten über
alle Typen hinweg, daher die Vorsilben.

| Typ | Name | Felder | Index | Rechte |
|---|---|---|---|---|
| `PublicKey` | `pk-{uid}` | `publicKey` (String) | – | `_creator` Write, `_icloud` Read + Create |
| `PreKeyBundle` | `pb-{uid}` | `bundle` (Bytes, JSON) | – | wie oben |
| `KeyCommitment` | `kt-{uid}-{epoch}` | `uid` (String), `epoch` (Int64), `commitment` (Bytes, JSON) | `uid` Queryable, `epoch` Queryable + Sortable | wie oben |
| `InboxMessage` | zufällig | `recipient`, `alert`, `tag`, `sender`, `messageId` (Strings/Int64), `payload`, `sealed` (Bytes) | `recipient`, `alert` Queryable; Erstellzeit (`___createTime`) Queryable + Sortable | `_creator` Write, `_icloud` Read + Create + **Write** |

`_world` (ohne Anmeldung) bekommt nichts. Auf `recordName` gibt es absichtlich
keinen Index.

Abgebildet auf Firestore: `publicKeys`, `prekeys`, `keyCommitments/{uid}/log`
und `messages/{uid}/inbox` wie bisher; `sealedAccess`, `deliveryTokens` und
`fcmTokens` fallen weg.

## Nachrichten

- **Senden:** ein `InboxMessage` mit `recipient = uid` der Empfängerin.
  Mit Absender stehen `sender`, `messageId` und die (Ende-zu-Ende
  verschlüsselte) Nutzlast `payload` darin, versiegelt nur `sealed`.
- **Empfangen:** CloudKit hat keine Live-Verbindung wie Firestore. Solange die
  App offen ist, fragt sie alle 5 Sekunden, nach dem Senden oder Empfangen
  20 Sekunden lang alle 1,5 Sekunden, und sofort, wenn eine Mitteilung
  eintrifft oder die App nach vorne kommt (`InboxWake`).
- **Löschen nach Empfang:** wie bisher löscht die Empfängerin, was sie
  abgeholt hat, und der Absender seine Kopie, sobald die Zustellung gemeldet
  ist. Dafür braucht `_icloud` Write auf `InboxMessage`.
- **Nach 24 Stunden:** Die stündliche Cloud Function gibt es nicht mehr. Jedes
  Gerät löscht beim Öffnen des Posteingangs (höchstens einmal pro Stunde) bis
  zu 200 Einträge, die älter als 24 Stunden sind.

## Mitteilungen

Die App legt ein `CKQuerySubscription` an: `recipient == meine Kennung AND
alert == 1`, bei neuen Einträgen. CloudKit schickt dann über APNs den festen
Text „Du hast eine neue Nachricht erhalten" (übersetzt über
`alertLocalizationKey`), `mutable-content` und das Feld `tag`. Die
Notification Service Extension macht daraus wie bisher „Neue Nachricht von
Mami". Steuernachrichten (zugestellt, gelesen …) tragen `alert = 0` und wecken
niemanden — früher entschied das `pushPlan` in der Cloud Function.

Ein Abo gehört dem Apple-Account, nicht dem Gerät: Laufen auf zwei iPhones
mit demselben Apple-Account zwei verschiedene Krypta-Kennungen, klingeln
beide. Das andere Gerät kennt den Anhänger nicht und zeigt nur den
neutralen Text.

## Sicherheit: was sich gegenüber Firebase ändert

Unverändert: Inhalte sind Ende-zu-Ende-verschlüsselt (X3DH/PQXDH, Double
Ratchet), Schlüssel werden gegen Sicherheitsnummer, Schlüsselwechsel-Sperre
und Key Transparency geprüft. Weder Apple noch andere Nutzer können
Nachrichten lesen oder unbemerkt Schlüssel unterschieben.

Anders:

- **Apple kennt den Apple-Account.** Firebase sah nur eine anonyme Kennung
  und eine IP-Adresse. CloudKit bindet jeden Eintrag an das iCloud-Konto, das
  ihn schreibt. Apple kann also sehen, welcher Apple-Account welcher
  Krypta-Kennung etwas schickt — nie, was. Die Krypta-Kennung selbst ist
  zufällig und verrät Kontakten nichts über den Apple-Account.
- **Sealed Sender verbirgt den Absender nur noch im Eintrag,** nicht mehr vor
  dem Betreiber. Ohne Anmeldung zu schreiben geht in CloudKit nicht.
- **Rechte nur je Typ.** Firestore-Regeln prüften jedes Dokument einzeln
  („nur die Empfängerin liest ihren Posteingang"). CloudKit kann das nicht;
  jedes angemeldete Gerät mit Krypta darf Posteingänge lesen und löschen.
  Die echte App tut das nur mit dem eigenen. Wer eine manipulierte App auf
  einem gejailbreakten Gerät betreibt, könnte fremde (verschlüsselte)
  Einträge sehen — Empfänger, Zeit, Größe, schreibendes iCloud-Konto — und
  Zustellungen stören. Einen öffentlichen API-Schlüssel wie bei Firebase, mit
  dem das von jedem Rechner aus ginge, gibt es nicht: an den Container kommt
  nur eine mit dem Team signierte App.
- **Kennung = erster Eintrag.** `pk-{uid}` gehört dem iCloud-Konto, das es
  zuerst anlegt. Neue Kennungen sind zufällig und vorher unbekannt. Bei aus
  Flutter übernommenen Kennungen könnte ein Kontakt, der sie kennt, sie vorher
  belegen; dann zeigt die App „Deine Schlüssel konnten nicht veröffentlicht
  werden", und Kontakte mit gespeichertem Schlüssel merken den fremden an der
  Schlüsselwechsel-Sperre.
- **Key Transparency** zählt nur Einträge vom selben iCloud-Konto wie
  `pk-{uid}`, damit niemand mit fremder `uid` einen Widerspruch vortäuschen
  kann.

## Grenzen

- **Nur Apple-Geräte.** Die Flutter-App (Android und ältere iOS-Fassungen)
  bleibt auf Firebase. Native Geräte und Flutter-Geräte erreichen einander
  nicht mehr. Aus Flutter übernommene Chats laufen weiter, sobald auch der
  Kontakt die native Fassung hat — die Kennungen bleiben dieselben.
- **iCloud ist Pflicht.** Ohne angemeldeten Apple-Account lässt sich Krypta
  nicht einrichten; fehlt er später, zeigt die Chatliste einen Hinweis.
- **Anfragen-Kontingent.** Die öffentliche Datenbank ist kostenlos, drosselt
  aber bei sehr vielen Anfragen (`requestRateLimited`); dann wartet die App
  so lange, wie CloudKit sagt.
- **Firebase-Projekt.** `firebase/`, `firebase.json` und die Workflows dafür
  gehören zur Flutter-App und bleiben, solange sie im Umlauf ist.
