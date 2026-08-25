#!/usr/bin/env python3
"""Apple-Development-Zertifikate ueber die App-Store-Connect-API aufraeumen.

Hintergrund: `xcodebuild archive` legt bei automatischer Signatur selbst ein
*Apple Development*-Zertifikat an. Dieser Topf ist pro Account klein und
fuellt sich mit jedem CI-Runner, der noch nie signiert hat. Ist er voll,
bricht der Build mit "Your account has reached the maximum number of
certificates" ab — unabhaengig davon, wie viele *Distribution*-Zertifikate
noch frei waeren. Das sind zwei getrennte Kontingente.

Dieses Skript widerruft das aelteste Development-Zertifikat, damit der
naechste Build wieder eins anlegen kann.

    python scripts/asc_certs.py list
    python scripts/asc_certs.py revoke-oldest --min-count 2 --dry-run
    python scripts/asc_certs.py revoke-oldest --min-count 2

Auth ueber die ueblichen drei Werte (Env oder Flags):
    ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (PEM oder Base64 davon)
    alternativ ASC_KEY_PATH auf eine .p8-Datei

Sicherheitsgrenzen, absichtlich hart verdrahtet:
  * Nur Development-Typen sind ueberhaupt widerrufbar (siehe REVOCABLE_TYPES).
    Ein Distribution-Zertifikat zu widerrufen wuerde jede Release-Signatur
    des Teams brechen — auch die von Marcos anderen Apps.
  * Das einzige vorhandene Zertifikat wird nie widerrufen.
  * --min-count als zusaetzlicher Riegel: unterhalb dieser Anzahl passiert
    nichts, denn dann ist der Topf nicht voll.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime as _dt
import json
import os
import sys
import urllib.error
import urllib.request

API_ROOT = "https://api.appstoreconnect.apple.com/v1"
AUDIENCE = "appstoreconnect-v1"
TOKEN_LIFETIME_SECONDS = 15 * 60  # Apple erlaubt maximal 20 Minuten.

# Was dieses Skript anfassen darf. Bewusst eine Allowlist: ein neuer,
# unbekannter Zertifikatstyp faellt damit auf die sichere Seite.
REVOCABLE_TYPES = frozenset({"DEVELOPMENT", "IOS_DEVELOPMENT", "MAC_APP_DEVELOPMENT"})

# Weit in der Zukunft — sortiert Eintraege ohne createdDate ans Ende, damit
# ein fehlendes Feld nicht als "sehr alt" durchgeht.
_FAR_FUTURE = _dt.datetime(9999, 1, 1, tzinfo=_dt.timezone.utc)


# -- reine Logik (ohne Netz, deshalb testbar) ---------------------------

def parse_date(raw):
    """Apples Datumsformat nach datetime. None/unlesbar -> _FAR_FUTURE."""
    if not raw:
        return _FAR_FUTURE
    text = raw.strip()
    # Apple liefert "+0000", fromisoformat will "+00:00" (vor Python 3.11).
    if len(text) >= 5 and text[-5] in "+-" and text[-3] != ":":
        text = text[:-2] + ":" + text[-2:]
    try:
        parsed = _dt.datetime.fromisoformat(text)
    except ValueError:
        return _FAR_FUTURE
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=_dt.timezone.utc)
    return parsed


def filter_revocable(certs):
    """Nur die Zertifikatstypen, die dieses Skript widerrufen darf."""
    return [
        c for c in certs
        if (c.get("attributes") or {}).get("certificateType") in REVOCABLE_TYPES
    ]


def select_oldest(certs):
    """Das Zertifikat mit dem fruehesten createdDate, oder None."""
    if not certs:
        return None
    return min(
        certs,
        key=lambda c: parse_date((c.get("attributes") or {}).get("createdDate")),
    )


def decide(certs, min_count=1):
    """Entscheidet, ob und was widerrufen wird.

    Rueckgabe: (zertifikat_oder_None, begruendung).
    """
    revocable = filter_revocable(certs)
    if not revocable:
        return None, "Keine Development-Zertifikate vorhanden — nichts zu widerrufen."
    if len(revocable) < min_count:
        return None, (
            f"Nur {len(revocable)} Development-Zertifikat(e), Schwelle ist {min_count} — "
            "der Topf ist nicht voll, es wird nichts widerrufen."
        )
    if len(revocable) == 1:
        return None, "Das einzige Development-Zertifikat wird nicht widerrufen."
    return select_oldest(revocable), "Aeltestes Development-Zertifikat ausgewaehlt."


def describe(cert):
    attrs = cert.get("attributes") or {}
    return (
        f"{attrs.get('displayName', '?')} "
        f"[{attrs.get('certificateType', '?')}] "
        f"Serial {attrs.get('serialNumber', '?')} "
        f"angelegt {attrs.get('createdDate', '?')} "
        f"laeuft ab {attrs.get('expirationDate', '?')} "
        f"(id {cert.get('id', '?')})"
    )


# -- Auth ---------------------------------------------------------------

def load_private_key(p8_value=None, key_path=None):
    """Nimmt PEM, Base64-davon oder einen Dateipfad und liefert PEM-Text."""
    if key_path:
        with open(key_path, "r", encoding="utf-8") as handle:
            return handle.read()
    if not p8_value:
        raise SystemExit("Kein Schluessel: ASC_KEY_P8 oder ASC_KEY_PATH setzen.")
    if "BEGIN PRIVATE KEY" in p8_value:
        return p8_value
    stripped = "".join(p8_value.split())
    try:
        decoded = base64.b64decode(stripped, validate=True).decode("utf-8")
    except (binascii.Error, UnicodeDecodeError) as exc:
        raise SystemExit(f"ASC_KEY_P8 ist weder PEM noch Base64 davon: {exc}")
    if "BEGIN PRIVATE KEY" not in decoded:
        raise SystemExit("ASC_KEY_P8 dekodiert nicht zu einem PEM-Schluessel.")
    return decoded


def build_jwt(key_id, issuer_id, private_key_pem, now=None):
    """ES256-Token fuer die App-Store-Connect-API."""
    import jwt  # lokal importiert, damit die reine Logik ohne PyJWT testbar bleibt

    issued = int(
        now if now is not None else _dt.datetime.now(_dt.timezone.utc).timestamp()
    )
    payload = {
        "iss": issuer_id,
        "iat": issued,
        "exp": issued + TOKEN_LIFETIME_SECONDS,
        "aud": AUDIENCE,
    }
    return jwt.encode(payload, private_key_pem, algorithm="ES256", headers={"kid": key_id})


# -- API ----------------------------------------------------------------

def _request(method, url, token):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = resp.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"App-Store-Connect-API {method} {url} -> HTTP {exc.code}: {detail}")
    except urllib.error.URLError as exc:
        raise SystemExit(f"App-Store-Connect-API nicht erreichbar: {exc.reason}")


def fetch_certificates(token):
    """Alle Zertifikate des Accounts, ueber Seitengrenzen hinweg."""
    certs = []
    url = f"{API_ROOT}/certificates?limit=200"
    while url:
        payload = _request("GET", url, token)
        certs.extend(payload.get("data", []))
        url = (payload.get("links") or {}).get("next")
    return certs


def revoke_certificate(token, cert_id):
    _request("DELETE", f"{API_ROOT}/certificates/{cert_id}", token)


# -- CLI ----------------------------------------------------------------

def _token_from_env(args):
    key_id = args.key_id or os.environ.get("ASC_KEY_ID", "")
    issuer_id = args.issuer_id or os.environ.get("ASC_ISSUER_ID", "")
    if not key_id or not issuer_id:
        raise SystemExit("ASC_KEY_ID und ASC_ISSUER_ID muessen gesetzt sein.")
    pem = load_private_key(
        os.environ.get("ASC_KEY_P8"),
        args.key_path or os.environ.get("ASC_KEY_PATH"),
    )
    return build_jwt(key_id, issuer_id, pem)


def _sort_key(cert):
    return parse_date((cert.get("attributes") or {}).get("createdDate"))


def capacity_verdict(count, limit, revoke_enabled):
    """Reicht der Platz im Development-Topf noch? (ok, Meldung).

    Am 2026-08-25 lief ein Build 22 Minuten — jeder Pod gebaut — und starb
    dann im Archive-Schritt an "Your account has reached the maximum number
    of certificates". Die Zahl steht binnen Sekunden fest, der Abbruch
    gehoert also nach vorn.

    Das Limit wird bewusst nicht geraten: es haengt am Accounttyp, und ein
    zu niedrig geratenes wuerde gesunde Builds blockieren. Ohne bekannte
    Zahl (Repository-Variable IOS_DEV_CERT_LIMIT) wird nur gewarnt.
    """
    if revoke_enabled:
        return True, (
            f"{count} Development-Zertifikat(e); das aelteste wird gleich "
            f"widerrufen, damit ist wieder Platz."
        )
    if limit is None:
        return True, (
            f"{count} Development-Zertifikat(e) im Account. Limit unbekannt — "
            f"setze die Repository-Variable IOS_DEV_CERT_LIMIT auf die Zahl, bei "
            f"der Apple 'maximum number of certificates' meldet, dann bricht der "
            f"Lauf hier ab statt nach 20 Minuten."
        )
    if count >= limit:
        return False, (
            f"{count} von {limit} Development-Zertifikaten belegt — Apple laesst "
            f"kein weiteres zu, und die automatische Signatur braucht genau eins. "
            f"Der Archive-Schritt wuerde nach rund 20 Minuten mit 'maximum number "
            f"of certificates' abbrechen. Lauf mit angehaktem "
            f"revoke_oldest_dev_cert neu starten."
        )
    return True, f"{count} von {limit} Development-Zertifikaten belegt — passt."


def cmd_check_capacity(args):
    token = _token_from_env(args)
    count = len(filter_revocable(fetch_certificates(token)))
    ok, message = capacity_verdict(count, args.limit, args.revoke_enabled)
    print(message)
    if not ok:
        print(f"::error::{message}")
        return 1
    return 0



def cmd_list(args):
    token = _token_from_env(args)
    certs = fetch_certificates(token)
    revocable = filter_revocable(certs)
    revocable_ids = {c.get("id") for c in revocable}
    print(f"{len(certs)} Zertifikat(e) im Account, davon {len(revocable)} Development:")
    for cert in sorted(certs, key=_sort_key):
        mark = "*" if cert.get("id") in revocable_ids else " "
        print(f"  {mark} {describe(cert)}")
    if revocable:
        print("\n* = von revoke-oldest widerrufbar")
    return 0


def cmd_revoke_oldest(args):
    token = _token_from_env(args)
    certs = fetch_certificates(token)
    chosen, reason = decide(certs, min_count=args.min_count)
    print(reason)
    if chosen is None:
        return 0
    print(f"Widerrufen: {describe(chosen)}")
    if args.dry_run:
        print("--dry-run: nichts geaendert.")
        return 0
    revoke_certificate(token, chosen["id"])
    print("Widerrufen. Der naechste Build kann ein neues Zertifikat anlegen.")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--key-id", help="Default: $ASC_KEY_ID")
    parser.add_argument("--issuer-id", help="Default: $ASC_ISSUER_ID")
    parser.add_argument(
        "--key-path",
        help="Pfad zur .p8-Datei; Default: $ASC_KEY_PATH bzw. $ASC_KEY_P8",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="Zertifikate anzeigen").set_defaults(func=cmd_list)

    capacity = sub.add_parser(
        "check-capacity", help="frueh pruefen, ob noch ein Zertifikat passt"
    )
    capacity.add_argument(
        "--limit", type=int, default=None,
        help="Zahl der erlaubten Development-Zertifikate; ohne Angabe nur Warnung",
    )
    capacity.add_argument(
        "--revoke-enabled", action="store_true",
        help="der Widerruf-Schritt laeuft gleich danach — dann nie abbrechen",
    )
    capacity.set_defaults(func=cmd_check_capacity)


    revoke = sub.add_parser(
        "revoke-oldest", help="aeltestes Development-Zertifikat widerrufen"
    )
    revoke.add_argument(
        "--min-count", type=int, default=2,
        help="Erst ab dieser Anzahl Development-Zertifikate widerrufen (Default: 2)",
    )
    revoke.add_argument("--dry-run", action="store_true", help="nur zeigen, nichts aendern")
    revoke.set_defaults(func=cmd_revoke_oldest)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
