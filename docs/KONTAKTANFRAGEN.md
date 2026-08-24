# Kontaktanfragen — Entwurf

Stand: 2026-08-24. **Noch nicht gebaut.** Vorlage für Daniels Freigabe und
Codex' Review, bevor Code entsteht.

---

## Was heute passiert

Fügt A den Nutzer B hinzu und schreibt, kommt die Nachricht **nie** an —
solange B nicht seinerseits A hinzugefügt hat. Sie wird nicht etwa aufgehoben,
sondern **vom Server gelöscht**. Fügt B den Nutzer A später hinzu, ist die
Nachricht endgültig weg.

Der Grund steht im Code, an zwei Stellen — `messenger_provider.dart:1898`
(Live-Empfang) und `:2144` (Polling):

```dart
// Reject messages from unknown senders. Do NOT auto-create contacts.
final contact = contactForId(senderId);
if (contact == null) {
  await _firestore.deleteRelayedMessage(userId!, change.doc.id);
  continue;
}
```

Das ist Absicht (Hardening-Commit `f7d6a25`): wer nur eine fremde User-ID
kennt, soll in dieser App nichts ablegen können. Der Preis ist, dass ein
Erstkontakt nur funktioniert, wenn beide Seiten sich blind hinzufügen — und
dass die erste Nachricht dabei verloren geht, ohne dass es jemand merkt.

## Zielbild

Das übliche Anfragemuster, wie Signal und WhatsApp es fahren, aber strenger:
**geschrieben wird erst nach der Annahme.** Damit kann keine Nachricht mehr
verloren gehen — es gibt sie schlicht noch nicht.

| Schritt | A sieht | B sieht |
|---|---|---|
| A fügt B hinzu | „Anfrage gesendet", Schreibfeld gesperrt | Anfrage mit *Annehmen / Ablehnen / Blockieren* |
| B nimmt an | Chat offen | Chat offen |
| B lehnt ab | unverändert „Anfrage gesendet" | Anfrage verschwindet |
| B blockiert | unverändert „Anfrage gesendet" | Kontakt blockiert |

**Ablehnen und Blockieren sehen für A gleich aus — nämlich nach nichts.** Das
ist beabsichtigt: A mitzuteilen „du wurdest abgelehnt" oder gar „du wurdest
blockiert" verrät eine Entscheidung, die B allein gehört. A kann in beiden
Fällen erneut anfragen; ob die Anfrage ankommt, entscheidet sich auf B's
Gerät.

---

## 1. Datenmodell

Neues Feld am `Contact`, **getrennt von `TrustState`**:

```dart
enum ContactRequestState {
  established,   // angenommen — beide dürfen schreiben
  outgoing,      // ich habe angefragt, keine Antwort
  incoming,      // jemand hat mich angefragt, ich entscheide
  declined,      // ich habe abgelehnt — die Gegenseite darf erneut anfragen
}
```

Dazu `declineCount` (int, Standard 0).

**Warum kein neuer `TrustState`.** `TrustState` beschreibt die *kryptografische*
Vertrauenslage: `unverified`, `verified`, `keyChanged`, `blocked`. Ob ich
jemanden kenne, ist eine andere Achse — ein Fremder kann kryptografisch
einwandfrei sein. Würde beides in einen Aufzählungstyp wandern, bräche die
Logik um `keyChanged` und `blocked`, und genau die schützt vor MITM
(`contact_model.dart:141-145`, `messenger_provider.dart:722`).

`blocked` bleibt also, wo es ist. Blockieren schlägt jede Anfrage.

**Persistenz und Migration.** `Contact.fromMap` prüft heute schon
feldweise (`if (map.containsKey('trustState'))`). Fehlt `requestState` im
gespeicherten Datensatz, gilt **`established`**.

