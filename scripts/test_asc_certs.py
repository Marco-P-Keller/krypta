"""Tests fuer scripts/asc_certs.py.

Laufen ohne Netz und ohne echten App-Store-Connect-Key: die Auswahl- und
Filterlogik ist von den HTTP-Aufrufen getrennt, damit genau der Teil testbar
ist, der im Fehlerfall ein fremdes Zertifikat widerrufen wuerde.

    python scripts/test_asc_certs.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import asc_certs  # noqa: E402


def cert(cid, ctype="DEVELOPMENT", created="2026-01-01T00:00:00.000+0000", name="Apple Development: Someone"):
    return {
        "id": cid,
        "type": "certificates",
        "attributes": {
            "certificateType": ctype,
            "createdDate": created,
            "displayName": name,
            "serialNumber": "SERIAL" + cid,
            "expirationDate": "2027-01-01T00:00:00.000+0000",
        },
    }


class SelectOldest(unittest.TestCase):
    def test_picks_earliest_created_date(self):
        certs = [
            cert("b", created="2026-03-01T00:00:00.000+0000"),
            cert("a", created="2026-01-15T00:00:00.000+0000"),
            cert("c", created="2026-07-01T00:00:00.000+0000"),
        ]
        self.assertEqual(asc_certs.select_oldest(certs)["id"], "a")

    def test_empty_list_returns_none(self):
        self.assertIsNone(asc_certs.select_oldest([]))

    def test_missing_created_date_sorts_last_not_first(self):
        # Ein Zertifikat ohne createdDate darf nicht faelschlich als
        # "aeltestes" gewaehlt werden, nur weil das Feld fehlt.
        certs = [cert("a", created="2026-05-01T00:00:00.000+0000")]
        certs.append({"id": "x", "attributes": {"certificateType": "DEVELOPMENT"}})
        self.assertEqual(asc_certs.select_oldest(certs)["id"], "a")

    def test_offset_timezones_compare_correctly(self):
        certs = [
            cert("later", created="2026-05-01T09:00:00.000+0000"),
            cert("earlier", created="2026-05-01T02:00:00.000-0800"),  # = 10:00 UTC
        ]
        self.assertEqual(asc_certs.select_oldest(certs)["id"], "later")


class FilterRevocable(unittest.TestCase):
    """Die Sicherheitsgrenze: Distribution-Zertifikate nie anfassen."""

    def test_keeps_development_types(self):
        certs = [cert("a", "DEVELOPMENT"), cert("b", "IOS_DEVELOPMENT")]
        self.assertEqual(len(asc_certs.filter_revocable(certs)), 2)

    def test_drops_distribution_types(self):
        certs = [
            cert("a", "DISTRIBUTION"),
            cert("b", "IOS_DISTRIBUTION"),
            cert("c", "MAC_APP_DISTRIBUTION"),
            cert("d", "DEVELOPER_ID_APPLICATION"),
        ]
        self.assertEqual(asc_certs.filter_revocable(certs), [])

    def test_drops_unknown_types(self):
        # Was wir nicht kennen, wird nicht widerrufen.
        certs = [cert("a", "PASS_TYPE_ID"), cert("b", "SOMETHING_NEW")]
        self.assertEqual(asc_certs.filter_revocable(certs), [])

    def test_mixed_list_keeps_only_development(self):
        certs = [cert("a", "DEVELOPMENT"), cert("b", "DISTRIBUTION")]
        kept = asc_certs.filter_revocable(certs)
        self.assertEqual([c["id"] for c in kept], ["a"])


class JwtClaims(unittest.TestCase):
    def setUp(self):
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec

        key = ec.generate_private_key(ec.SECP256R1())
        self.pem = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ).decode()

    def _decode(self, token):
        import jwt

        header = jwt.get_unverified_header(token)
        payload = jwt.decode(token, options={"verify_signature": False}, audience="appstoreconnect-v1")
        return header, payload

    def test_header_has_es256_and_key_id(self):
        token = asc_certs.build_jwt("KEYID123", "ISSUER-UUID", self.pem, now=1_770_000_000)
        header, _ = self._decode(token)
        self.assertEqual(header["alg"], "ES256")
        self.assertEqual(header["kid"], "KEYID123")

    def test_payload_claims(self):
        token = asc_certs.build_jwt("KEYID123", "ISSUER-UUID", self.pem, now=1_770_000_000)
        _, payload = self._decode(token)
        self.assertEqual(payload["iss"], "ISSUER-UUID")
        self.assertEqual(payload["aud"], "appstoreconnect-v1")
        self.assertEqual(payload["iat"], 1_770_000_000)

    def test_expiry_within_apple_limit(self):
        # Apple lehnt Tokens mit mehr als 20 Minuten Laufzeit ab.
        token = asc_certs.build_jwt("K", "I", self.pem, now=1_770_000_000)
        _, payload = self._decode(token)
        self.assertLessEqual(payload["exp"] - payload["iat"], 20 * 60)
        self.assertGreater(payload["exp"] - payload["iat"], 0)


class DecideRevocation(unittest.TestCase):
    """Der Gate davor: nur widerrufen, wenn wirklich etwas zu widerrufen ist."""

    def test_refuses_when_below_min_count(self):
        certs = [cert("a"), cert("b")]
        chosen, reason = asc_certs.decide(certs, min_count=3)
        self.assertIsNone(chosen)
        self.assertIn("2", reason)

    def test_proceeds_when_at_min_count(self):
        certs = [cert("a", created="2026-01-01T00:00:00.000+0000"), cert("b"), cert("c")]
        chosen, _ = asc_certs.decide(certs, min_count=3)
        self.assertIsNotNone(chosen)
        self.assertEqual(chosen["id"], "a")

    def test_never_revokes_the_only_certificate(self):
        chosen, reason = asc_certs.decide([cert("a")], min_count=1)
        self.assertIsNone(chosen)
        self.assertIn("einzige", reason.lower())

    def test_distribution_only_account_revokes_nothing(self):
        certs = [cert("a", "DISTRIBUTION"), cert("b", "IOS_DISTRIBUTION")]
        chosen, _ = asc_certs.decide(certs, min_count=1)
        self.assertIsNone(chosen)




class CapacityVerdict(unittest.TestCase):
    """Wann der Zertifikatstopf den Build kippt — und zwar frueh.

    Am 2026-08-25 lief ein Build 22 Minuten, baute jeden Pod, und starb
    dann im Archive-Schritt an "Your account has reached the maximum number
    of certificates". Die Zahl der Zertifikate steht binnen Sekunden fest.

    Das Limit rate ich bewusst nicht: es haengt am Accounttyp, und ein zu
    niedrig geratenes Limit wuerde gesunde Builds blockieren. Ohne bekannte
    Zahl wird nur gewarnt.
    """

    def test_no_limit_known_only_warns(self):
        ok, msg = asc_certs.capacity_verdict(5, limit=None, revoke_enabled=False)
        self.assertTrue(ok)
        self.assertIn("5", msg)

    def test_below_limit_is_fine(self):
        ok, _ = asc_certs.capacity_verdict(1, limit=2, revoke_enabled=False)
        self.assertTrue(ok)

    def test_at_limit_stops_the_run(self):
        ok, msg = asc_certs.capacity_verdict(2, limit=2, revoke_enabled=False)
        self.assertFalse(ok)
        # Die Meldung muss den Ausweg nennen, sonst sucht man ihn wieder.
        self.assertIn("revoke_oldest_dev_cert", msg)

    def test_at_limit_passes_when_revoke_is_armed(self):
        # Der Widerruf-Schritt laeuft gleich danach und macht einen Platz
        # frei — dann waere ein Abbruch hier falsch.
        ok, msg = asc_certs.capacity_verdict(2, limit=2, revoke_enabled=True)
        self.assertTrue(ok)
        self.assertIn("widerrufen", msg.lower())

    def test_over_limit_also_stops(self):
        ok, _ = asc_certs.capacity_verdict(3, limit=2, revoke_enabled=False)
        self.assertFalse(ok)


if __name__ == "__main__":
    unittest.main(verbosity=2)