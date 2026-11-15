"""Tests for tools/check_red_iads_names.py."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from mission_names import Entry, read_entries  # noqa: E402
from check_red_iads_names import check_names  # noqa: E402

def entry(group, units, coalition="red", category="vehicle"):
    return Entry(coalition, category, group, units, ["x"] * len(units), 0.0, 0.0)


class CheckNamesTest(unittest.TestCase):
    def test_good_names_pass(self):
        entries = [
            entry("MAP-SAM SA-2 Poti", ["MAP-SAM SA-2 Poti-01", "MAP-SAM SA-2 Poti-02"]),
            entry("MAP-PD SA-10 Gudauta #1", ["MAP-PD SA-10 Gudauta #1-01"]),
            entry("MAP-EW Sochi", ["MAP-EW Sochi"]),
            entry("Rapier Dzhvari #1", ["Rapier Dzhvari #1-01", "Rapier Dzhvari #1-02"]),
            entry("TBS-CC Tbilissi", ["TBS-CC Tbilissi"], category="static"),
            entry("TBS-EW Awacs Tbilisi", ["TBS-EW Awacs Tbilisi"], category="plane"),
        ]
        self.assertEqual(check_names(entries), [])

    def test_check_names_flags_bad_unit_suffix(self):
        problems = check_names([entry("MAP-SAM SA-2 Poti", ["foo"])])
        self.assertEqual(len(problems), 1)
        self.assertIn("foo", problems[0])

    def test_check_names_ew_unit_must_equal_group(self):
        problems = check_names([entry("MAP-EW Sochi", ["MAP-EW Sochi-01"])])
        self.assertEqual(len(problems), 1)

    def test_check_names_flags_unprefixed_group_without_number(self):
        self.assertEqual(len(check_names([entry("SA-2 - Poti", ["SA-2 - Poti-01"])])), 1)

    def test_check_names_flags_pd_without_number(self):
        self.assertEqual(len(check_names([entry("MAP-PD SA-10 Gudauta", ["MAP-PD SA-10 Gudauta-01"])])), 1)

    def test_check_names_ignores_blue_qra_veafspawn(self):
        entries = [
            entry("EWR - Blue", ["whatever"], coalition="blue"),
            entry("Qra_Tbilissi-1", ["Qra pilot"], category="plane"),
            entry("veafSpawn-Mig29S-Fox1", ["pilot"], category="plane"),
        ]
        self.assertEqual(check_names(entries), [])

    def test_check_names_ignores_unprefixed_static(self):
        # the Mission Editor names a static's unit like its group: a decoration must not be flagged
        self.assertEqual(check_names([entry("Static Bunker-1", ["Static Bunker-1"], category="static")]), [])

    def test_check_names_checks_prefixed_static(self):
        self.assertEqual(len(check_names([entry("TBS-CC Tbilissi", ["Unit #1"], category="static")])), 1)


class RealMissionTest(unittest.TestCase):
    def test_real_mission_follows_naming_rule(self):
        text = (ROOT / "src" / "mission" / "mission").read_text(encoding="utf-8")
        self.assertEqual(check_names(read_entries(text)), [])


if __name__ == "__main__":
    unittest.main()