Das ist der Migrationspfad und er ist nicht verhandelbar: alle bestehenden
Kontakte gelten nach dem Update als angenommen. Ohne das stünden Daniels und
Marcos laufende Chats nach dem Update als offene Anfrage da, und beide könnten
nicht mehr schreiben.

## 2. Wie eine Anfrage reist

**Nicht als Kontrollnachricht.** Kontrollnachrichten (`delivered`, `read`,
`delete`, `unlock`) werden mit einem HMAC signiert, dessen Schlüssel aus dem
gemeinsamen Geheimnis der Sitzung stammt (`messenger_provider.dart:769`). Zu
einem Fremden existiert noch keine Sitzung, also auch kein Schlüssel.

**Stattdessen als erste echte Nachricht.** A holt B's PreKey-Bundle
(`prekeys/{B}`, öffentlich lesbar), führt den normalen X3DH-Handschlag und
sendet eine verschlüsselte Nachricht, deren **innerer** Payload die Markierung
`_rq: 1` trägt und keinen Text enthält. Der Server sieht davon nichts — die
Markierung liegt innerhalb der Verschlüsselung.

Die Annahme läuft danach als gewöhnliche Kontrollnachricht (`accepted`): zu
diesem Zeitpunkt gibt es eine Sitzung, weil B A's Anfrage entschlüsselt hat.

Für die Ablehnung wird **nichts** gesendet.

## 3. Der geöffnete Spalt im Empfangspfad

Das ist die Stelle, die Codex am genauesten ansehen sollte.

Heute wird bei unbekanntem Absender sofort verworfen. Künftig:

```
Absender ohne angenommenen Kontakt
  ├─ Kontakt existiert und ist blockiert      → verwerfen, löschen
  ├─ offene Anfragen ≥ 20                     → verwerfen, löschen
  ├─ declineCount ≥ 3                         → verwerfen, löschen
  ├─ publicKeys/{sid} nicht abrufbar          → verwerfen, löschen
  ├─ Entschlüsselung schlägt fehl             → verwerfen, löschen
  ├─ innerer Payload ohne `_rq`               → verwerfen, löschen
  └─ sonst → Kontakt als `incoming` anlegen, Anfrage anzeigen
```

Drei Eigenschaften, die dabei erhalten bleiben müssen:

- **Von Fremden wird genau eine Sache angenommen: eine Anfrage ohne Inhalt.**
  Eine beliebige Nachricht von einem Unbekannten wird weiterhin verworfen.
  Der Spalt ist enger als „Nachrichten von Fremden zulassen".
- **Der provisorische Kontakt wird erst gespeichert, wenn die Entschlüsselung
  gelungen ist.** Sonst könnte jeder mit Müll-Payloads Einträge erzeugen.
- **Die TOFU-Grundlinie wird beim Anlegen gesetzt** (`firstSeenIdentityKey`),
  genau wie in `addContact` (`messenger_provider.dart:487-495`). Damit greift
  `_verifyIdentityConsistency` ab der ersten Nachricht.

Beide Empfangspfade — Live-Listener und Polling — brauchen dieselbe Logik.
Sie sind heute getrennt implementiert und **liefen bei früheren Änderungen
schon einmal auseinander**; die Prüfung gehört deshalb in eine gemeinsame
Funktion, nicht zweimal hingeschrieben.

## 4. Senden gesperrt bis zur Annahme

`Contact.canSendMessages` (`contact_model.dart:143`) wird erweitert:

```dart
bool get canSendMessages =>
    trustState != TrustState.keyChanged &&
    trustState != TrustState.blocked &&
    requestState == ContactRequestState.established;
```

Die Anfrage selbst muss an dieser Sperre vorbei — sie läuft über einen eigenen
Weg (`sendContactRequest`), nicht über `sendMessage`.

**Zwei Übergänge, die beim Hinzufügen entstehen:**

