# Bitcoin gegen Bitcoin Core prüfen

Die Unit-Tests (`KryptaCore/Tests/KryptaBitcoinTests`, `KryptaWalletTests`)
prüfen gegen die offiziellen Vektoren und eine Kette im Speicher. Dieses
Werkzeug geht einen Schritt weiter: es lässt einen echten Bitcoin-Core-Knoten
(Regtest) jede Transaktion beurteilen.

```sh
BITCOIN_BIN=/pfad/zu/bitcoin/bin ./run.sh   # bitcoind, bitcoin-cli; Python 3
```

1. `regtest.py` + `regtest-signer`: Coinbases an Adressen der Wallet,
   dann über 20 Transaktionen, geplant und signiert mit `KryptaBitcoin`: an
   P2WPKH, P2TR, P2WSH, P2PKH und P2SH, mit mehreren Eingängen, über
   unbestätigtes Wechselgeld, „alles senden", 1 bis 150 sat/vB. Jede muss
   `testmempoolaccept` bestehen; Gebühr auf den Satoshi wie geplant,
   geschätzte Größe nie kleiner als die echte, Satz nie unter dem gewählten.
2. `esplora_mock.py` + `esplora-e2e`: ein kleiner Esplora-Server über dem
   Knoten (Format wie mempool.space) und zwei `WalletEngine` mit dem echten
   `EsploraClient`: Guthaben, Senden, Prüfen der Zahlung mit Merkle-Beweis
   gegen den echten Blockkopf, Zurücksenden, Doppelausgabe abgewiesen.

Zuletzt gelaufen mit Bitcoin Core 29.1: in zwei Läufen 22 und 27
Transaktionen (die Runden sind zufällig) angenommen und gemined,
Ende-zu-Ende ohne Fehler.
