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
import os
import sys

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


def check_encryption_key(uses_non_exempt, code):
    """Export-Compliance-Schluessel in der Info.plist plausibilisieren."""
    if not uses_non_exempt:
        return True, "ITSAppUsesNonExemptEncryption ist false — kein Code noetig."
    if code:
        return True, "ITSEncryptionExportComplianceCode ist gesetzt."
    return False, (
        "ITSAppUsesNonExemptEncryption ist true, aber ITSEncryptionExportComplianceCode "
        "fehlt in ios/Runner/Info.plist. Apple lehnt den Upload ab (Fehler 90592). "
        "Den Code liefert App Store Connect unter der App -> App-Informationen -> "
        "Exportkonformitaetsdokumentation."
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

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
