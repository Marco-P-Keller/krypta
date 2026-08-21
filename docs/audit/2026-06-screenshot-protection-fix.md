# Screenshot-Schutz — Fix (2026-06-11)

**Branch:** `fix/build61-delivery` (zusammen mit dem Build-61-Delivery-Fix → Build 62)
**Team:** Claude (Fable 5, Implementer) + Codex (Reviewer) — **Codex: APPROVED** nach 4 Runden
**Status:** Committed + gepusht. **Pflicht vor Release: iOS-Gerätetest (siehe Matrix unten).**
**Verifikation:** flutter analyze lib/ clean, 363 Tests grün / 1 vorbestehender Skip.

---

## Symptom

iOS: Beim Screenshot erschien ein Popup „Screenshot blockiert", **aber der Screenshot
wurde trotzdem aufgenommen** und landete in der Fotomediathek. Das Popup verschwand
zudem zu schnell (3 s).

## Root Cause

- **Android war korrekt.** `FLAG_SECURE` ist gesetzt → Screenshots/Recording/
  App-Switcher-Vorschau werden real geschwärzt.
- **iOS war Etikettenschwindel.** `enableSecureFlag` setzte nur ein Bool
  `isSecureFlagEnabled = true`, das **nichts** bewirkte. Es gab keinerlei Schutz.
  Der Screenshot wurde voll aufgenommen; die App meldete danach (via
  `userDidTakeScreenshotNotification`) fälschlich „blockiert".

## Plattform-Realität (wichtig!)

**iOS bietet keine API, einen Screenshot zu verhindern.** Der Auslöser
(Power+Lauter) lässt sich nicht abfangen — in keiner App. Der einzige etablierte
Schutz: den **Inhalt im Screenshot/Recording schwärzen** über die „secure canvas"
eines `isSecureTextEntry`-`UITextField`. Der Screenshot wird also weiterhin
ausgelöst, ist aber **leer/schwarz** — der Chat landet nicht in den Fotos.
Daniel hat sich bewusst für diesen (einzig möglichen) echten Schutz entschieden.

## Der Fix

