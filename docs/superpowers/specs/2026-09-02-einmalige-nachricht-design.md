# Einmalige Nachricht

Stand 02.09.2026. Ersetzt den Selbstloeschtimer einzelner Nachrichten und
Burn after read durch eine Funktion.

## Ziel

Der Absender kann festlegen, dass eine Nachricht **nur einmal geoeffnet**
werden darf. Der Empfaenger sieht zunaechst nur eine geschuetzte Blase mit
der Schaltflaeche **Oeffnen**. Nach einer Bestaetigung erscheint der Text in
einer eigenen Ansicht. Danach ist die Nachricht dauerhaft fort.

## Abgrenzung

**Betroffen:** der Loeschtimer fuer eine **einzelne** Nachricht, und
**Burn after read**. Beide fallen als Sendeoption weg.

**Nicht betroffen:** der Loeschtimer fuer den **ganzen Chat**. Er bleibt
unveraendert, samt Systemmeldung bei einem Fristwechsel und dem rueckwirkenden
Verhalten. Ebenso unberuehrt bleibt die Passwortnachricht.

## Entschiedene Fragen

Diese Punkte waren offen und sind von Daniel am 02.09.2026 entschieden.

### E1 Burn after read wird mitersetzt

Nicht nur der Timer. Burn after read gibt dasselbe Versprechen ab wie die
neue Funktion, nur schwaecher: kein Hinweis vorher, der Inhalt steht offen im
Verlauf, und der Zeitpunkt des Verschwindens ist fuer den Empfaenger nicht
absehbar.

**Folge:** eine einzelne Nachricht hat danach genau zwei Sonderoptionen,
Einmalige Nachricht und Passwort. Vorher waren es sechs Eintraege fuer drei
Konzepte.

### E2 Verbraucht wird beim Bestaetigen, nicht beim Schliessen

Mit dem Tippen auf **Bestaetigen und oeffnen** ist die Nachricht von der
Platte fort. Die Ansicht zeigt danach nur noch, was im Arbeitsspeicher liegt.

**Begruendung:** nur so haelt die Zusage auch dann, wenn die App hart
abgeschossen wird oder der Akku leer ist. Wuerde erst beim Schliessen
geloescht, koennte man die App im richtigen Moment abschiessen und die
Nachricht bliebe erneut oeffenbar.

**Preis:** kommt genau in diesem Moment ein Anruf herein, ist die Nachricht
fort, gelesen oder nicht. Der Bestaetigungsdialog sagt das vorher an.

### E3 Beim Absender verschwindet sie ebenfalls

Sobald der Empfaenger bestaetigt hat, geht eine Ablaufmeldung an den Absender
und die Nachricht wird auch dort entfernt. Das ist die heutige Regel von
Burn after read und bleibt so. Ein Vermerk „geoeffnet" wird bewusst nicht
hinterlassen.

### E4 Bestand laeuft aus, statt zu brechen

Auf den Geraeten liegen Nachrichten mit Einzeltimer und mit Burn after read,
denen etwas zugesagt wurde. Wird die Logik ersatzlos entfernt, bleiben sie
fuer immer stehen und brechen damit ihr eigenes Versprechen.

**Deshalb:** **Senden** geht nur noch mit der neuen Funktion. **Lesen und
Ablaufen** der alten bleibt erhalten. Ein aelterer Build, der `_bar` oder eine
Einzelfrist schickt, wird weiterhin korrekt behandelt.

## Ablauf

### Absender

1. Tippt im Sendemenue auf **Einmalige Nachricht**. Die Markierung gilt fuer
   die naechste Nachricht, wie heute bei Burn after read.
2. Schreibt und sendet.
3. Sieht seinen eigenen Text normal, solange nicht geoeffnet wurde.

### Empfaenger

1. Sieht eine geschuetzte Blase. Kein Inhalt, nur die Schaltflaeche
   **Oeffnen**.
