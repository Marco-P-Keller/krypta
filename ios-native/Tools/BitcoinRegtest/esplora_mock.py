"""Ein kleiner Esplora-Server über bitcoind -regtest (nur für den Test).

Liefert die Endpunkte, die KryptaWallet benutzt, im Format von Esplora
(Blockstream/mempool.space). Daten kommen direkt aus Bitcoin Core: echte
Transaktionen, echte Blockköpfe, echte Merkle-Bäume.
"""
import json, subprocess, os, sys, hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BTC = os.environ.get('BITCOIN_BIN', '')
DATA = os.environ['DATADIR']

def cli(*a):
    out = subprocess.run([os.path.join(BTC, 'bitcoin-cli') if BTC else 'bitcoin-cli', '-regtest', '-datadir=' + DATA, '-rpcuser=u', '-rpcpassword=p'] + [str(x) for x in a], capture_output=True, text=True)
    if out.returncode:
        raise RuntimeError(out.stderr.strip())
    s = out.stdout.strip()
    try:
        return json.loads(s)
    except Exception:
        return s

def sats(v):
    return int(round(v * 1e8))

def dsha(b):
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()

def index():
    """Alle Transaktionen der Kette und des Mempools mit Status."""
    txs = {}
    height = cli('getblockcount')
    for h in range(height + 1):
        bh = cli('getblockhash', h)
        b = cli('getblock', bh, 2)
        for pos, t in enumerate(b['tx']):
            txs[t['txid']] = (t, {'confirmed': True, 'block_height': h, 'block_hash': bh, 'block_time': b['time']}, bh, pos)
    for txid in cli('getrawmempool'):
        t = cli('getrawtransaction', txid, 'true')
        txs[txid] = (t, {'confirmed': False}, None, None)
    return txs

def prevout(txs, vin):
    if 'coinbase' in vin:
        return None
    t = txs[vin['txid']][0]
    o = t['vout'][vin['vout']]
    return {'scriptpubkey': o['scriptPubKey']['hex'], 'scriptpubkey_address': o['scriptPubKey'].get('address'), 'value': sats(o['value'])}

def esplora_tx(txs, txid):
    t, status, _, _ = txs[txid]
    vin = []
    for v in t['vin']:
        vin.append({'txid': v.get('txid', '0' * 64), 'vout': v.get('vout', 0xffffffff), 'prevout': prevout(txs, v),
                    'is_coinbase': 'coinbase' in v, 'sequence': v['sequence']})
    vout = [{'scriptpubkey': o['scriptPubKey']['hex'], 'scriptpubkey_address': o['scriptPubKey'].get('address'), 'value': sats(o['value'])} for o in t['vout']]
    ins = sum(p['prevout']['value'] for p in vin if p['prevout'])
    fee = 0 if any(p['is_coinbase'] for p in vin) else ins - sum(o['value'] for o in vout)
    return {'txid': txid, 'version': t['version'], 'locktime': t['locktime'], 'vin': vin, 'vout': vout,
            'size': t['size'], 'weight': t['weight'], 'fee': fee, 'status': status}

