#!/usr/bin/env python3
"""Version und Export-Compliance gegen App Store Connect pruefen.

Warum: Am 2026-08-23 lief ein Build 26 Minuten durch — Archivieren und
IPA-Export komplett erfolgreich — und starb erst beim Upload an vier
Metadatenfehlern. Alle vier waren vorher bekannt, wenn man App Store Connect
gefragt haette:

    90186  train version '1.0.0' is closed for new build submissions
    90478  version can't be imported, a later version has been closed
    90062  CFBundleShortVersionString [1.0.0] muss hoeher sein als [3.0.0]
    90592  Invalid Export Compliance Code, Wert in der Info.plist ist leer

Dieses Skript fragt genau das ab, bevor der teure Teil laeuft.

    python scripts/asc_app_state.py show
    python scripts/asc_app_state.py check --version 3.0.1

Auth wie bei asc_certs.py: ASC_KEY_ID, ASC_ISSUER_ID und ASC_KEY_P8 bzw.
ASC_KEY_PATH. Die Bundle ID kommt aus --bundle-id oder $BUNDLE_ID.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import asc_certs  # noqa: E402  (teilt Auth und HTTP)

API_ROOT = asc_certs.API_ROOT


# -- reine Logik (ohne Netz, deshalb testbar) ---------------------------

def parse_version(raw):
    """"3.0.1" -> (3, 0, 1). Unlesbares -> None.

    Apple erlaubt bis zu drei Zahlensegmente. Verglichen wird numerisch:
    als Text waere "10" kleiner als "9".
    """
    if not raw:
        return None
    parts = str(raw).strip().split(".")
    if not parts or not parts[0]:
        return None
    numbers = []
    for part in parts[:3]:
        if not part.isdigit():
            return None
        numbers.append(int(part))
    while len(numbers) < 3:
        numbers.append(0)
    return tuple(numbers)


def is_higher(candidate, reference):
    """Ist candidate echt groesser als reference?"""
    left, right = parse_version(candidate), parse_version(reference)
    if left is None or right is None:
        return False
    return left > right


def latest_version(versions):
    """Die numerisch groesste lesbare Version, oder None."""
    parsed = [(parse_version(v), v) for v in versions]
    usable = [(key, raw) for key, raw in parsed if key is not None]
    if not usable:
        return None
    return max(usable)[1]


def check_version(candidate, known_versions):
    """Rueckgabe: (ok, Meldung fuers Log)."""
    latest = latest_version(known_versions)
    if latest is None:
        return True, (
            f"App Store Connect kennt noch keine Version — {candidate} ist in Ordnung."
        )
    if is_higher(candidate, latest):
        return True, f"{candidate} liegt ueber der hoechsten bekannten Version {latest}."
    return False, (
        f"Version {candidate} ist nicht hoeher als {latest} (bereits bei App Store "
        f"Connect). Apple lehnt den Upload ab (Fehler 90062/90186). "
        f"pubspec.yaml auf etwas ueber {latest} setzen."
    )


# Die Info.plist-Pruefung (ITSAppUsesNonExemptEncryption gegen
# ITSEncryptionExportComplianceCode) steckt bewusst im Preflight-Schritt des
# Workflows und nicht hier: sie braucht kein Netz, nur eine lokale Datei.
# Eine zweite Kopie an dieser Stelle waere nur eine, die auseinanderlaeuft.


# -- Tarn-Name gegen bereits vergebene App-Namen ------------------------
#
# ITMS-90129 "The bundle uses a bundle name or display name that is already
# taken" killt den Build erst in Apples Verarbeitung, NACH dem Upload — die
# altool-Validierung laesst ihn durch. Ein Fehlversuch kostet damit einen
# kompletten Lauf. Am 2026-08-23 passiert: CFBundleDisplayName stand auf
# "Calc" (vergeben an Michael Wesemann), die deutsche Lokalisierung auf
# "Rechner" (vergeben an Apple selbst) — zwei Kollisionen auf einmal.

def parse_strings_file(text):
    """Ein .strings-File als dict. Kommentare und Leerzeilen fallen raus."""
    pairs = {}
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    for match in re.finditer(r'"([^"]+)"\s*=\s*"([^"]*)"\s*;', text):
        pairs[match.group(1)] = match.group(2)
    return pairs


def name_verdict(name, own_app_name, hits):
    """Darf dieser Anzeigename benutzt werden?

    hits: Liste (land, verkaeufer) exakter Namenstreffer im App Store.
    """
    if own_app_name and name.strip().lower() == own_app_name.strip().lower():
        return True, f'"{name}" ist der eigene App-Store-Name — kein Konflikt.'
    if not hits:
        return True, f'"{name}" ist in den geprueften Stores frei.'
    where = ", ".join(f"{country}: {seller}" for country, seller in hits)
    return False, (
        f'"{name}" ist bereits vergeben ({where}). Apple lehnt den Build in der '
        f"Verarbeitung ab (ITMS-90129) — und zwar erst NACH dem Upload, die "
        f"Validierung laesst ihn durch. Anderen Namen waehlen."
    )


# -- API ----------------------------------------------------------------

def find_app_id(token, bundle_id):
    payload = asc_certs._request(
        "GET", f"{API_ROOT}/apps?filter[bundleId]={bundle_id}&limit=1", token
    )
    data = payload.get("data") or []
    if not data:
        raise SystemExit(f"Keine App mit Bundle ID {bundle_id} in App Store Connect gefunden.")
    return data[0]["id"], (data[0].get("attributes") or {}).get("name", "?")


def _collect(token, url, attribute):
    values = []
    while url:
        payload = asc_certs._request("GET", url, token)
        for entry in payload.get("data", []):
            value = (entry.get("attributes") or {}).get(attribute)
            if value:
                values.append(value)
        url = (payload.get("links") or {}).get("next")
    return values


def fetch_store_versions(token, app_id):
    return _collect(
        token, f"{API_ROOT}/apps/{app_id}/appStoreVersions?limit=200", "versionString"
    )


def fetch_prerelease_versions(token, app_id):
    return _collect(
        token, f"{API_ROOT}/apps/{app_id}/preReleaseVersions?limit=200", "version"
    )


ITUNES_SEARCH = "https://itunes.apple.com/search"
NAME_CHECK_COUNTRIES = ("de", "us")


def itunes_exact_matches(name, countries=NAME_CHECK_COUNTRIES):
    """Exakte Namenstreffer im oeffentlichen App-Store-Katalog.

    Kein Auth noetig. Achtung: die Suche kennt nur *veroeffentlichte* Apps —
    ein reservierter, noch unveroeffentlichter Name taucht hier nicht auf.
    Ein Treffer ist also ein sicheres Nein, kein Treffer ein starkes, aber
    kein garantiertes Ja.
    """
    hits = []
    for country in countries:
        url = ITUNES_SEARCH + "?" + urllib.parse.urlencode(
            {"term": name, "entity": "software", "country": country, "limit": 200}
        )
        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
        except Exception as exc:  # Netzfehler darf den Build nicht kippen
            print(f"  (Namenspruefung {country} nicht moeglich: {exc})")
            continue
        for entry in payload.get("results", []):
            if entry.get("trackName", "").strip().lower() == name.strip().lower():
                hits.append((country, entry.get("sellerName", "?")))
                break
    return hits


def collect_cover_names(info_plist_path, lproj_dir):
    """Alle Namen, unter denen die App auf dem Geraet erscheinen kann.

    Die Basis-Info.plist UND jede Lokalisierung — genau daran ist es
    gescheitert: "Calc" in der Basis, "Rechner" in de.lproj, beide vergeben.
    """
    names = set()
    with open(info_plist_path, "rb") as handle:
        plist = plistlib.load(handle)
    for key in ("CFBundleDisplayName", "CFBundleName"):
        value = plist.get(key, "")
        if value and not value.startswith("$("):
            names.add(value)

    if os.path.isdir(lproj_dir):
        for entry in sorted(os.listdir(lproj_dir)):
            if not entry.endswith(".lproj"):
                continue
            strings_path = os.path.join(lproj_dir, entry, "InfoPlist.strings")
            if not os.path.isfile(strings_path):
                continue
            with open(strings_path, "r", encoding="utf-8") as handle:
                pairs = parse_strings_file(handle.read())
            for key in ("CFBundleDisplayName", "CFBundleName"):
                if pairs.get(key):
                    names.add(pairs[key])
    return sorted(names)


def fetch_encryption_declarations(token, app_id):
    """Die hinterlegten Exportkonformitaets-Erklaerungen der App."""
    url = f"{API_ROOT}/appEncryptionDeclarations?filter[app]={app_id}&limit=200"
    try:
        payload = asc_certs._request("GET", url, token)
    except SystemExit as exc:
        # Kein harter Abbruch: der Key darf diesen Endpunkt evtl. nicht lesen,
        # das soll den Versionscheck nicht mitreissen.
        print(f"  (Exportkonformitaet nicht abfragbar: {exc})")
        return []
    return payload.get("data", [])


# -- CLI ----------------------------------------------------------------

def _context(args):
    token = asc_certs._token_from_env(args)
    bundle_id = args.bundle_id or os.environ.get("BUNDLE_ID", "")
    if not bundle_id:
        raise SystemExit("Bundle ID fehlt: --bundle-id oder $BUNDLE_ID setzen.")
    app_id, name = find_app_id(token, bundle_id)
    return token, app_id, name, bundle_id


def cmd_show(args):
    token, app_id, name, bundle_id = _context(args)
    print(f"App: {name} ({bundle_id}, id {app_id})")

    store = fetch_store_versions(token, app_id)
    print(f"\nApp-Store-Versionen ({len(store)}):")
    for version in sorted(set(store), key=lambda v: parse_version(v) or (0, 0, 0)):
        print(f"  {version}")

    pre = fetch_prerelease_versions(token, app_id)
    print(f"\nTestFlight-Versionen ({len(pre)}):")
    for version in sorted(set(pre), key=lambda v: parse_version(v) or (0, 0, 0)):
        print(f"  {version}")

    highest = latest_version(store + pre)
    print(f"\nHoechste bekannte Version: {highest}")
    if highest:
        print(f"Naechster Upload braucht mehr als {highest}.")

    decls = fetch_encryption_declarations(token, app_id)
    print(f"\nExportkonformitaets-Erklaerungen ({len(decls)}):")
    for decl in decls:
        attrs = decl.get("attributes") or {}
        print(f"  id {decl.get('id')}")
        for key in sorted(attrs):
            print(f"    {key}: {attrs[key]}")
    if not decls:
        print("  keine")
    return 0


def cmd_check(args):
    token, app_id, name, bundle_id = _context(args)
    store = fetch_store_versions(token, app_id)
    pre = fetch_prerelease_versions(token, app_id)
    ok, message = check_version(args.version, store + pre)
    print(f"App: {name} ({bundle_id})")
    print(message)
    if not ok:
        print(f"::error::{message}")
        return 1
    return 0


def cmd_check_names(args):
    own = args.own_name
    if own is None:
        # Ohne --own-name per API holen: sonst schlaegt die Pruefung faelschlich
        # an, wenn der Anzeigename bewusst der eigene App-Store-Name ist.
        try:
            _, _, own, _ = _context(args)
        except SystemExit as exc:
            print(f"Eigener App-Name nicht ermittelbar ({exc}) — pruefe ohne.")
            own = None

    names = collect_cover_names(args.info_plist, args.lproj_dir)
    if not names:
        print("Keine festen Anzeigenamen gefunden — nichts zu pruefen.")
        return 0

    print(f"Anzeigenamen im Bundle: {', '.join(names)}")
    failed = False
    for name in names:
        ok, message = name_verdict(name, own, itunes_exact_matches(name))
        print(("  OK   " if ok else "  FEHLER ") + message)
        if not ok:
            print(f"::error::{message}")
            failed = True
    return 1 if failed else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--key-id", help="Default: $ASC_KEY_ID")
    parser.add_argument("--issuer-id", help="Default: $ASC_ISSUER_ID")
    parser.add_argument("--key-path", help="Default: $ASC_KEY_PATH bzw. $ASC_KEY_P8")
    parser.add_argument("--bundle-id", help="Default: $BUNDLE_ID")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("show", help="Versionen und Exportkonformitaet anzeigen").set_defaults(
        func=cmd_show
    )

    check = sub.add_parser("check", help="Version gegen App Store Connect pruefen")
    check.add_argument("--version", required=True, help="die Version aus pubspec.yaml")
    check.set_defaults(func=cmd_check)

    names = sub.add_parser(
        "check-names", help="Tarn-Namen gegen bereits vergebene App-Namen pruefen"
    )
    names.add_argument("--info-plist", default="ios/Runner/Info.plist")
    names.add_argument("--lproj-dir", default="ios/Runner")
    names.add_argument(
        "--own-name",
        help="eigener App-Store-Name; ohne Angabe per API ermittelt (braucht Auth)",
    )
    names.set_defaults(func=cmd_check_names)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