2. Tippt **Oeffnen**. Es erscheint die Rueckfrage:

   > Diese Nachricht kann nur einmal geoeffnet werden. Sobald du sie
   > schliesst, wird sie dauerhaft entfernt. Das gilt auch, wenn etwas
   > dazwischenkommt.

   Schaltflaechen **Abbrechen** und **Bestaetigen und oeffnen**.

   **Der dritte Satz ist eine Ergaenzung von mir, nicht aus Daniels Vorgabe.**
   Ohne ihn steht im Dialog nur „sobald du sie schliesst", waehrend nach E2
   auch ein Anruf oder ein Absturz die Nachricht verbraucht. Der Dialog wuerde
   sonst etwas anderes zusagen als die Funktion tut. Daniel kann den Satz
   streichen, dann muss E2 auf „beim Schliessen" zurueck.
3. Nach **Bestaetigen und oeffnen** geschieht in dieser Reihenfolge:
   a) die Nachricht wird aus dem Speicher auf der Platte entfernt,
   b) die Ablaufmeldung geht an den Absender,
   c) die Ansicht oeffnet sich mit dem Text aus dem Arbeitsspeicher.
4. Die Ansicht bleibt offen, solange er sie offen laesst. Der Text ist
   vollstaendig lesbar.
5. Schliessen, App-Wechsel, Absturz und leerer Akku fuehren zum selben
   Ergebnis: die Nachricht ist fort und im Verlauf nicht mehr sichtbar.

### Abbrechen

Tippt der Empfaenger im Bestaetigungsdialog auf **Abbrechen**, bleibt alles
unveraendert. Die Nachricht kann spaeter erneut geoeffnet werden.

## Datenmodell

### Neu

`Message.einmalig` (bool, Standard `false`). Gespeichert als `einmalig`,
auf der Leitung als `_once` im inneren Payload.

### Bleibt, aber nur noch lesend

`Message.burnAfterRead` wird nicht mehr gesetzt, aber weiter deserialisiert
und beim Verlassen des Chats weiter ausgewertet. Grund siehe E4. Das Feld
kann entfernt werden, sobald keine Geraete mit aelteren Builds mehr im Umlauf
sind; das ist keine Aufgabe dieser Aenderung.

**`_bar` bleibt `burnAfterRead` und wird NICHT zu `einmalig`.** Ein aelterer
Absender hat seiner Gegenseite das alte Verhalten zugesagt, Inhalt sichtbar
und weg beim Verlassen. Es waere falsch, daraus nachtraeglich eine Nachricht
mit Tor und Bestaetigung zu machen. Die beiden Wege laufen nebeneinander, bis
der Bestand durch ist.

### Bleibt unveraendert

`Message.selfDestructDuration` und `Message.selfDestructFromChat` tragen
weiterhin den **Chat-Timer**. Neue Nachrichten setzen die Dauer nur noch aus
der Chat-Frist, `selfDestructFromChat` ist dann immer `true`. Bestehende
Nachrichten mit `selfDestructFromChat == false` laufen nach der alten Regel
ab, ab Zustellung.

## Regeln

Die Entscheidungen stehen in `lib/features/messenger/logic/einmalig_policy.dart`
als reine Funktionen, weil der Provider Firebase braucht und im Test nicht
laeuft. Das ist die Hausregel dieses Projekts, siehe `UnreadPolicy`,
`BlockPolicy`, `VerificationPolicy`.

    abstract final class EinmaligPolicy {
      /// Ob die Blase den Inhalt verbergen und stattdessen „Oeffnen" zeigen
      /// muss. Nur beim Empfaenger, und nur solange nicht geoeffnet wurde.
      static bool verbergen({
        required bool einmalig,
        required String senderId,
        required String? eigeneId,
      });

      /// Ob eine eintreffende Nachricht als einmalig gilt.
      /// Liest ausschliesslich `_once`.
      static bool ausPayload(Map<String, dynamic> payload);
    }

`verbergen` ist beim **Absender** immer `false`. Er sieht seinen eigenen Text,
bis geoeffnet wurde.

## Oberflaeche

### Sendemenue im Chat

Die Liste der Einzelfristen und der Eintrag Burn after read entfallen. Es
bleiben **Einmalige Nachricht** und **Passwort**, beide wie bisher
gegenseitig ausschliessend zur Chat-Frist der Nachricht.