- Ich füge jemanden hinzu, von dem bereits eine Anfrage offen ist
  (`incoming`) → direkt `established`. Wer selbst hinzufügt, hat zugestimmt;
  ihn danach noch auf einen Knopf „Annehmen" zu schicken, wäre eine
  Rückfrage nach einer bereits getroffenen Entscheidung.
- Ich füge jemanden hinzu, den ich vorher abgelehnt habe (`declined`) →
  `outgoing`, und mein `declineCount` für ihn wird zurückgesetzt. Der Zähler
  bremst fremdes Anklopfen, nicht meine eigene Entscheidung.

Im Chat ist das Schreibfeld gesperrt, solange nicht `established`. Mit einem
Text, der sagt warum: bei `outgoing` „Warte auf Antwort", bei `incoming`
„Nimm die Anfrage an, um zu schreiben".

## 4b. QR-Code: Zeigen heisst Zustimmen

Wer seinen QR-Code herzeigt, will den Kontakt. Für ihn soll die Rückfrage
entfallen — der Scanner soll sofort schreiben können.

**Das ging mit dem bisherigen QR-Inhalt nicht.** Er lautete
`{v, uid, ik, fp}`: Nutzerkennung, öffentlicher Schlüssel und dessen Hash.
Alle drei stehen ohnehin in `publicKeys`, für jeden lesbar. Wer eine ID kennt,
baut den ganzen Code nach, ohne ihn je gesehen zu haben. „Ich habe deinen Code
gescannt" liess sich damit nicht nachweisen — und eine automatische Annahme
darauf zu stützen hätte die Anfragesperre still für jeden geöffnet, der eine ID
kennt.

**Deshalb ein Einmal-Token.** Der Code ist jetzt `v: 2` und trägt zusätzlich
`rt`, ein zufälliges Token aus 24 Bytes. Das zeigende Gerät merkt es sich im
Arbeitsspeicher, zehn Minuten lang, und löst es genau einmal ein.

| Schritt | |
|---|---|
| B zeigt seinen Code | Gerät gibt ein frisches Token aus und merkt es sich |
| A scannt | bekommt das Token mit |
| A's Anfrage | trägt `_rt` im verschlüsselten Payload |
| B empfängt | Token stimmt → **direkt angenommen**, keine Rückfrage |
| B meldet zurück | `accepted` — A's Sperre fällt ebenfalls |

Fehlt das Token oder ist es abgelaufen, läuft alles wie gewohnt über die
Rückfrage. **v1-Codes bleiben lesbar**: ein Gerät mit älterem Stand zeigt
weiterhin solche, und dann gilt eben der gewöhnliche Weg.

Das Token liegt bewusst nur im Arbeitsspeicher und lebt kurz. Es gilt für den
Moment, in dem zwei Menschen nebeneinanderstehen — nicht darüber hinaus.

## 5. Missbrauchsschutz

Nach dem Umbau kann jeder, der eine User-ID kennt, einen Eintrag in der
Chatliste des anderen erzeugen. Das ist der unvermeidliche Preis dafür, dass
Fremde einen erreichen können. Drei Bremsen:

| Bremse | Wert | Wirkung |
|---|---|---|
| offene Anfragen | 20 | darüber hinaus wird still verworfen |
| Ablehnungen je Absender | 3 | danach kommt von dieser ID nichts mehr durch |
| Blockiert | — | schlägt alles, unbegrenzt |

Die Zähler stehen lokal am Kontakt. Ein Angreifer kann sie nicht zurücksetzen,
ohne dass der Empfänger ihn selbst annimmt oder entblockt.

**Bewusst nicht serverseitig.** Ein Limit in den Firestore-Regeln wäre
wirksamer gegen einen entschlossenen Fluter, verrät dem Server aber, wer wem
zum ersten Mal schreibt — genau das Metadatum, das Sealed Sender verbirgt.
Für drei Nutzer ist die lokale Bremse angemessen; wenn die App wächst, gehört
das noch einmal auf den Tisch.

## 6. Oberfläche