**iOS (`ios/Runner/AppDelegate.swift`):**
- `installSecureMaskIfNeeded()`: bettet `window.layer` einmalig unter die secure
  canvas eines hidden `secureMaskField` → iOS schließt diese Layer aus
  Screenshots, Bildschirmaufnahmen und AirPlay-Mirroring aus; das Display rendert
  normal. Erzwingt die Canvas-Erzeugung (`isSecureTextEntry = true` + `layoutIfNeeded`)
  **vor** dem Lookup, **verifiziert** das Reparenting und schlägt sonst
  **fail-closed** fehl (kein falsches „geschützt").
- `setScreenshotMask(on:completion:)`: Main-Thread, re-verifiziert die Struktur nach
  jedem Toggle (UIKit kann Sublayer neu bauen) und repariert einmalig; meldet den
  **verifizierten** Aktiv-Status. Ein Disable ohne vorherigen Install baut die private
  Layer-Struktur nicht auf.
- `screenshotTaken()` sendet jetzt den **verifizierten** Maskenstatus
  (`isScreenshotMaskActive`), nicht die bloße Anforderung → die Warnung ist auch dann
  ehrlich, wenn der Trick auf einer künftigen iOS-Version bricht.
- Bestehendes App-Switcher-`blackView` unverändert als zusätzliche Absicherung.

**Dart:**
- `enableScreenshotProtection()` → `Future<bool>`: spiegelt den verifizierten
  Status (kein optimistisches „true" mehr).
- `_toggleScreenshotProtection` (Settings): Switch springt zurück, wenn das Masking
  nicht installiert werden konnte (ehrliche UI).
- Bewusste Produktentscheidung: bei Masking-Fehler **degradierter Weiterbetrieb**
  statt Messenger-Sperre (E2E ist die Kern-Garantie; Masking ist Zusatzschicht).

**Popup (`chat_screen.dart` + l10n DE/EN):**
- Dauer 3 s → **6 s**; neue Screenshots ersetzen die alte Toast statt zu stapeln.
- Ehrliche Texte: aktiv → „Screenshot erkannt – der Chat-Inhalt wurde dabei geschützt
  und nicht aufgenommen"; ungeschützt → „Achtung: Screenshot gemacht – der Inhalt war
  nicht geschützt". Kein „iOS blockt Screenshots"-Wording mehr.

## Codex-Review (4 Runden)

1. R1: Canvas-Install konnte still fail-open (P1); Resolve vor Masking (P1);
   unehrliche Detection (P2).
2. R2: nach Fixes — Dart-Returnwert nicht ausgewertet (P1); `secureMaskInstalled`
   stale nach Toggle (P1); Disable installierte unnötig (P2).
3. R3: nach Fixes — Settings-Toggle ignorierte `Future<bool>` (P2); app.dart-Kommentar
   veraltet (P3).
4. R4: **APPROVED.** Rest: Device-Test + heuristische Canvas-Auswahl (durch
   Verifikation abgesichert).

## PFLICHT vor Release — iOS-Gerätetest (Marco, echtes Gerät, kein Simulator)

Der Schutz nutzt undokumentiertes `isSecureTextEntry`-Layer-Verhalten. Vor dem
TestFlight-Release auf einem echten iPhone/iPad verifizieren, dass der **Flutter/Metal-
Content** (nicht nur UIKit-Overlays) im Capture wirklich schwarz ist:

- [ ] iPhone Hochformat: Screenshot im Chat → Bild ist schwarz/leer
- [ ] iPhone Querformat: dito
- [ ] iPad Split View / Resize: dito
- [ ] App-Switcher: Vorschau zeigt keinen Chat-Inhalt
- [ ] Bildschirmaufnahme (Control Center): Aufnahme zeigt schwarz
- [ ] AirPlay/QuickTime-Mirroring: gespiegeltes Bild schwarz
- [ ] enable → disable → enable (Chat öffnen → zurück zum Rechner → Chat öffnen),
      danach Screenshot erneut schwarz (Toggle-Robustheit)
- [ ] Screenshot **außerhalb** des Messengers (Rechner/Setup): normal sichtbar
      (Schutz nur im Chat aktiv) + Popup-Text ehrlich, 6 s sichtbar

Wenn ein Punkt fehlschlägt: nicht releasen, zurück an Claude/Codex.

## Rest-Risiko

`isSecureTextEntry`-Canvas-Trick = public API, aber undokumentiertes Rendering-
Verhalten. Apple lehnt das nicht ab (viele Apps nutzen es), aber ein künftiges iOS
könnte es brechen → dann **fail-open** (Screenshot wieder sichtbar), aber die
Post-Capture-Warnung bleibt ehrlich („nicht geschützt"). Android unberührt (echtes
FLAG_SECURE-Blocken).

---

## Regression in Build 68 (gemeldet 2026-08-21) — UI verschoben

**Symptom (TestFlight Build 68, echtes iPhone):** Die gesamte Oberflaeche ist nach
unten und nach rechts verschoben. Titel „Chats" und Zurueck-Pfeil stehen auf
Bildschirmmitte statt in der Navigationsleiste, darueber eine grosse schwarze
Flaeche; der FAB unten rechts wird am Bildschirmrand abgeschnitten.

**Root Cause:** Das Secure-Textfeld wurde per `centerXAnchor`/`centerYAnchor`
**zentriert** ins Window gehaengt, und `window.layer` wurde unter dessen Canvas
genestet. Ein Sublayer erbt das Koordinatensystem seiner Vorfahren — also wurde die
komplette App um den Ursprung des zentrierten Feldes verschoben (rund eine halbe
Bildschirmhoehe nach unten, eine halbe Breite nach rechts). Die schwarze Flaeche
oben ist der freigewordene Root-Layer.

Die alte Verifikation prueft nur `window.layer.superlayer === canvas`, also die
**Struktur**. Die **Geometrie** wurde nirgends geprueft — deshalb meldete der Code
„verifiziert, Schutz aktiv", waehrend die UI zerschossen war.

Zweiter, latenter Fehler derselben Methode: der Canvas wurde ueber
`sublayers?.last` gesucht. Ab **iOS 17** ist der Secure-Canvas der **erste**
Sublayer; `.last` greift dort einen anderen Layer ab (eigener Text-Inset-Ursprung,
kein OS-Schutz) — zusaetzlicher Versatz **und** keine wirksame Schwaerzung.

**Fix:**

1. Feld wird an **top-left** des Windows gepinnt, auf **volle Window-Groesse**
   (statt zentriert) — Ursprung (0,0), und Auto Layout haelt das ueber Rotation und
   iPad-Resize hinweg.
2. Canvas-Lookup probiert **`first` und `last`** und behaelt den Kandidaten, der die
   vollstaendige Verifikation besteht (kein hartkodierter Versionscheck).
3. Neue `applySecureMaskGeometry()`: rechnet den Ziel-Frame ueber
   `convert(_:to:)` in Canvas-Koordinaten um, damit das Window absolut auf
   denselben Pixeln landet wie ohne Maske. `window.bounds` als Groessenquelle,
   damit Rotation korrekt bleibt.
4. Neue `isWindowGeometryIntact()`: vergleicht die **absolute** Position/Groesse
   des Window-Layers gegen die Referenz vor dem Umhaengen (Toleranz 0,5 pt). Genau
   der Check, der in Build 68 fehlte. Install gilt nur als erfolgreich, wenn
   Struktur **und** Geometrie stimmen.
5. Neue `restoreOriginalParenting()` + Watchdog auf
   `orientationDidChangeNotification` und `applicationDidBecomeActive`: bei
   kaputter Struktur oder Geometrie wird die Maske **abgebaut** und das Window
   zurueckgehaengt. **Fail-visible statt fail-black** — lieber korrekte UI ohne
   Maskierung als eine verschobene/schwarze UI, die Schutz behauptet.
6. `isSecureMaskStructureIntact()` prueft jetzt zusaetzlich, dass der Feld-Layer
   noch unter dem urspruenglichen Superlayer haengt.
7. Der Geometrie-Check konvertiert das **komplette Rect** (`convert(_:from:)`) statt
   nur des Ursprungs — damit schlaegt er auch bei Scale/Rotation/Translation an, die
   irgendein Layer zwischen Window und Original-Parent setzt.
8. `scheduleSecureMaskRecheck()`: Nachkontrolle im naechsten Runloop **und** nach
   0,75 s. Die Verifikation direkt nach dem Install beweist nur den Zustand in
   diesem Moment; UIKit legt danach weitere Layout-Passes nach (Safe Area, Keyboard,
   Flutter-View-Setup).
9. **Genau ein Kandidat, kein Fallback:** iOS 17+ nimmt `first`, aeltere Releases
   `last` — und wenn der nicht verifiziert, wird abgebrochen. Grund (Codex R1+R2,
   P1): die Verifikation prueft Ancestry, Platzierung und Sichtbarkeit; das sind
   Eigenschaften, die ein beliebiger Layer erfuellt. Ein Fallback auf den anderen
   Sublayer haette aus einem ehrlichen "kein Schutz" ein falsches "geschuetzt"
   gemacht (`isScreenshotMaskActive = true` ohne echte Capture-Ausnahme) — genau
   in dem Moment, in dem der erwartete Canvas kurzzeitig durchfaellt. Fail closed
   ist hier richtig: UI korrekt, Maskierung aus, Warnung ehrlich.
10. `isAncestorChainRenderable()`: kein Layer zwischen Window und Original-Parent
    darf `isHidden`, teiltransparent sein oder per `masksToBounds` das Window
    beschneiden. Geometrie allein reicht nicht — ein falscher Layer kann das Rect
    korrekt abbilden und den Inhalt trotzdem wegclippen.
11. **Jeder Install startet aus einem sichtbaren Zustand** (Codex R1, P1): haengt
    `window.layer` nicht an seinem Original-Parent, wird es zuerst
    zurueckgehaengt. Und ein Reinstall nach kaputter Struktur ruft vorher
    `restoreOriginalParenting()` — sonst konnte ein frueher Return (keine
    Kandidaten, Canvas weg) das Window unter einem abgehaengten Canvas
    stranden lassen: schwarzer Screen.
12. **Scene-Resize-Hook statt Orientierungs-Notification** (Codex R1, P1):
    `orientationDidChangeNotification` feuert bei iPad Split View und Stage
    Manager nicht. Stattdessen `SecureMaskField.layoutSubviews` — das Feld ist
    ans Window gepinnt, also meldet UIKit dort jede Groessenaenderung der Scene.
    Repair laeuft coalesced im naechsten Runloop (`isRepairingMask`).
13. **Delete-Code ueberlebt Dispose** (Codex R1, P2): der pauschale
    `mounted`-Guard haette einen bereits eingegebenen Notfall-Wipe verschluckt,
    wenn die Argon2id-Pruefung nach dem Dispose fertig wird. Jetzt werden
    `MessengerProvider` und `EmergencyWipeService` **vor** dem `await` gegriffen,
    der Wipe laeuft unabhaengig vom Mounted-State, und nur die UI-Teile
    (`_logic.clear()`, `widget.onDeleteCode()`) sind gegated. `delete` steht
    im Switch bewusst vor `secret` — das spiegelt die Prioritaet des Detectors.
14. **Kill-Switch** `maskContentInCaptures` (oben in `AppDelegate`): auf `false`
   gesetzt fasst die App den Layer-Baum des Windows nie an — Screenshots zeigen
   dann wieder echten Inhalt (die Warnung sagt das ehrlich), aber ein UI-Versatz
   ist physisch ausgeschlossen. Umzulegen, falls ein Geraete-Build den Build-68-
   Fehler nochmal zeigt.

**Konsequenz fuer den Gerätetest:** Die Checkliste oben bleibt Pflicht, plus neu:

- [ ] App-Start: UI sitzt korrekt im Bildschirm (kein Versatz, keine schwarze
      Flaeche oben, FAB unten rechts vollstaendig sichtbar)
- [ ] Nach Rotation hoch/quer/hoch: UI weiterhin korrekt positioniert
- [ ] Nach App-Switch (Home → zurueck): UI weiterhin korrekt positioniert
- [ ] Wenn die Maskierung auf dem Geraet **nicht** installierbar ist: App laeuft
      normal weiter, Settings-Toggle springt zurueck, Screenshot-Warnung sagt
      ehrlich „nicht geschuetzt"
