"""Signiert mit KryptaBitcoin (regtest-signer) und lässt Bitcoin Core prüfen.

Aufruf über run.sh. Jede Transaktion muss `testmempoolaccept` bestehen, die
Gebühr muss auf den Satoshi stimmen, die geschätzte Größe darf nie kleiner
sein als die echte, der Satz nie unter dem gewählten liegen.
"""
import json, subprocess, random, sys, os, time, hashlib
BTC=os.environ.get('BITCOIN_BIN', '')
DATA=os.environ['DATADIR']
SIGNER=os.environ['SIGNER']
env=dict(os.environ)
def tool(name):
    return os.path.join(BTC, name) if BTC else name
WORDS='abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'
def cli(*a):
    out=subprocess.run([tool('bitcoin-cli'),'-regtest','-datadir='+DATA,'-rpcuser=u','-rpcpassword=p']+[str(x) for x in a],capture_output=True,text=True)
    if out.returncode: raise Exception(out.stderr)
    s=out.stdout.strip()
    try: return json.loads(s)
    except: return s
def sign(job):
    job.setdefault('words',WORDS); job.setdefault('changeIndex',0); job.setdefault('lockTime',0)
    r=subprocess.run([SIGNER],input=json.dumps(job),capture_output=True,text=True,env=env)
    return json.loads(r.stdout)
subprocess.run([tool('bitcoind'),'-regtest','-datadir='+DATA,'-rpcuser=u','-rpcpassword=p','-daemon','-fallbackfee=0.0001','-txindex=1'],check=True)
for _ in range(50):
    try: cli('getblockcount'); break
    except Exception: time.sleep(0.3)
addrs=sign({'coins':[],'recipient':'','feeRate':1})
recv, chg = addrs['receive'], addrs['change']
# Coinbases an Adresse 0..4, dann 100 Blöcke zum Reifen an eine Fremdadresse (P2TR aus BIP350-Vektor, regtest-hrp)
for i in range(5): cli('generatetoaddress',1,recv[i])
# Fremde Adressen jeder Art (regtest): P2WPKH (Kryptas change 19 zählt hier als fremd), P2TR, P2WSH, P2PKH, P2SH
# P2TR/P2WSH-Programme beliebig; Core akzeptiert Ausgaben an jedes Programm.
def bech(hrp,ver,prog):
    CH='qpzry9x8gf2tvdw0s3jn54khce6mua7l'
    def pm(v):
        g=[0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3];c=1
        for x in v:
            t=c>>25;c=(c&0x1ffffff)<<5^x
            for i in range(5): c^=g[i] if (t>>i)&1 else 0
        return c
    def cb(d,f,t):
        acc=bits=0;r=[];m=(1<<t)-1
        for v in d:
            acc=(acc<<f)|v;bits+=f
            while bits>=t: bits-=t;r.append((acc>>bits)&m)
        if bits: r.append((acc<<(t-bits))&m)
        return r
    data=[ver]+cb(prog,8,5)
    const=1 if ver==0 else 0x2bc830a3
    e=[ord(x)>>5 for x in hrp]+[0]+[ord(x)&31 for x in hrp]
    mod=pm(e+data+[0]*6)^const
    return hrp+'1'+''.join(CH[d] for d in data+[(mod>>5*(5-i))&31 for i in range(6)])
def b58check(payload):
    A='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
    p=payload+hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4]
    n=int.from_bytes(p,'big');s=''
    while n: n,r=divmod(n,58);s=A[r]+s
    return '1'*(len(p)-len(p.lstrip(b'\0')))+s
xonly=cli('getblock',cli('getbestblockhash'))['hash']  # beliebige 32 Bytes
foreign={
 'p2wpkh': chg[19],
 'p2tr': bech('bcrt',1,list(bytes.fromhex('79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'))),
 'p2wsh': bech('bcrt',0,list(hashlib.sha256(b'krypta').digest())),
 'p2pkh': b58check(b'\x6f'+hashlib.sha256(b'a').digest()[:20]),
 'p2sh': b58check(b'\xc4'+hashlib.sha256(b'b').digest()[:20]),
}
for k,v in foreign.items():
    info=cli('validateaddress',v); assert info['isvalid'], (k,v)
cli('generatetoaddress',101,foreign['p2tr'])
def utxos_of(address):
    r=cli('scantxoutset','start',json.dumps(['addr('+address+')']))
    return r['unspents']
def coins_for(pairs):
    cs=[]
    for chain,idx in pairs:
        a=(recv if chain==0 else chg)[idx]
        for u in utxos_of(a):
            cs.append({'txid':u['txid'],'vout':u['vout'],'value':round(u['amount']*1e8),'chain':chain,'index':idx})
    return cs