Die Markierung ueber der Eingabezeile zeigt „Einmalige Nachricht" statt der
bisherigen Frist.

### Blase beim Empfaenger

Der geschuetzte Zustand nutzt die Darstellung der Passwortnachricht als
Vorbild: Symbol, kurzer Hinweis, Schaltflaeche. Beschriftung **Oeffnen**.

### Bestaetigungsdialog

Ein `AlertDialog` mit `scrollable: true`, wie seit dem 02.09. fuer alle
Dialoge mit Inhalt verlangt. Titel, der Warntext aus dem Ablauf, und die
beiden Schaltflaechen.

Der Dialog nennt zusaetzlich die Grenze der Funktion, siehe Abschnitt
Grenzen.

### Ansicht

Eine eigene Route, kein Blatt. Vollflaechig, der Text zentriert und
scrollbar, dazu ein deutlicher Schliessen-Knopf. Kein Kopieren, wie im
uebrigen Chat auch.

## Was wegfaellt

- Die Fristauswahl fuer eine einzelne Nachricht im Sendemenue.
- Der Eintrag Burn after read im Sendemenue.
- Die **Restzeit unter der Blase** samt eigenem Sekundentakt. Sie gehoerte
  ausschliesslich zum Einzeltimer; beim Chat-Timer stand dort nie etwas.
- Die Tutorialzeile zur Restzeit (`tutTRemaining`, `tutDRemaining`).
- Die Tutorialzeile zu Burn after read wird zur Zeile fuer die einmalige
  Nachricht.

## Grenzen, die benannt werden muessen

Eine einmalige Nachricht schuetzt **nicht** gegen einen Screenshot und nicht
gegen ein zweites Telefon, das danebenliegt. Der Screenshot-Hinweis meldet
den Screenshot der Gegenseite, verhindern kann die App ihn nicht.

**Festlegung: es steht im Bestaetigungsdialog**, nicht nur im Tutorial. Der
Dialog ist der Moment der Entscheidung; wer dort liest, entscheidet mit dem
Wissen. Als eigene, kleinere Zeile unter dem Warntext:

> Ein Screenshot laesst sich nicht verhindern. Du erfaehrst davon.

Eine Funktion, die mehr verspricht als sie haelt, ist schlechter als eine
ehrliche; an genau dieser Stelle ist der fruehere Screenshot-Schutz
gescheitert.

## Tests

Zuerst geschrieben, wie im Projekt ueblich.

**`einmalig_policy_test.dart`**
- verbergen: beim Empfaenger wahr, beim Absender falsch.
- ausPayload: `_once` wird erkannt; `_bar` eines aelteren Absenders ebenso;
  fehlt beides, ist die Nachricht gewoehnlich.

**`message_model`**
- `einmalig` ueberlebt Speichern und Laden.
- Ein Bestandsdatensatz ohne das Feld laedt als `false`.

**Widget**
- Die Blase zeigt beim Empfaenger keinen Inhalt, sondern die Schaltflaeche.
- Beim Absender zeigt sie den Text.
- Der Bestaetigungsdialog haelt auf dem kleinsten Geraet bei maximaler
  Systemschrift, in allen sieben Sprachen. Dieselbe Pruefung wie fuer die
  uebrigen Dialoge seit dem 02.09.

**Lokalisierung**
- Alle neuen Texte in sieben Sprachen, nicht leer, ohne Gedankenstriche.

## Testprotokoll

Betroffen sind die Punkte **1.27**, **3.9**, **5.14** und **3.11**. Alle vier
beschreiben Verhalten, das es danach nicht mehr gibt, und werden umgeschrieben
statt geloescht: ihre Haekchen haengen an den `data-id`. Dazu kommt ein neuer
Punkt fuer die einmalige Nachricht.

## Bewusst nicht Teil dieser Aenderung

- Das Entfernen von `burnAfterRead` aus dem Modell. Siehe E4.
- Ein Vermerk „geoeffnet" beim Absender. Siehe E3.
- Jede Aenderung am Chat-Timer.
