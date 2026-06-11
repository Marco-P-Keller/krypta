# Build-61 Zustellbug — Root Cause & Fix (2026-06-11)

**Branch:** `fix/build61-delivery` (= Build-61-Commit `d713eb5` + Fix), auch auf `audit/2026-05` gepusht
**Team:** Claude (Fable 5, Implementer) + Codex (Reviewer) — **Codex: APPROVED** nach 4 Runden
**Status:** Committed + gepusht (Daniel hat auf Einzel-Review verzichtet, Codex-Gate bestanden). Version: 1.0.0+62.
**Verifikation:** 363/363 Tests grün (12 neue), 1 vorbestehender Skip, `flutter analyze lib/` clean.

---

## Symptom

Build 61 (TestFlight): Nachrichten-Senden schlägt fehl — Nachrichten kommen beim
Empfänger nie an („kann nicht zugestellt werden"). Betroffen: Daniel + Marco.

## Root Cause

**Der X3DH-Handshake war für JEDE neue Session inkonsistent — in allen Pfaden:**

1. **Bundle-Pfad (Normalfall ab Build 61):** Der H2-Network-Fix (audit 2026-05)
   ließ `publishPreKeyBundle` erstmals durch die Firestore-Rules (`updatedAt`).
   `buildBundle` legte **immer** einen One-Time-Prekey bei → Sender rechnete
   **4-DH**, aber der Empfänger konnte nur **3-DH**: kein `opkId` auf der
   Leitung (Session-Header = nur `ek`), kein Caller übergab je
   `oneTimePreKeyPrivate`, OTP-Konsum war toter Code. → Shared Secrets
   verschieden → jede erste Nachricht MAC-failt → Receive-Pfad **löscht sie
   still vom Server**, kein Ack, Sender bleibt auf „Gesendet".
2. **Fallback-Pfad (kein Bundle):** Sender rechnete alle DHs gegen den
   **Identity-Key** des Empfängers; der Empfänger überschrieb aber
   bedingungslos mit seinem **Signed Prekey**, sobald vorhanden (= immer) →
   DH1- + Ratchet-Key-Mismatch.
3. **Kein `spkId` auf der Leitung:** nach SPK-Rotation (7 Tage / 48 h Overlap)
   konnte der Empfänger den passenden Key nicht finden (`findSignedPreKey`
   existierte ungenutzt).
4. **Re-Handshake-Sackgasse:** Empfänger mit altem Session-State ignorierte
   `ek`-Header für immer (im Code dokumentiert) — einseitige Resets
   (Reinstall, Key-Change, Chat-Delete) brickten Chats dauerhaft.

Eure alten Chats liefen auf Sessions aus der Zeit **vor** dem April-Hardening;
sobald irgendein Ereignis einen neuen Handshake erzwang, war der Chat tot.
Build 61 hat das nicht eingeführt, aber flächendeckend aktiviert (Bundles mit
OTP existierten erstmals wirklich auf dem Server).

Serverseitig: `consumeOneTimePreKey` (Sender schreibt das Empfänger-Dokument,
Rule ist owner-only, `updatedAt` fehlte) war **immer** permission-denied.

## Der Fix

| # | Änderung | Datei |
|---|----------|-------|
| F1 | Bundle publiziert **keinen OTP** mehr (lokaler Pool bleibt für künftige echte OTP-Implementierung) | `prekey_manager.dart` |
| F2 | Sender immer **3-DH**; Bundle-OPK wird ignoriert (deckt alte, noch opk-tragende Server-Bundles); toter DH4-Empfängerzweig entfernt | `session_handshake_service.dart` |
| F3 | Neue pure Key-Auswahl `resolveInboundHandshakeKeys`: `ek2` ⇒ Identity-Mirror (Fallback), sonst SPK per `spkId` (Rotation/Overlap), sonst current SPK, sonst Identity | `session_handshake_service.dart` |
| F4 | Session-Header trägt `{ek, spkId}` (Payload bleibt ≤ 10 Keys); Empfänger-Init aufgespalten in pure Ableitung + persistierenden Wrapper (C5-Lineage erhalten) | `messenger_provider.dart` |
| F5 | **Session-Heal:** Decrypt-Fehler + `ek`-Header ⇒ tentative frische Inbound-Session; Commit **erst nach voller Akzeptanz** (Sealed-Sender + C4/C5-Gate bzw. Ctrl-HMAC+Counter). Pending per `(chatId\|messageId)`, Freshness-Recheck atomar am Commit-Punkt, accepted-`ek`-Replay-Guard (FIFO 100, persistiert) | `messenger_provider.dart` |
| F6 | `consumeOneTimePreKey` entfernt (war immer permission-denied) | `firestore_service.dart` |

Neue Tests: `test/security/x3dh_handshake_consistency_test.dart` (12 Tests —
Bundle-mit/ohne-OTP-Roundtrip, Fallback-Mirror positiv/negativ, Key-Auswahl
5 Fälle, Bundle-ohne-OPK, Heal-Szenario).

## Codex-Review-Verlauf (4 Runden)

1. R1: Heal committete vor den Gates (P1) → transaktional umgebaut.
2. R2: Pending überlebte Exception-Pfade (P2) → Discard in allen Catches; `_ctrl` typsicher.
3. R3: Pending nur per chatId gekeyt — Concurrency (P2) → Composite-Key `(chatId|messageId)`.
4. R4: TOCTOU bei parallelen Heals derselben Replay-Nachricht (P1) → Freshness-Recheck synchron am Commit-Punkt. **APPROVED.**

Bewusster Trade-off (Codex-bestätigt): ohne OPK hat die erste Nachricht einer
Session Standard-3-DH-Forward-Secrecy (wie Signal ohne OTPs) — bis OTP
end-to-end existiert (braucht `opkId` im Header + Empfänger-Konsum + owner-
seitige Server-Löschung).

## Feld-Recovery (nach Build 62 auf beiden Geräten)

1. **Eine** Seite löscht den kaputten Chat und schreibt neu.
2. Die Gegenseite heilt automatisch (F5) — kein beidseitiges Löschen nötig.

## Marco-Actions (Daniel hat keine IAM-Rechte auf `kryptaecc`!)

- `firebase deploy --only firestore:rules` (und bei Gelegenheit `functions`)
  aus dem Repo-Stand — falls die deployten Rules älter sind als die Repo-Rules,
  ist `/prekeys` sonst gar nicht lesbar (permission-denied ⇒ rote Sendefehler).
  Von hier aus weder lesbar noch deploybar (403 IAM_PERMISSION_DENIED).

## Follow-ups (nicht in diesem Fix)

- Provider-Test-Harness mit `fake_cloud_firestore` für E2E-Replay-Tests des
  Heal-Pfads (Codex-Wunsch; Ordering ist aktuell per Konstruktion erzwungen).
- Session-Header (`ek`, `ek2`, `spkId`) in die AAD aufnehmen (Wire-Change,
  beide Seiten) — derzeit nicht MAC-gedeckt; Heal toleriert das (Decrypt-Erfolg
  ist das Gate), aber sauberer wäre Authentifizierung.
- Echte OTP-Unterstützung end-to-end.
- Inbox-Listener-Error-Recovery (bekannter Punkt aus dem April-Sweep).
