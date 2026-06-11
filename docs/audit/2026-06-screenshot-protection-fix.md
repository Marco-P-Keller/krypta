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
