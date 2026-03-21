# iOS Archive / App Store Connect – Code-Sign-Fehler

## Fehler

`Failed to code sign binary … objective_c.framework: resource fork, Finder information, or similar detritus not allowed`

## Warum passiert das?

Apples **codesign** akzeptiert **keine Extended Attributes** (xattr) auf Binaries/Frameworks. Diese Metadaten legt macOS oft an, wenn:

- das Projekt oder der `build/`-Ordner auf **iCloud Drive** liegt (z. B. **Schreibtisch & Dokumente** in der iCloud),
- du Dateien aus dem **Downloads**-Ordner kopierst,
- der **Finder** oder die **Datei-App** „Zusatzinfos“ anhängt.

Flutter baut Native-Assets (z. B. **`objective_c`**) unter `build/native_assets/ios/…` und signiert sie – dort schlägt es fehl, sobald xattrs dran sind.

## Was wir im Projekt gemacht haben

1. **`ios/flutter_codesign_prep.sh`**: **`COPYFILE_DISABLE=1`**, dann **`xattr -cr`** auf **`build/native_assets/ios/`** (wie im manuellen Schnellfix), danach auf **`build/native_assets/`**, plus relevante Ordner in **`~/.pub-cache/hosted`**. Optional: in der Xcode-Scheme-Umgebung **`STRIP_PROJECT_XATTRS=1`** setzen für ein projektweites `xattr -cr` (nur bei Bedarf).
2. **Run Script** und **Thin Binary** rufen das Skript **vor** `xcode_backend.sh` auf; bei **Exit-Code ≠ 0** wird **noch einmal** bereinigt und **`build`** bzw. **`embed_and_thin`** **einmal wiederholt** (hilft, wenn beim ersten Lauf xattrs auf dem frischen Framework landen).

## Schnellfix (Terminal)

Genau der Ordner, in dem Flutter `objective_c.framework` ablegt – **rekursiv alle xattrs entfernen**, dann erneut bauen/archivieren:

```bash
xattr -cr /Users/marcokeller/Desktop/kryptaecc/kryptaapp/build/native_assets/ios/
```

(Pfad an dein Projekt anpassen, falls es woanders liegt.)

**Ursache (wie du es beschrieben hast):** Netzlaufwerk, ZIP, Finder-Kopien, iCloud „Schreibtisch & Dokumente“ – macOS hängt unsichtbare Metadaten an; **`codesign` lehnt die ab** mit *resource fork, Finder information, or similar detritus not allowed*.

## Wenn es trotzdem scheitert

1. **Projekt nicht in iCloud legen**  
   Lege das Repo z. B. nach `~/Developer/kryptaapp` (ohne iCloud-Sync für diesen Ordner).

2. **Vor dem Archiv manuell bereinigen** (entspricht dem Schnellfix + Pub-Cache)

   ```bash
   cd /pfad/zu/kryptaapp
   xattr -cr build/native_assets/ios/ 2>/dev/null || true
   ./scripts/strip_xattrs_ios.sh
   flutter clean
   flutter pub get
   cd ios && pod install && cd ..
   ```

3. **Archiv über Flutter (empfohlen für konsistente Builds)**

   ```bash
   export COPYFILE_DISABLE=1
   flutter build ipa
   ```

4. **Optional: ganzes Projektverzeichnis** (hartnäckige Fälle)

   ```bash
   xattr -cr /pfad/zu/kryptaapp/
   ```

   Oder: `STRIP_PROJECT=1 ./scripts/strip_xattrs_ios.sh`  
   Danach bei Pod-Problemen: `cd ios && pod install`.

5. **Automatisch im Xcode-Build:** `ios/flutter_codesign_prep.sh` entfernt xattrs u. a. unter `build/native_assets/ios/` **vor** jedem `build` / `embed_and_thin`. Schlägt der erste Lauf fehl, wird **einmal** erneut bereinigt und gebaut (Retry).

## Kurzfassung

**Ursache:** Extended Attributes durch iCloud/Finder.  
**Lösung:** Projekt lokal ohne iCloud-Sync + eingebaute Xcode-Skripte + bei Bedarf `./scripts/strip_xattrs_ios.sh` vor dem Archiv.