def spends(txs):
    s = {}
    for txid, (t, status, _, _) in txs.items():
        for i, v in enumerate(t['vin']):
            if 'txid' in v:
                s[(v['txid'], v['vout'])] = (txid, i, status)
    return s

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype='application/json'):
        data = body if isinstance(body, bytes) else (json.dumps(body) if ctype == 'application/json' else str(body)).encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        if self.path == '/tx':
            try:
                self.send(200, cli('sendrawtransaction', body.strip()), 'text/plain')
            except RuntimeError as e:
                self.send(400, str(e), 'text/plain')
        elif self.path.startswith('/_mine'):
            q = dict(p.split('=') for p in self.path.split('?')[1].split('&'))
            cli('generatetoaddress', q['n'], q['address'])
            self.send(200, 'ok', 'text/plain')
        else:
            self.send(404, 'not found', 'text/plain')

    def do_GET(self):
        p = self.path.strip('/').split('/')
        try:
            if p == ['blocks', 'tip', 'height']:
                return self.send(200, cli('getblockcount'), 'text/plain')
            if p == ['fee-estimates']:
                return self.send(200, {'1': 5.1, '2': 4.0, '3': 3.2, '6': 2.0, '24': 1.2, '144': 1.0})
            if p == ['v1', 'prices']:
                return self.send(200, {'time': 0, 'USD': 100000, 'EUR': 92000, 'CHF': 86000})
            if p[0] == 'block' and len(p) == 3 and p[2] == 'header':
                return self.send(200, cli('getblockheader', p[1], 'false'), 'text/plain')
            txs = index()
            if p[0] == 'address':
                addr = p[1]
                touching = [tid for tid, (t, st, _, _) in txs.items()
                            if any(o['scriptPubKey'].get('address') == addr for o in t['vout'])
                            or any((prevout(txs, v) or {}).get('scriptpubkey_address') == addr for v in t['vin'])]
                if len(p) == 2:
                    stats = {True: dict(funded_txo_count=0, funded_txo_sum=0, spent_txo_count=0, spent_txo_sum=0, tx_count=0),
                             False: dict(funded_txo_count=0, funded_txo_sum=0, spent_txo_count=0, spent_txo_sum=0, tx_count=0)}
                    for tid in touching:
                        t, st, _, _ = txs[tid]
                        s = stats[st['confirmed']]
                        s['tx_count'] += 1
                        for o in t['vout']:
                            if o['scriptPubKey'].get('address') == addr:
                                s['funded_txo_count'] += 1; s['funded_txo_sum'] += sats(o['value'])
                        for v in t['vin']:
                            po = prevout(txs, v)
                            if po and po['scriptpubkey_address'] == addr:
                                s['spent_txo_count'] += 1; s['spent_txo_sum'] += po['value']
                    return self.send(200, {'address': addr, 'chain_stats': stats[True], 'mempool_stats': stats[False]})
                if p[2] == 'utxo':
                    sp = spends(txs)
                    out = []
                    for tid in touching:
                        t, st, _, _ = txs[tid]
                        for o in t['vout']:
                            if o['scriptPubKey'].get('address') == addr and (tid, o['n']) not in sp:
                                out.append({'txid': tid, 'vout': o['n'], 'value': sats(o['value']), 'status': st})
                    return self.send(200, out)
                if p[2] == 'txs':
                    order = sorted(touching, key=lambda tid: (txs[tid][1]['confirmed'], -(txs[tid][1].get('block_height') or 0)))
                    return self.send(200, [esplora_tx(txs, tid) for tid in order][:75])
            if p[0] == 'tx':
                txid = p[1]
                if txid not in txs:
                    return self.send(404, 'Transaction not found', 'text/plain')
                if len(p) == 2:
                    return self.send(200, esplora_tx(txs, txid))
                if p[2] == 'hex':
                    return self.send(200, cli('getrawtransaction', txid), 'text/plain')
                if p[2] == 'status':
                    return self.send(200, txs[txid][1])
                if p[2] == 'outspend':
                    sp = spends(txs).get((txid, int(p[3])))
                    return self.send(200, {'spent': False} if not sp else {'spent': True, 'txid': sp[0], 'vin': sp[1], 'status': sp[2]})
                if p[2] == 'merkle-proof':
                    t, st, bh, pos = txs[txid]
                    if not st['confirmed']:
                        return self.send(400, 'not confirmed', 'text/plain')
                    level = [bytes.fromhex(x)[::-1] for x in cli('getblock', bh, 1)['tx']]
                    branch, i = [], pos
                    while len(level) > 1:
                        if len(level) % 2:
                            level.append(level[-1])
                        branch.append(level[i ^ 1][::-1].hex())
                        level = [dsha(level[k] + level[k + 1]) for k in range(0, len(level), 2)]
                        i //= 2
                    return self.send(200, {'block_height': st['block_height'], 'merkle': branch, 'pos': pos})
            self.send(404, 'not found', 'text/plain')
        except Exception as e:
            self.send(500, 'error: %s' % e, 'text/plain')

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 3002
    ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
