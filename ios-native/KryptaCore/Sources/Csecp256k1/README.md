# libsecp256k1 (vendored)

Die Kurve von Bitcoin, aus [bitcoin-core/secp256k1](https://github.com/bitcoin-core/secp256k1),
derselben Bibliothek, mit der Bitcoin Core signiert und prüft.

- Version: **v0.7.1**, Commit `1a53f4961f337b4d166c25fce72ef0dc88806618`
- `include/` und `src/` sind **unverändert** kopiert, nur die Dateien, die
  für ECDSA ohne Zusatzmodule gebraucht werden (keine Schnorr-, MuSig- oder
  ECDH-Module). Lizenz: MIT, siehe `COPYING`.
- Übersetzt wird über `build_*.c`: jede Hülle schaltet nur die Warnung für
  ungenutzte statische Funktionen ab und bindet eine Datei aus `src/` ein.
- Einstellungen: die Vorgaben der Bibliothek (`ECMULT_WINDOW_SIZE` 15,
  `COMB_BLOCKS` 11, `COMB_TEETH` 6), passend zu den vorberechneten Tabellen.

Warum eingebettet statt als Paket: Die Wallet hängt an genau dieser Datei
Code. Ein Paketupdate könnte sie unbemerkt ändern; so ist jede Änderung ein
sichtbarer Diff, der sich gegen den Tag prüfen lässt:

```sh
git clone --depth 1 -b v0.7.1 https://github.com/bitcoin-core/secp256k1 /tmp/secp
for f in include/* src/*; do cmp "$f" "/tmp/secp/$f" || echo "ANDERS: $f"; done
```

Aktualisieren: dieselben Dateien aus dem neuen Tag kopieren, obigen Vergleich
anpassen, `swift test` (Vektoren in `KryptaBitcoinTests`) laufen lassen.
