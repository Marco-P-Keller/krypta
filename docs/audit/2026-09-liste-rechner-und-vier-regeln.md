# Die Chatliste, der freiwillige Rechner und die vier Löschregeln

**22./23.09.2026.** Daniels Liste („Krypta – Funktionen") nennt drei Dinge:
die vier Lösch-Funktionen im Chat, die Nachrichtenanzeige in der Chatliste
und den Taschenrechner, der optional werden soll. Der Reihe nach, mit dem,
was jeweils wirklich im Code stand.

## Die vier Löschregeln

Die Liste unterscheidet vier Fälle:

1. Selbstlösch-Timer für den **gesamten Chat**, ab Zustellung.
2. Derselbe Timer für **einzelne Nachrichten**.
3. **Nach Ansehen löschen**, für einzelne Nachrichten oder den ganzen Chat.
4. Die Nachricht zur **einmaligen Ansicht**.

„Alle vier Funktionen sind bereits implementiert", steht darunter. Zwei
waren es: 1 und 4, dazu 3 in der Fassung für den ganzen Chat („Direkt nach
dem Lesen"). **2 und 3-je-Nachricht gab es nicht mehr.** Sie waren am
02.09.2026 abgeschafft worden, und zwar mit Absicht: die einmalige Nachricht
hatte sie abgelöst, „drei Konzepte für geht wieder weg wurden eines". Im
Eingabefeld standen seither zwei Einträge, „Aus" und „Einmal ansehen".

Wer das nicht weiss, sieht eine Funktionsliste, in der zwei Punkte fehlen,
und nennt das einen Fehler. Genau so steht es in der Liste.

### Was jetzt gilt

Die Wahl je Nachricht ist ein Blatt statt eines Aufklappmenüs: vier Fälle,
drei davon brauchen einen Satz Erklärung, dazu sechs Fristen. In ein
Aufklappmenü am Bildschirmrand passt das nicht, ohne dass die Hälfte
abgeschnitten wird — daran krankte schon die alte Liste mit sechs Fristen und
Burn after read.

Die Entscheidung selbst liegt in `RegelPolicy` und nicht in der Ansicht, weil
sie eine Regel ist und keine Darstellung. Sie beantwortet genau eine Frage:
welche Frist an der Nachricht hängt und **woher** sie kommt.

Die Herkunft ist der Teil, den man leicht übersieht. Eine Chat-Frist folgt
später der aktuellen Einstellung des Chats, weil sie beiden Seiten gehört und
zwischen ihnen abgeglichen wird; eine eigene behält die Nachricht, auch wenn
der Chat danach umgestellt wird. Vor dem 22.09. ging jede Nachricht mit
`selfDestructFromChat: true` hinaus — es gab ja nur die eine Quelle.

„Nach Ansehen löschen" brauchte **kein** neues Feld auf der Leitung. `_bar`
reist seit jeher mit, die Empfangsseite liest es weiter, nur geschrieben
wurde es seit dem 02.09. nicht mehr. Ein Gerät mit einer älteren Fassung
versteht die Nachricht also ohne Umbau. Dass `EinmaligPolicy.ausPayload`
ausdrücklich **nicht** auf `_bar` schaut, bleibt richtig und wird hier zum
zweiten Mal wichtig: die beiden Zusagen sind verschieden, und aus der einen
darf nachträglich nicht die andere werden.

Zwei Zusagen an derselben Nachricht wären eine zu viel. Die einmalige trägt
deshalb weder Frist noch „nach Ansehen", und das steht nicht nur in der
Oberfläche, sondern auch im Provider: `burnAfterRead: burnAfterRead &&
!einmalig`.

## Die Chatliste

„Die Vorschau bzw. Anzeige der Nachrichten in der Chatliste soll vom Prinzip
her wie bei WhatsApp funktionieren." Im Bild daneben sind Uhrzeit und Ballon
rot eingekringelt.

Der Vorschautext war am 30.08.2026 ausgebaut worden, und der Grund von damals
gilt weiter: er lag als `lastMessagePreview` am Chat und damit **zweimal**
verschlüsselt auf der Platte, im Nachrichtenspeicher und noch einmal in
`chats.enc`. Zwei Kopien schützen nicht besser als eine, sie vergrössern nur
die Fläche.

Beides ist zu haben. Die Vorschau entsteht jetzt bei jedem Aufbau der Liste
aus dem Verlauf **im Speicher** — die Nachrichten aller Chats liegen seit
`initialize()` ohnehin dort. Gespeichert wird sie nirgends; das Feld am Chat
bleibt weg. Ein Schalter in den Einstellungen schaltet sie ab, und zwei
Nachrichtenarten zeigen ihren Inhalt nie: die einmalige (sie ist einmal zu
öffnen, nicht einmal zu lesen und einmal in der Liste) und die
passwortgeschützte, solange sie zu ist.

### Die Uhrzeit, und was daran falsch war

Dort stand eine eigene Rechnung mit `now.difference(time).inDays`. Um zehn
nach Mitternacht ist das für eine Nachricht von gestern 23:50 immer noch
null — in der Liste stand deshalb weiter `23:50`, als wäre sie von heute.
Eine Stufe höher derselbe Fehler: „Dienstag" blieb bis Mittwochabend stehen.
Gerechnet wird jetzt in **Kalendertagen**.

Und die Wörter waren fest verdrahtet englisch: `Yesterday`, `Mon`, `Tue` —
in einer App mit sieben Sprachen. Sie kommen jetzt aus der Übersetzung
beziehungsweise aus `intl`, die Uhrzeit über `MaterialLocalizations`, damit
sie der 24-Stunden-Einstellung des Geräts folgt.

### Die Reihenfolge

Sie hing allein daran, dass `_touchChat` den Chat an den Anfang der Liste
schob. Bei einer ankommenden Nachricht stimmte das. Es stimmte nicht bei den
anderen Aufrufern derselben Funktion: `deleteMessageForMe` und die
Ablaufmeldung der Gegenseite rufen sie, um die Uhrzeit auf die letzte
**verbliebene** Nachricht zurückzusetzen. Ein Chat von vorletzter Woche
sprang dadurch an die Spitze, weil darin etwas gelöscht wurde. Und lief eine
Nachricht ab, blieb der Chat oben, obwohl darunter nichts Neues mehr lag.
Sortiert wird jetzt nach der Uhrzeit, siehe `ChatOrder`.

**Nicht** geändert: solange etwas ungelesen ist, steht dort die Uhrzeit der
**ersten** neuen Nachricht und nicht der letzten. Das war eine eigene
Entscheidung vom 31.08. mit eigenem Anlass — die Uhrzeit wanderte sonst mit
jeder weiteren Nachricht mit, und wann etwas Neues anfing, war nicht mehr
abzulesen. WhatsApp macht es anders; wer es andersherum will, ändert
`Chat.displayTime` und `chat_list_time_test.dart`.

## Der Taschenrechner

„TR soll optional sein und in den Einstellungen jederzeit ein- und
ausgeschaltet werden können." Dazu: im Tutorial darauf hinweisen, die
Einrichtung muss übersprungen werden können, und später nachholbar sein.

Der Rechner war bis hierher keine Einstellung, sondern die Statik der App:
`_AppScreen.calculator` war der Startbildschirm, das Ziel jedes Sperrens und
der einzige Weg zum Messenger. Die Einrichtung verlangte zwei Codes, bevor
sie überhaupt weiterging.

Jetzt gibt es drei Zustände, und die Entscheidung darüber steht in
`ZugangsPolicy`:

| Rechner | Tresor oder Face ID | beim Sperren |
|---|---|---|
| an | egal | der Rechner |
| aus | ja | der Sperrbildschirm |
| aus | nein | gar nicht sperren |

Die dritte Zeile ist die unbequeme. Ein Bildschirm, den ein einziger Tipp
öffnet, ist keine Sperre — er behauptet nur eine. Dieselbe Ehrlichkeit hat
das Projekt beim Screenshot-Schutz schon einmal teuer gelernt: lieber sagen,
dass nichts schützt, als etwas vorzuspiegeln. Wer ohne Rechner Schutz will,
setzt ein Tresor-Passwort oder Face ID; beides steht im Tutorial und in den
Einstellungen.

Der Sperrbildschirm sagt offen, was er ist. Das ist der ganze Unterschied zum
Rechner, dessen Sinn war, nicht wie eine Sperre auszusehen. Wer ihn
abschaltet, hat sich gegen die Verkleidung entschieden, nicht gegen das
Schloss; eine halbe Tarnung wäre das Schlechteste von beidem.

### Die Vorgabe ist „an", und das ist keine Kleinigkeit

Jedes Gerät, das schon läuft, hat einen Geheimcode vergeben und erwartet den
Rechner. Sein Schlüsselbund kennt `krypta_cfg_calculator_lock` nicht. Die
Abfrage liest deshalb `!= 'false'` und nicht `== 'true'`: ein fehlender
Schlüssel heisst „an". Andersherum hätte das Update bei jedem bestehenden
Gerät die Zugangssperre abgeschaltet, ohne dass jemand danach gefragt hätte.

Dieselbe Falle hat das Projekt schon einmal getroffen, beim Push-Schalter —
siehe `StorageKeys.pushPrivacyMode`, wo der Wert bis heute verkehrt herum
gespeichert wird, weil ein neuer Schlüssel allen Nutzern ihre Einstellung
verdreht hätte. Der Test dazu steht in `zugangs_vorgaben_test.dart`.

### Codes und Türen

Beim Überspringen entstehen **keine** Codes, weder Geheim- noch Löschcode.
Ein Code ohne Rechner wäre ein Schlüssel ohne Tür, und beim späteren
Einschalten wird er ohnehin neu vergeben. Umgekehrt räumt das Abschalten
beide weg: ein Löschcode, zu dem es keine Eingabe mehr gibt, ist ein
Geheimnis ohne Tür — und ein Geheimcode wäre eine Zugangsmöglichkeit, von
der die Einstellungen behaupten, es gebe sie nicht mehr.

### Die Notfall-Löschung, und was auf dem Sperrbildschirm nicht steht

Im ersten Entwurf hatte der Sperrbildschirm oben rechts den Notfallknopf,
mit Rückfrage. Er ist wieder weg, und der Grund ist eine Regel, die diese App
bisher überall einhält: **vor dem Entsperren gibt es keine Zerstörung ohne
Wissen.** Am Rechner braucht sie den Löschcode; am Tresor-Bildschirm passiert
sie erst nach fünf falschen Passwörtern. Ein Knopf hätte jedem, der das
gesperrte Telefon in die Hand bekommt, mit zwei Tipps das Konto vernichtet —
samt der Meldung an alle Kontakte, dass es einen nicht mehr gibt.

Der Zwangsfall bleibt bedient, und zwar deniabler als ein Knopf: fünf falsche
Tresor-Passwörter löschen alles, und das sieht aus wie jemand, der sein
Passwort vergessen hat.

**Offen gesagt, was das kostet:** wer den Rechner abschaltet und *nur* Face ID
benutzt, hat vor dem Entsperren gar keinen Weg zur Löschung mehr — weder
Löschcode noch Fehlversuche. Für den Zwangsfall ist das die schwächste der
drei Aufstellungen. Wem der wichtig ist, der behält den Rechner oder setzt
zusätzlich ein Tresor-Passwort.

Nach dem Entsperren ist sie wie immer erreichbar: in den Einstellungen und
über den Notfallknopf in Chatliste und Chat.

## Prüfen

`flutter test`, 958 Tests waren es vorher. Neu dazu:

* `chatliste_vorschau_test.dart` — was in der Liste steht und was nie,
* `chatliste_zeit_test.dart` — der Tageswechsel um Mitternacht,
* `chatliste_reihenfolge_test.dart` — der alte Chat, der nicht mehr springt,
* `chatliste_kachel_test.dart` — die Kachel selbst, in zwei Sprachen,
* `nachrichtenregel_test.dart` — die vier Fälle und was aus ihnen folgt,
* `zugang_policy_test.dart` — wohin die App beim Sperren fällt,
* `zugangs_vorgaben_test.dart` — die Vorgaben für Geräte, die schon laufen.

Dazu erweitert: `chat_list_privacy_test.dart` um das, was auch bei
eingeschalteter Vorschau nie dasteht.
