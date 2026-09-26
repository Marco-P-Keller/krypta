# Bitcoin in Krypta

Jedes Konto hat eine eigene Bitcoin-Wallet. Im Chat kann man Kontakte direkt
bezahlen: das Geld geht über die Bitcoin-Blockchain, im Chat steht, dass
jemand gezahlt hat. Selbstverwahrt: Krypta (und damit auch der Betreiber)
hat nie Zugriff auf das Geld.

## Überblick

| Teil | Wo | Was |
|---|---|---|
| Kurve | `KryptaCore/Sources/Csecp256k1` | libsecp256k1 v0.7.1 aus Bitcoin Core, unverändert eingebettet ([README](KryptaCore/Sources/Csecp256k1/README.md)) |
| Bitcoin | `KryptaCore/Sources/KryptaBitcoin` | BIP39, BIP32, BIP84, Bech32/Bech32m, Base58Check, Adressen, BIP21, Transaktionen, BIP143, Münzauswahl, Merkle-Beweise. Ohne Netz. |
| Wallet | `KryptaCore/Sources/KryptaWallet` | Abgleich über Esplora, Adressen je Kontakt, Senden, Prüfen von Zahlungen aus dem Chat |
| Chat | `KryptaMessenger/Engine+Payments.swift` | `_btc` und `_pay` in der Ende-zu-Ende-Verschlüsselung |
| App | `Krypta/Services/WalletKeychain.swift`, `Krypta/Features/Wallet/` | Schlüsselbund mit Face ID, Oberfläche |

## Schlüssel

- **Entstehung:** 16 Bytes aus `SecRandomCopyBytes` beim Einrichten (oder beim
  ersten Entsperren nach dem Update). Daraus zwölf Wörter nach BIP39 und die
  Schlüssel nach BIP84 (`m/84'/0'/0'`, native Segwit, `bc1q…`). Testnetze:
  `m/84'/1'/0'`.
- **Aufbewahrung:** im Schlüsselbund, `WhenUnlockedThisDeviceOnly` und an
  `userPresence` gebunden (Face ID, Touch ID oder Gerätecode). Nicht in
  Backups, nicht in iCloud, nicht auf anderen Geräten. Ohne Bestätigung
  kommt auch Krypta selbst nicht an den Schlüssel; iOS erzwingt das in der
  Secure Enclave. Hat das iPhone keinen Code, erlaubt iOS diese Bindung
  nicht; dann liegt der Schlüssel ohne sie da, und die Wallet sagt das
  deutlich (Einstellungen → Schutz). Wer den Gerätecode später entfernt,
  kann den Schlüssel für iOS unlesbar machen; dann hilft das
  Wiederherstellen mit den zwölf Wörtern.
- **Benutzung:** nur zum Signieren und zum Anzeigen der Wörter, jeweils nach
  Face ID oder Code. Seed und private Schlüssel leben nur für diesen Moment
  im Speicher und werden danach überschrieben (so gut Swift das zulässt).
- **Öffentlich:** Die Kontoschlüssel (xpub) liegen ohne Rückfrage lesbar im
  Schlüsselbund. Aus ihnen entstehen alle Adressen; Geld bewegen kann man
  damit nicht.
- **Löschen:** Löschcode, Notfallknopf, fünf falsche Tresor-Passwörter und
  „Alles löschen" nehmen die Wallet mit. Das Guthaben bleibt auf der
  Blockchain und lässt sich mit den zwölf Wörtern zurückholen, in Krypta
  oder jeder anderen Wallet (BIP39/BIP84). Deshalb drängt die Wallet, die
  Wörter zu sichern, und prüft die Abschrift.

## Bezahlen im Chat

Alles reist **innerhalb** der Ende-zu-Ende-Verschlüsselung (Double Ratchet,
Sealed Sender). Der Krypta-Server sieht weder Adressen noch Beträge noch,
dass überhaupt Bitcoin im Spiel ist.

1. **`_btc`** in jeder Nachricht und Steuernachricht an einen Kontakt:
   `{"n": "main"}`, und sobald bekannt ist, dass der Kontakt selbst eine
   Wallet hat, zusätzlich `"a"`: eine Empfangsadresse **nur für ihn**.
   Eine Flutter-App schickt kein `_btc` und bekommt deshalb nie eine
   Adresse. Schaltet jemand „Zahlungen im Chat" aus, fehlt `_btc`, und seine
   Kontakte vergessen die Adresse.