**Chatliste.** Anfragen erscheinen in der normalen Liste, markiert. Kein
getrennter Posteingang — bei der aktuellen Nutzerzahl wäre das Overhead.

**Im Chat, bei `incoming`.** Leiste über dem Schreibfeld mit *Annehmen*,
*Ablehnen*, *Blockieren*. Nach der Annahme verschwindet sie.

**Im Chat, bei `outgoing`.** Hinweis „Anfrage gesendet" und ein Knopf *Erneut
anfragen*. Der Knopf funktioniert immer — ob die Anfrage ankommt, entscheidet
die Gegenseite, und A erfährt es nicht.

**Blockieren allgemein.** Heute steckt der Block-Knopf ausschließlich im
Warnblock für einen geänderten Schlüssel (`chat_settings_sheet.dart:355`) —
ein gewöhnlicher Kontakt lässt sich gar nicht blockieren. Das wird ein
regulärer Eintrag in den Chat-Einstellungen, immer verfügbar, mit Rückfrage.

Alle neuen Texte gehen über die `.arb`-Dateien in allen sieben Sprachen.

## 7. Was bewusst nicht gebaut wird

- **Kein Text an der Anfrage.** Eine Anfrage trägt keinen Inhalt. Sonst wäre
  sie der Kanal, den der Spalt gerade nicht öffnen soll.
- **Keine Rückmeldung über Ablehnung oder Blockierung.** Siehe oben.
- **Kein serverseitiges Limit.** Siehe 5.
- **Keine Anfrage-Historie.** Abgelehnte Anfragen hinterlassen nur den Zähler,
  keinen Verlauf.

## 8. Tests

Die reine Zustandslogik gehört in eine testbare Einheit, unabhängig von
Firebase — so wie `KeyPublishStatus` es vormacht:

- Übergänge: `outgoing` → `established` bei Annahme; `incoming` → `declined`
  bei Ablehnung; `declined` → `incoming` bei erneuter Anfrage
- `declineCount` zählt und sperrt ab 3
- Blockiert schlägt jeden Übergang
- Beidseitiges Hinzufügen: wer selbst `outgoing` hat und eine Anfrage bekommt,
  landet direkt auf `established` — wer selbst angefragt hat, hat zugestimmt
- Hinzufügen bei offener `incoming`-Anfrage → direkt `established`
- Hinzufügen nach eigener Ablehnung → `outgoing`, `declineCount` zurückgesetzt
- `canSendMessages` ist false in `outgoing`, `incoming`, `declined`
- Migration: ein gespeicherter Kontakt ohne `requestState` lädt als
  `established`
- Obergrenze: die 21. offene Anfrage wird verworfen
- QR-Token: gültiges Token → direkt `established`; abgelaufenes, fremdes oder
  fehlendes Token → gewöhnliche Rückfrage; dasselbe Token ein zweites Mal →
  keine Wirkung mehr

Dazu ein Durchlauf über den Empfangspfad mit den sechs Verwerfungsgründen
aus Abschnitt 3.

## 9. Offene Risiken

**Für Codex besonders:**

1. Der geöffnete Spalt im Empfangspfad (Abschnitt 3) — reicht die Reihenfolge
   der Prüfungen, und wird wirklich nur bei gültiger Entschlüsselung *und*
   vorhandener `_rq`-Markierung ein Kontakt angelegt?
2. Live-Listener und Polling dürfen nicht auseinanderlaufen.
3. Die Migration bestehender Kontakte auf `established` — greift sie in beiden
   Ladepfaden?
4. Ob `canSendMessages` wirklich überall auf dem Sendeweg abgefragt wird, oder
   ob es einen Pfad gibt, der daran vorbeikommt.

**Produktseitig für Daniel:** Nach dem Umbau kann jeder, der eure IDs kennt,
euch anklopfen. Heute kann das niemand. Das ist die Änderung, nicht ein
Nebeneffekt davon.
