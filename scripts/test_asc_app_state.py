"""Tests fuer scripts/asc_app_state.py.

Der Kern ist der Versionsvergleich. Der muss numerisch sein, nicht
lexikografisch — sonst gilt "10.0.0" als kleiner als "9.0.0" und der
Preflight winkt genau den Build durch, den Apple ablehnt.

    python scripts/test_asc_app_state.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import asc_app_state as st  # noqa: E402


class ParseVersion(unittest.TestCase):
    def test_three_parts(self):
        self.assertEqual(st.parse_version("3.1.4"), (3, 1, 4))

    def test_short_forms_pad_with_zero(self):
        self.assertEqual(st.parse_version("3.0"), (3, 0, 0))
        self.assertEqual(st.parse_version("3"), (3, 0, 0))

    def test_whitespace_tolerated(self):
        self.assertEqual(st.parse_version("  2.7.1 "), (2, 7, 1))

    def test_junk_returns_none(self):
        self.assertIsNone(st.parse_version("nightly"))
        self.assertIsNone(st.parse_version(""))
        self.assertIsNone(st.parse_version(None))

    def test_more_than_three_parts_uses_first_three(self):
        # Apple erlaubt maximal drei; ein viertes Feld nicht abstuerzen lassen.
        self.assertEqual(st.parse_version("1.2.3.4"), (1, 2, 3))


class IsHigher(unittest.TestCase):
    def test_patch_bump_counts(self):
        self.assertTrue(st.is_higher("3.0.1", "3.0.0"))

    def test_lower_is_rejected(self):
        self.assertFalse(st.is_higher("1.0.0", "3.0.0"))

    def test_equal_is_not_higher(self):
        self.assertFalse(st.is_higher("3.0.0", "3.0.0"))

    def test_numeric_not_lexicographic(self):
        # Der eigentliche Grund fuer diesen Test: "10" < "9" als Text.
        self.assertTrue(st.is_higher("10.0.0", "9.0.0"))
        self.assertTrue(st.is_higher("3.10.0", "3.9.0"))

    def test_unparsable_current_is_not_higher(self):
        self.assertFalse(st.is_higher("nightly", "1.0.0"))


class LatestVersion(unittest.TestCase):
    def test_picks_numerically_largest(self):
        self.assertEqual(st.latest_version(["1.0.0", "3.0.0", "2.5.0"]), "3.0.0")

    def test_ignores_unparsable_entries(self):
        self.assertEqual(st.latest_version(["1.0.0", "beta", "2.0.0"]), "2.0.0")

    def test_empty_returns_none(self):
        self.assertIsNone(st.latest_version([]))
        self.assertIsNone(st.latest_version(["nur-müll"]))

    def test_double_digit_segments(self):
        self.assertEqual(st.latest_version(["3.9.0", "3.10.0"]), "3.10.0")


class CheckDecision(unittest.TestCase):
    """Was der Preflight meldet — das ist die Zeile, die im Log landet."""

    def test_ok_when_higher(self):
        ok, msg = st.check_version("3.0.1", ["1.0.0", "3.0.0"])
        self.assertTrue(ok)
        self.assertIn("3.0.1", msg)

    def test_fails_when_equal(self):
        ok, msg = st.check_version("3.0.0", ["3.0.0"])
        self.assertFalse(ok)
        self.assertIn("3.0.0", msg)

    def test_fails_when_lower_and_names_the_blocker(self):
        ok, msg = st.check_version("1.0.0", ["1.0.0", "3.0.0"])
        self.assertFalse(ok)
        # Die Meldung muss sagen, wogegen verglichen wurde, sonst raetselt
        # man wieder 26 Minuten lang.
        self.assertIn("3.0.0", msg)

    def test_ok_when_app_has_no_versions_yet(self):
        ok, _ = st.check_version("1.0.0", [])
        self.assertTrue(ok)


class ExportCompliance(unittest.TestCase):
    def test_missing_code_is_reported(self):
        ok, msg = st.check_encryption_key(uses_non_exempt=True, code="")
        self.assertFalse(ok)
        self.assertIn("ITSEncryptionExportComplianceCode", msg)

    def test_present_code_passes(self):
        ok, _ = st.check_encryption_key(uses_non_exempt=True, code="abc-123")
        self.assertTrue(ok)

    def test_exempt_app_needs_no_code(self):
        ok, _ = st.check_encryption_key(uses_non_exempt=False, code="")
        self.assertTrue(ok)


if __name__ == "__main__":
    unittest.main(verbosity=2)