ok=0
def check(res, rate, label, mine=True):
    global ok
    assert 'hex' in res, (label,res)
    acc=cli('testmempoolaccept',json.dumps([res['hex']]))[0]
    assert acc['allowed'], (label, acc)
    assert acc['txid']==res['txid'], (label,'txid')
    vs=acc['vsize']; fee=round(acc['fees']['base']*1e8)
    assert fee==res['fee'], (label,'fee',fee,res['fee'])
    assert vs<=res['estimatedVSize'], (label,'vsize',vs,res['estimatedVSize'])
    assert fee/vs>=rate-1e-9, (label,'rate',fee/vs,rate)
    txid=cli('sendrawtransaction',res['hex'])
    dec=cli('getrawtransaction',txid,'true')
    assert all(v['value']*1e8>=294 or v['scriptPubKey']['type'] in ('pubkeyhash','scripthash') for v in dec['vout'])
    ok+=1
    print(f"ok {label}: {res['inputs']} in, vsize {vs} (Schätzung {res['estimatedVSize']}), {fee} sat, {fee/vs:.2f} sat/vB")
    return txid
# 1. Coinbase (Adresse 0) an jede fremde Art, mit Wechselgeld
for n,(kind,addr) in enumerate(foreign.items()):
    idx=n
    cs=coins_for([(0,idx)])
    rate=random.choice([1,2.5,7,33,150])
    res=sign({'coins':cs,'recipient':addr,'amount':random.randint(10_000,90_000_000),'feeRate':rate,'changeIndex':n,'lockTime':cli('getblockcount')})
    check(res,rate,'coinbase -> '+kind)
cli('generatetoaddress',1,foreign['p2tr'])
# 2. Mehrere Wechselgeld-Münzen zusammen ausgeben (mehrere Eingänge)
cs=coins_for([(1,i) for i in range(5)])
assert len(cs)>=5, cs
big=sum(c['value'] for c in cs)
res=sign({'coins':cs,'recipient':foreign['p2wpkh'],'amount':big-cs[0]['value']//2,'feeRate':12,'changeIndex':6,'lockTime':cli('getblockcount')})
assert res['inputs']>=2
check(res,12,'mehrere Eingänge')
# 3. Unbestätigtes Wechselgeld weiter ausgeben (Kette im Mempool)
cs=coins_for([(1,6)]) or []
if not cs:
    tx=cli('getrawmempool')
cs=[]
for txid in cli('getrawmempool'):
    d=cli('getrawtransaction',txid,'true')
    for v in d['vout']:
        if v['scriptPubKey'].get('address')==chg[6]:
            cs.append({'txid':txid,'vout':v['n'],'value':round(v['value']*1e8),'chain':1,'index':6,'confirmed':False})
assert cs
res=sign({'coins':cs,'recipient':recv[10],'amount':100_000,'feeRate':3,'changeIndex':7})
check(res,3,'unbestätigte Kette')
cli('generatetoaddress',1,foreign['p2tr'])
# 4. Alles abräumen (ohne Wechselgeld), an eigene Empfangsadresse
cs=coins_for([(1,i) for i in range(20)]+[(0,10)])
res=sign({'coins':cs,'recipient':recv[11],'feeRate':5})
assert res['changeIndex']==-1
check(res,5,'alles senden')
cli('generatetoaddress',1,foreign['p2tr'])
# 5. Zufallsrunden: kleine Beträge, Staubgrenzen, viele Sätze
for round_ in range(25):
    cs=coins_for([(0,11)]+[(1,i) for i in range(8,19)])
    if not cs: break
    total=sum(c['value'] for c in cs)
    rate=random.choice([1,1.1,2,5,9.9,20,100])
    amt=random.choice([294,295,1000,random.randint(294,total//3)])
    res=sign({'coins':cs,'recipient':random.choice([recv[12],foreign['p2pkh'],foreign['p2sh'],foreign['p2tr']]),'amount':amt,'feeRate':rate,'changeIndex':8+round_%11,'lockTime':cli('getblockcount')})
    if 'error' in res: print('skip',res); continue
    check(res,rate,f'Runde {round_}')
    cli('generatetoaddress',1,foreign['p2tr'])
cli('generatetoaddress',1,foreign['p2tr'])
print('ALLE OK:',ok,'Transaktionen von Bitcoin Core angenommen und gemined; Mempool leer:',cli('getmempoolinfo')['size']==0)
cli('stop')