2. Wird die Adresse benutzt, bekommt der Kontakt mit der nächsten Nachricht
   (oder Zustellbestätigung) eine neue. So bleibt jede Zahlung auf der
   Blockchain für sich.
3. **Senden:** planen (Münzauswahl, Gebühr), bestätigen, Face ID, signieren,
   Transaktion an den Server. Erst wenn der Server sie angenommen hat, geht
   die Nachricht mit **`_pay`** raus: `{"txid", "vout", "sat", "a", "n"}`,
   dazu die Notiz als `_t`.
4. **Empfangen:** Die Nachricht ist nur eine Behauptung. Die Wallet prüft:
   die Adresse ist eine eigene; die rohe Transaktion hat genau diese Kennung
   (SHA-256² selbst gerechnet); ihre Ausgabe `vout` zahlt an diese Adresse.
   Angezeigt wird der **tatsächlich** gezahlte Betrag. Stimmt etwas nicht,
   steht „Stimmt nicht" in Rot, nie ein Betrag, der nicht angekommen ist.
   Je Kontakt prüft die Wallet höchstens zehn offene Zahlungen zugleich: wer
   mit erfundenen Zahlungen flutet, blockiert nur seine eigenen.
5. **Bestätigt** heißt: Merkle-Beweis bis in einen Blockkopf, dessen Hash
   Krypta selbst nachrechnet und dessen Arbeit mindestens Schwierigkeit 50 T
   entspricht (Bitcoin; heute liegt sie weit darüber). Einen Block zu
   erfinden, um eine Zahlung vorzutäuschen, kostet Strom für sechsstellige
   Beträge. Bis sechs Bestätigungen wird nachgeprüft.

Die Chatliste zeigt bei Zahlungen keinen Betrag (dort stünde sonst die
ungeprüfte Behauptung).

## Senden ohne Doppelzahlung

- Vor dem Signieren: sind die gewählten Münzen noch frei? Nach Face ID noch
  einmal (ein Abgleich könnte dazwischengekommen sein).
- Nach dem Signieren: jede Signatur wird gegen Schlüssel und Sighash
  geprüft; der Empfänger bekommt genau den Betrag, das Wechselgeld geht an
  eine eigene, frische Adresse, die Gebühr ist die angezeigte.
- Die signierte Transaktion wird **vor** dem Senden gespeichert und ihre
  Münzen gesperrt. Lehnt der Server ab (HTTP 4xx), werden sie frei: nur er
  hatte die Transaktion. Bricht die Verbindung ab, bleibt offen, ob sie raus
  ist: dann bleiben die Münzen gesperrt, und jeder Abgleich fragt für jeden
  Eingang, wer ihn ausgegeben hat. Diese Transaktion → erledigt; eine
  andere → diese kann nie mehr gelten; niemand → **genau dieselbe**
  Transaktion noch einmal senden. Eine zweite Zahlung entsteht nie.
- Scheitert nach dem Senden nur die Chat-Nachricht, schickt „erneut senden"
  nur die Nachricht, nie eine zweite Transaktion.
- Gebühr: Sätze vom Server, geordnet und auf 1 bis 1000 sat/vB begrenzt.
  Gerechnet wird mit der größtmöglichen Signatur, der echte Satz liegt nie
  darunter. Über 10 % des Betrags fragt die App extra nach.
- RBF ist gesetzt (`nSequence = 0xFFFFFFFD`), `nLockTime` ist die aktuelle
  Blockhöhe (gegen Fee Sniping, wie Bitcoin Core). Die Reihenfolge von
  Empfänger und Wechselgeld ist zufällig.

## Der Server

