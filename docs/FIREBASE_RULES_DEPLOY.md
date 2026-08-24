# Firestore Rules veröffentlichen – ohne eigenen Rechner

`.github/workflows/firebase-rules.yml` lädt `firebase/firestore.rules` in das
Firebase-Projekt **kryptaecc**. Alles Nötige lässt sich im Browser erledigen;
weder Firebase CLI noch ein lokaler Login werden gebraucht.

Der Workflow startet:

- **manuell** über Actions → Firebase Rules → Run workflow, und
- **automatisch**, sobald sich `firebase/firestore.rules` auf `main` ändert.

---

## 1. Dienstkonto anlegen

`firebase login:ci` scheidet aus – das setzt einen lokalen Browser plus CLI
voraus. Stattdessen ein Dienstkonto, das Google ohnehin als den Weg für CI
empfiehlt:

1. [Google Cloud Console → IAM & Verwaltung → Dienstkonten](https://console.cloud.google.com/iam-admin/serviceaccounts)
   öffnen, oben das Projekt **kryptaecc** auswählen
2. **Dienstkonto erstellen**, Name z. B. `github-actions-rules`
3. Rollen zuweisen:
   - **Firebase Rules Admin** (`roles/firebaserules.admin`)
   - **Service Usage Consumer** (`roles/serviceusage.serviceUsageConsumer`)

   Wer es einfacher mag, nimmt stattdessen die eine Rolle **Firebase Admin** –
   das sind allerdings deutlich mehr Rechte als für diesen Zweck nötig.
4. Auf das angelegte Dienstkonto klicken → Tab **Schlüssel** →
   **Schlüssel hinzufügen → Neuen Schlüssel erstellen → JSON** → herunterladen

## 2. Secret setzen

Repo → **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Inhalt |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | kompletter Inhalt der heruntergeladenen JSON-Datei |

Base64-kodiert wird ebenfalls akzeptiert; der Workflow erkennt beides. Er
prüft vor dem Deploy, ob `client_email`, `private_key` und `project_id`
vorhanden sind, und bricht sonst mit einer klaren Meldung ab.

### Optionale Variablen

Reiter **Variables**, nur bei Abweichung vom Standard nötig:

| Variable | Default | Zweck |
|---|---|---|
| `FIREBASE_PROJECT_ID` | `kryptaecc` | Ziel-Projekt |
| `FIREBASE_TOOLS_VERSION` | `latest` | Version der Firebase CLI, z. B. auf eine feste Version pinnen |

## 3. Deployen

Actions → **Firebase Rules** → **Run workflow**. Oder einfach die Regeln auf
`main` ändern – dann läuft er von selbst.

## 4. Was bewusst *nicht* mitdeployt wird

Der Workflow ruft `firebase deploy --only firestore:rules` auf, nicht
`firebase deploy` pauschal. Zwei Gründe:

- **Functions bleiben außen vor.** Sie gehören in einen eigenen, bewusst
  ausgelösten Schritt: ein Functions-Deploy legt Firestore-Trigger und
  Scheduler an, braucht mehrere Minuten und zusätzliche Rollen, die dieses
  Dienstkonto nicht hat. Siehe `docs/FIREBASE_FUNCTIONS.md`.
  (Bis `2cb14c9` stand hier, der Deploy scheitere an der abgekündigten
  Runtime `nodejs18` – das galt, solange `firebase.json` darauf stand. Es
  steht seither auf `nodejs22`, ein Functions-Deploy ist also möglich.)
- **Indexes bleiben außen vor.** `firebase/firestore.indexes.json` ist leer
  (`"indexes": []`). Das erspart dem Dienstkonto die Rolle
  *Cloud Datastore Index Admin*.

Sollen Functions oder Indexes später mit deployt werden, brauchen sie einen
eigenen Schritt samt passender Rollen – und die Functions vorher eine
unterstützte Node-Runtime.

## 5. Prüfen, ob es gewirkt hat

[Firebase Console](https://console.firebase.google.com/project/kryptaecc/firestore/rules)
→ Firestore Database → Rules. Dort steht die aktive Fassung samt Zeitstempel
der Veröffentlichung.

Besonders zu kontrollieren sind die beiden Blöcke, die das Audit 2026-05
nachgetragen hat (H1-Network) – ohne sie greift der Catch-all und Sealed
Sender sowie die Key-Transparency-Schicht sind komplett blockiert:

- `match /deliveryTokens/{userId}`
- `match /keyCommitments/{userId}/log/{epochId}`

Fehlen sie in der Konsole, lief der Deploy noch nicht.

## 6. Was der Deploy prüft – und was nicht

Firebase kompiliert die Regeln serverseitig und lehnt sie bei Syntaxfehlern
ab; ein kaputtes Regelwerk geht also nicht versehentlich live. **Nicht**
geprüft wird, ob die Regeln inhaltlich das Richtige erlauben und verbieten.
Dafür bräuchte es Emulator-Tests mit `@firebase/rules-unit-testing`, die
etwa nachweisen, dass ein Fremder keine fremde Inbox lesen kann.

Zum gefahrlosen Ausprobieren einzelner Regeln eignet sich der
**Rules Playground** in der Firebase Console: dort lassen sich Lese- und
Schreibzugriffe gegen die aktive Fassung simulieren, ohne etwas zu ändern.

## 7. Troubleshooting

| Fehler | Ursache / Lösung |
|---|---|
| `Secret FIREBASE_SERVICE_ACCOUNT fehlt` | Schritt 2 nachholen |
| `Dienstkonto-JSON ohne Feld …` | unvollständiger Secret-Inhalt – JSON komplett einfügen, inklusive der geschweiften Klammern |
| `Permission denied on resource project kryptaecc` | Rollen aus Schritt 1 fehlen, oder das Dienstkonto gehört zu einem anderen Projekt |
| `HTTP Error: 403, Firebase Rules API has not been used` | Firebase Rules API im Projekt aktivieren (Link steht in der Fehlermeldung) |
| `Compilation error in firestore.rules` | Syntaxfehler in den Regeln – Zeilennummer steht in der Ausgabe, es wurde nichts veröffentlicht |

## 8. Sicherheitshinweise

- Die Dienstkonto-Datei wird am Ende jedes Runs vom Runner gelöscht, auch
  wenn der Deploy fehlschlägt (`if: always()`).
- Der Workflow läuft mit `permissions: contents: read`.
- Der Schlüssel ist langlebig und gilt für das gesamte Projekt. Bei Verdacht
  auf Kompromittierung: in der Cloud Console beim Dienstkonto löschen und
  einen neuen erzeugen.
- Wer ganz ohne dauerhaften Schlüssel auskommen will, kann stattdessen
  Workload Identity Federation einrichten – aufwendiger, aber es liegt dann
  kein Secret im Repository.
