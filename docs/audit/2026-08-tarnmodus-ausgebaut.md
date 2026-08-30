# Tarn-Messenger ausgebaut, Chatliste verrät keinen Inhalt mehr

**30.08.2026.** Zwei Änderungen, die zusammengehören: beide betreffen das,
was jemand sieht, ohne einen Chat zu öffnen.

## Der Tarn-Messenger

Krypta hatte einen zweiten, falschen Messenger. Neben dem Geheimcode gab es
im Rechner einen **Tarncode**; wer den tippte, landete in einer harmlos
aussehenden Chat-App, vorbefüllt mit „Mom — Did you buy milk?" und
„Alex — See you later!". Gedacht für den Zwangsfall: jemand verlangt, dass du
die App aufmachst, und du zeigst Nachrichten an Mama über Milch.

**Er war seit dem Umbau vom 24.08. unerreichbar.** Im Rechner stand

```dart
case CodeResult.decoy:
  // Decoy mode removed — treat as no match
  break;
```

`DecoyMessengerScreen` wurde nirgends mehr instanziiert, und einen Ort zum
Setzen eines Tarncodes gab es in den Einstellungen nicht. Passend dazu: die
App heißt wieder Krypta ECC, der Rechner ist eine Zugangssperre und keine
Verkleidung.

**Was trotzdem weiterlief:** `app.dart` rief bei jedem Start
`ensureDecoyFilesExist()`, und das schrieb die erfundenen Chats auf die
Platte. Die Begründung im Code war, die Datei solle existieren, damit ihr
*Fehlen* nichts verrät. Das Argument trägt nicht mehr — im Gegenteil. Eine
Datei namens `decoy_chats` mit erfundenen Chats sagt jemandem, der das Gerät
auswertet, dass diese App einen Tarnmodus hat oder hatte. Ein Hinweis ohne
Gegenwert, für einen Modus, den es nicht mehr gibt.

### Die Falle beim Löschen

`saveDecoyData` / `loadDecoyData` heißen wie der Tarn-Speicher, sind aber der
**allgemeine Schlüssel-Wert-Speicher**. `prekey_manager.dart` legt darüber den
PreKey-Zustand ab, die Key-Transparency-Pins laufen auch durch.
`loadData`/`saveData` waren nur Aliase darauf. Wer beim Ausbau nach „decoy"
greift und alles löscht, bricht den Messenger.

Deshalb: umbenannt statt gelöscht. Die Aliase sind zum Original geworden.

### Was jetzt gilt

Weg sind `lib/features/decoy/` (zwei Dateien, ~600 Zeilen), die Verdrahtung in
`main.dart` und `app.dart`, `CodeResult.decoy` samt der dritten Code-Prüfung,
`saveDecoyCode`/`verifyDecoyCode`, und vier Übersetzungen in sieben Sprachen.

Der Zeitschutz im `CodeDetector` bleibt: entscheidend ist, dass **alle**
Prüfungen immer laufen, nicht wie viele es sind. Aus drei parallelen
Argon2id-Läufen werden zwei.

**Das Aufräumen auf bestehenden Geräten** ist der Teil, den man leicht
vergisst. Dort liegen `decoy_chats`, eventuell `decoy_msg_*` und im
Schlüsselbund `krypta_code_decoy`. `LegacyCleanup` räumt das einmalig beim
Start weg.

Die Reihenfolge ist dabei **umgekehrt zum `FreshInstallGuard`**: dort wird der
Merker VOR dem Räumen gesetzt, weil ein Dauerlauf die App nie über die
Einrichtung kommen liesse. Hier ist Löschen wiederholbar und folgenlos, und
die Reste dürfen nicht liegen bleiben, nur weil ein Lauf schiefging — also
erst räumen, dann merken.

Zwei Details in dieselbe Richtung: `purgeLegacyDecoyFiles` **wirft**, wenn der
Speicher noch nicht bereit ist, statt „nichts gefunden" zu melden und sich das
zu merken. Und der Merker heißt `krypta_cfg_legacy_cleanup`, nicht
`..._decoy_purged` — ein Schlüssel mit „decoy" im Namen würde genau das
erzählen, was das Aufräumen beseitigt.

## Die Chatliste

Unter dem Namen stand die letzte Nachricht im Klartext. Die Chatliste ist die
eine Ansicht, die jemand zu sehen bekommt, ohne einen Chat zu öffnen — über
die Schulter, oder weil das entsperrte Telefon kurz aus der Hand gegeben
wurde.

Der Ballon mit der Anzahl **gab es schon** und die Zählung dahinter ist
intakt: beide Empfangswege zählen hoch, wenn der Chat nicht offen ist,
`setActiveChat` setzt beim Öffnen zurück, beide rufen danach
`notifyListeners()`, die Liste hängt an einem `Consumer`. Der Ballon wurde nur
von der Textzeile daneben erschlagen.

`lastMessagePreview` ist ganz aus dem Modell verschwunden, nicht nur aus der
Anzeige. Der Klartext lag damit **zweimal** auf der Platte: im
Nachrichtenspeicher und noch einmal in `chats.enc`. Verschlüsselt zwar, aber
unter demselben Schlüssel — zwei Kopien schützen nicht besser als eine, sie
vergrößern nur die Fläche. `_updateChatPreview` heißt jetzt `_touchChat` und
zieht nur noch Zeitstempel und Zähler nach.

Alter Bestand: `fromMap` liest das Feld nicht mehr, `toMap` schreibt es nicht
mehr. Beim nächsten Speichern der Chatliste fällt es aus der Datei.

Die Zeile bleibt bestehen — Anfrage-Markierung und Tipp-Anzeige sitzen darin —
ist aber sonst leer. Die Tipp-Anzeige verrät keinen Inhalt und bleibt.

## Prüfen

5.7 und 5.8 im Testprotokoll. 568 Tests grün (vorher 555), neu:
`legacy_cleanup_test.dart`, `chat_list_privacy_test.dart`,
`chat_preview_purge_test.dart`.