Standard ist [mempool.space](https://mempool.space) (Esplora-Schnittstelle),
in den Wallet-Einstellungen lässt sich ein eigener Server eintragen (nur
HTTPS), etwa der eigene Knoten mit Esplora oder mempool.

| Der Server kann … | Folge |
|---|---|
| sehen, welche Adressen die Wallet abfragt, und die IP-Adresse | Datenschutz: er kann die Adressen einer Wallet verknüpfen. Abhilfe: eigener Server. |
| schweigen oder falsche Guthaben zeigen | Anzeige falsch oder leer; Geld bewegen kann er nicht |
| über Beträge von Münzen lügen | Die Signatur (BIP143) enthält die Beträge; eine gelogene Zahl ergibt eine ungültige Transaktion, keine höhere Gebühr |
| eine Zahlung im Chat vortäuschen | Nein: Krypta prüft die rohe Transaktion selbst; „bestätigt" nur mit Merkle-Beweis und echter Blockarbeit |
| eine überhöhte Gebühr vorschlagen | Begrenzung auf 1000 sat/vB, Gebühr steht vor dem Senden in sat und Prozent da |

Unbestätigte Zahlungen sind bei Bitcoin grundsätzlich nicht endgültig
(der Absender kann sie mit RBF ersetzen). Die Blase sagt deshalb
„Unbestätigt", bis ein Block sie enthält.

## Was Krypta nicht verhindern kann

- Wer das entsperrte iPhone **und** Face ID oder den Code hat, kann Bitcoin
  senden.
- Ein kompromittiertes Gerät des Kontakts kann eine falsche Adresse
  schicken. Die Adresse kommt aber immer über den verifizierten,
  Ende-zu-Ende-verschlüsselten Kanal; ein Server dazwischen kann sie nicht
  austauschen. Sicherheitsnummer vergleichen schützt vor dem Mann in der Mitte.
- Wer nur die Wörter kennt, hat das Geld. Die Wörter gehören auf Papier.
- Nach dem Wiederherstellen sucht Krypta 200 Adressen tief. Hatte man mehr
  als 150 Kontakten Adressen gegeben, die nie benutzt wurden, hilft
  „Adressen gründlich durchsuchen" (Krypta vergibt nicht mehr offene
  Adressen als das).
- Kein Lightning, keine Taproot-Adressen für die eigene Wallet (senden an
  Taproot geht), keine Gebührenerhöhung für hängende Zahlungen in der
  Oberfläche.

## Tests

```sh
cd ios-native/KryptaCore && swift test
```

- `KryptaBitcoinTests`: offizielle Vektoren für BIP39 (Trezor, alle 24),
  BIP32 (Vektoren 1 bis 5), BIP84, BIP143 (Sighash **und** Signatur Byte für
  Byte), BIP173/BIP350, RIPEMD-160, Block 100 000 (Kopf, Merkle-Wurzel);
  Parser gegen Müll; Münzauswahl mit Zufallsfällen (Summen, Staub,
  Mindestsatz).
- `KryptaWalletTests`: zwei Wallets auf einer Kette im Speicher, die jede
  Signatur wie ein Knoten prüft: Empfangen, Bezahlen, Prüfen,
  gefälschte Zahlungen (zu hoch, fremde Adresse, falsche Ausgabe,
  erfunden, falsches Netz), Netzfehler beim Senden, Ablehnung, abgebrochene
  Rückfrage, veraltete Entwürfe, Wiederherstellen mit Geld an Adresse 150.
- `KryptaMessengerTests/PaymentTests`: zwei Messenger mit Wallets. Adressen
  nur verschlüsselt (der Server sieht keine), Zahlung im Chat bis zur
  Bestätigung, „erneut senden" ohne zweite Transaktion, Kontakte ohne
  Wallet, gefälschte Zahlungsnachricht.
- Gegen **Bitcoin Core 29.1** (Regtest, einmalig beim Bau): 22 mit
  `KryptaBitcoin` signierte Transaktionen, an alle Adressarten, mit mehreren
  Eingängen, unbestätigten Ketten, „alles senden", 1 bis 150 sat/vB. Alle
  von `testmempoolaccept` angenommen und gemined, Gebühr auf den Satoshi
  wie geplant, Größenschätzung nie zu klein.

## Demo-Modus

`-KryptaDemo` startet mit einer Blockchain im Speicher (Regtest): 0,05 BTC
Guthaben, und Lena bezahlt im Chat 0,0021 BTC „Für die Pizza 🍕".

## Rechtliches

Die Wallet ist selbstverwahrend: Schlüssel und Geld liegen beim Nutzer, der
Anbieter von Krypta kann nichts bewegen. Für den App Store gilt Richtlinie
3.1.5(a): Apps mit Wallet müssen von einem als Organisation registrierten
Entwickler kommen.
