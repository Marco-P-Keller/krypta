# Der Messenger blitzte beim Zurückkehren auf

**Gemeldet:** 30.08.2026, Gerätetest. „Wenn man die App verlässt und wieder
reingeht kommt der Taschenrechner, aber ganz am Anfang blitzt manchmal kurz
das hinter dem Taschenrechner auf."

## Was da aufblitzte

Der Messenger. Genau das, was der Taschenrechner verdecken soll.

## Warum

Beim Verlassen der App legt `AppDelegate.applicationWillResignActive` eine
schwarze Ansicht über das Fenster. Sie ist als Schutz für die Vorschau im
App-Umschalter gedacht — sie leistet aber noch etwas Zweites, das leicht
übersehen wird: sie deckt auch die **Rückkehr** ab.

Die Umschaltung auf den Taschenrechner passiert in `app.dart` bei `paused`.
Ab diesem Zeitpunkt zeichnet Flutter nicht mehr. Das `setState` markiert den
Baum als schmutzig, aber das Bild dazu entsteht erst beim Aufwachen. Die
Flutter-Ebene hält solange weiter das **letzte abgelieferte Bild** — und das
ist der Messenger, denn ein Bild mit dem Taschenrechner gab es nie.

Beim Aufwachen war die Abdeckung also das Einzige, was ihn verdeckte. Und sie
fiel nach fester Zeit: einen Runloop-Durchlauf nach
`applicationDidBecomeActive`. Ob das Bild mit dem Taschenrechner bis dahin
stand, hat niemand geprüft.

**Warum „manchmal":** meistens stand es. Zwischen `willEnterForeground` und
`didBecomeActive` läuft die Umschalt-Animation, ein paar hundert Millisekunden,
in denen Flutter wieder zeichnet. Das reichte — solange der Dart-Faden frei
war.

Er war es nicht immer, und ausgerechnet der Aufwach-Pfad selbst hat ihn
blockiert: `didChangeAppLifecycleState(resumed)` rief als Erstes
`integrity.recheck()`. Dahinter steht `isDeviceCompromised()`, und das ist
`async` nur dem Namen nach — vor der Arbeit steht kein `await`. Vierzehn
`existsSync()` auf Systempfade und ein Schreibversuch nach
`/private/jailbreak_test`, den die Sandbox ablehnt, laufen **synchron auf dem
Faden, der das Bild bauen soll**. Genau in dem Moment, in dem die Abdeckung
fiel.

Zwei Fehler, die sich stapeln: einer macht das Leck möglich, der andere löst
es aus.

## Was jetzt gilt

**Die Abdeckung fällt auf Zuruf, nicht nach Zeit.** `PrivacyCover`
(`lib/services/platform/privacy_cover.dart`) meldet über den Kanal
`dismissPrivacyCover`, sobald wirklich ein Bild auf dem Schirm steht — zwei
Bilder nach dem Aufwachen, weil der erste Rückruf nur sagt, dass gebaut und
gemalt wurde, nicht dass der Rasterfaden abgeliefert hat.

**Beide `scheduleFrame()` sind Pflicht, nicht Vorsicht.** Ein Rückruf für
„nach dem Bild" plant kein Bild ein. Nach einem Blick ins Kontrollzentrum
kehrt die App zurück, ohne dass sich etwas geändert hat — kein Relock, nichts
schmutzig, also von sich aus auch kein Bild. Ohne das erzwungene Bild liefe
der Rückruf nie und die Abdeckung bliebe liegen, bis der Wachhund anschlägt.
Das ist beim Schreiben der Tests aufgefallen, nicht beim Nachdenken.

**Wachhund.** Bleibt der Zuruf aus — hängender oder abgestürzter Dart-Teil —,
nimmt die native Seite die Abdeckung nach drei Sekunden selbst ab. Eine
dauerhaft schwarze App ist der schlimmere Ausgang; diese Erfahrung steckt
schon in `removeSnapshotMasks()`.

**Nur solange die App vorn ist.** Ein spät eintreffender Zuruf dürfte sonst
eine Abdeckung abnehmen, die bereits für die nächste Pause liegt — und damit
den Messenger in die Vorschau setzen.

**Die Prüfungen laufen nach dem Bild.** `recheck()` und
`evictStaleCacheEntries()` hängen jetzt hinter dem Abnehmen der Abdeckung. Was
den Faden blockiert, hat auf dem Weg zum ersten Bild nichts zu suchen.

## Was offen bleibt

Android hat gar keine Abdeckung. `FLAG_SECURE` schwärzt dort die Vorschau im
Umschalter, aber die Rückkehr hat dieselbe Lücke: auch dort hält die Ebene das
letzte Bild von vor der Pause. Nicht gemeldet, nicht geprüft, nicht angefasst
— gehört auf die Liste, sobald ein Android-Gerät im Test ist.

`isDeviceCompromised()` ist weiterhin synchron. Es blockiert jetzt an einer
harmloseren Stelle, aber richtig wäre, die Dateisystem-Abfragen von der
Oberfläche wegzuschaffen.

## Prüfen

5.6 im Testprotokoll. 5 neue Fälle in `test/security/privacy_cover_test.dart`,
551 Tests grün.
