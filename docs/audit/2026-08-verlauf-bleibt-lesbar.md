# Der Verlauf bleibt lesbar (2026-08-25)

**Branch:** `dev-Daniele`
**Status:** implementiert, 492 Tests grün, `flutter analyze lib test` ohne Fehler
**Kehrt um:** die Entscheidung „Klartext nie auf die Platte" aus dem Mai-Audit

---

## Was war

`Message.toMap` schrieb den Klartext bewusst nicht mit:

> `decryptedContent` is NEVER persisted to disk. Plaintext exists only in RAM
> for UI display and is cleared on chat switch, memory scrub, or app restart.

Dazu drei Stellen, die ihn aktiv aus dem Speicher räumten: beim Wechsel des
Chats, alle zwei Minuten für alle inaktiven Chats, und vor dem Wipe.

Die Folge auf dem Gerät: wer die App verließ und zurückkam, fand in jedem Chat
nur noch `••••••`. Nicht vorübergehend — der Klartext war weg, endgültig, und
aus `encryptedContent` nicht wiederherstellbar, weil der Ratchet-Schlüssel
dieser Nachricht längst verbraucht und nicht gespeichert ist.

Ein Messenger, der seine eigene Geschichte vergisst, ist keiner. Daniel hat es
beim Test von Build 90 gemeldet.

## Warum das Wegwerfen nichts geschützt hat

Der Schutz liegt nicht darin, den Klartext wegzuwerfen, sondern darin, **wo er
liegt**. `EncryptedLocalStore` verschlüsselt mit XChaCha20-Poly1305 unter einem
256-Bit-Schlüssel aus dem Schlüsselbund, nach Möglichkeit in der Secure Enclave
verpackt, mit `first_unlock_this_device` — lesbar also erst nach der ersten
Entsperrung, und nur auf diesem Gerät. Das ist dieselbe Klasse von Schutz, die
Signal und WhatsApp für ihre lokale Datenbank verwenden.

Genau diesen Schlüssel hält die App die ganze Zeit im Arbeitsspeicher
(`Uint8List? _storageKey`). Wer den Arbeitsspeicher lesen kann, liest ihn mit —
und entschlüsselt damit den gesamten Speicher. Den Klartext daneben
wegzuwischen, während der Schlüssel danebenliegt, kostet den Verlauf und
gewinnt nichts.

## Was jetzt gilt

- Der Klartext wird mitgeschrieben, verschlüsselt wie alles andere.
- **Ausgenommen: passwortgeschützte Nachrichten.** Ihr Klartext gehört hinter
  das Passwort, nicht auf die Platte. Solange eine gesperrt ist, steht in
  `decryptedContent` ohnehin nur der mit dem Passwort verschlüsselte Block —
  der bleibt, sonst ließe sie sich nach einem Neustart nie wieder öffnen.
- Das Räumen beim Chatwechsel und der Zwei-Minuten-Timer sind weg. Sie mussten
  weg: jeder folgende Statuswechsel schreibt die Nachrichtenliste zurück, ein
  geräumter Eintrag hätte die gespeicherte Fassung mit `null` überschrieben und
  die Nachricht dauerhaft unleserlich gemacht.
- Das Räumen vor dem Wipe bleibt. Dort ist es richtig: es nullt die Referenzen,
  bevor der Speicher ohnehin gelöscht wird.

## Was das kostet

Ein Angreifer mit **entsperrtem Gerät und entsperrter App** konnte den Verlauf
schon vorher lesen — er steht auf dem Bildschirm. Ein Angreifer mit
**gesperrtem Gerät** kommt an den Schlüssel nicht heran, vorher wie nachher.

Der Unterschied liegt dazwischen: wer eine forensische Kopie des App-Verzeichnisses
zieht **und** den Schlüsselbund dieses Geräts nach der ersten Entsperrung
auslesen kann, bekommt jetzt den Verlauf statt nur der Metadaten. Wer das kann,
konnte vorher schon Kontakte, Chatnamen und Zeitstempel lesen — und hätte den
laufenden Klartext ebenso aus dem Arbeitsspeicher geholt.

Selbstzerstörung, Burn-after-Read und die Notfall-Löschung sind unberührt: sie
löschen Nachrichten, statt sie unlesbar zurückzulassen.

## Tests

`test/core/message_persistence_test.dart` (7 Fälle): gewöhnliche Nachricht
bleibt lesbar, Umlaute und Zeilenumbrüche kommen heil an, der Klartext einer
entsperrten passwortgeschützten Nachricht bleibt draußen, eine gesperrte bleibt
aufsperrbar, ein Systemhinweis bringt keinen Text mit.

Die Erwartung in `test/security/wipe_test.dart` war auf das alte Verhalten
festgeschrieben und wurde mitgezogen.
