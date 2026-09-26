#!/bin/sh
# Prüft KryptaBitcoin und KryptaWallet gegen Bitcoin Core (Regtest).
#
#   BITCOIN_BIN=/pfad/zu/bitcoin/bin ./run.sh
#
# Braucht bitcoind und bitcoin-cli (Bitcoin Core 25 oder neuer) und Python 3.
set -eu
cd "$(dirname "$0")"
swift build -q
export SIGNER="$(swift build --show-bin-path)/regtest-signer"
export DATADIR="$(mktemp -d)"
BIN="${BITCOIN_BIN:+$BITCOIN_BIN/}"
cleanup() {
    "${BIN}bitcoin-cli" -regtest -datadir="$DATADIR" -rpcuser=u -rpcpassword=p stop >/dev/null 2>&1 || true
    [ -n "${MOCK:-}" ] && kill "$MOCK" 2>/dev/null || true
    sleep 1
    rm -rf "$DATADIR"
}
trap cleanup EXIT

# 1. Signieren: 20+ Transaktionen, alle Adressarten, gegen testmempoolaccept.
python3 regtest.py

# 2. Zwei Wallets über Esplora-HTTP (esplora_mock.py liefert die Daten von
#    Bitcoin Core): Abgleich, Senden, Prüfen mit echtem Merkle-Beweis.
#    Frische Kette, damit die Coinbase 50 BTC bringt.
sleep 2
rm -rf "$DATADIR" && mkdir -p "$DATADIR"
"${BIN}bitcoind" -regtest -datadir="$DATADIR" -rpcuser=u -rpcpassword=p -daemon -txindex=1 >/dev/null
sleep 3
python3 esplora_mock.py 3002 &
MOCK=$!
sleep 1
"$(swift build --show-bin-path)/esplora-e2e"
