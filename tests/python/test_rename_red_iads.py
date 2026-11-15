"""Tests for tools/rename_red_iads.py."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from mission_names import Entry, read_entries  # noqa: E402
from rename_red_iads import apply_table, check_names  # noqa: E402

FIXTURE = (Path(__file__).parent / "fixtures" / "mini_mission.lua").read_text(encoding="utf-8")


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


class RealMissionTest(unittest.TestCase):
    def test_real_mission_follows_naming_rule(self):
        text = (ROOT / "src" / "mission" / "mission").read_text(encoding="utf-8")
        self.assertEqual(check_names(read_entries(text)), [])


class ApplyTableTest(unittest.TestCase):
    def test_apply_from_csv_on_fixture(self):
        rows = [
            dict(old_group="SA-2 - Poti", new_group="MAP-SAM SA-2 Poti", old_unit="SA-2 - Poti-unit-1", new_unit="MAP-SAM SA-2 Poti-01"),
            dict(old_group="SA-2 - Poti", new_group="MAP-SAM SA-2 Poti", old_unit="SA-2 - Poti-unit-2", new_unit="MAP-SAM SA-2 Poti-02"),
            dict(old_group="CommandCenterRed", new_group="TBS-CC Tbilissi", old_unit="CommandCenterRed", new_unit="TBS-CC Tbilissi"),
            dict(old_group="Awacs #3", new_group="TBS-EW Awacs Tbilisi", old_unit="Awacs #3", new_unit="TBS-EW Awacs Tbilisi"),
        ]
        out = apply_table(FIXTURE, rows)
        entries = read_entries(out)
        names = [(e.coalition, e.group_name, e.unit_names) for e in entries]
        self.assertEqual(
            names,
            [
                ("blue", "SA-2 - Poti-unit-1", ["Blue radar"]),
                ("red", "MAP-SAM SA-2 Poti", ["MAP-SAM SA-2 Poti-01", "MAP-SAM SA-2 Poti-02"]),
                ("red", "TBS-CC Tbilissi", ["TBS-CC Tbilissi"]),
                ("red", "TBS-EW Awacs Tbilisi", ["TBS-EW Awacs Tbilisi"]),
            ],
        )
        self.assertEqual(check_names(entries), [])


if __name__ == "__main__":
    unittest.main()
