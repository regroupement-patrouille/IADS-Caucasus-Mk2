"""Tests for tools/mission_names.py (run: python -m unittest discover -s tests/python -v)."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from mission_names import read_entries  # noqa: E402

FIXTURE = (Path(__file__).parent / "fixtures" / "mini_mission.lua").read_text(encoding="utf-8")
REAL_MISSION = ROOT / "src" / "mission" / "mission"


class ReadEntriesTest(unittest.TestCase):
    def test_read_entries(self):
        entries = read_entries(FIXTURE)
        summary = [(e.coalition, e.category, e.group_name, e.unit_names, e.unit_types) for e in entries]
        self.assertEqual(
            summary,
            [
                ("blue", "vehicle", "SA-2 - Poti-unit-1", ["Blue radar"], ["1L13 EWR"]),
                ("red", "vehicle", "SA-2 - Poti", ["SA-2 - Poti-unit-1", "SA-2 - Poti-unit-2"], ["SNR_75V", "S_75M_Volhov"]),
                ("red", "static", "CommandCenterRed", ["CommandCenterRed"], [".Command Center"]),
                ("red", "plane", "Awacs #3", ["Awacs #3"], ["A-50"]),
            ],
        )
        poti = entries[1]
        self.assertEqual((poti.x, poti.y), (1000.0, 2000.0))

    def test_real_mission_parses(self):
        entries = read_entries(REAL_MISSION.read_text(encoding="utf-8"))
        by_name = {e.group_name: e for e in entries}
        self.assertIn("TBS-CC Tbilissi", by_name)
        self.assertIn("TBS-EW Awacs Tbilisi", by_name)
        self.assertEqual(len(by_name["TBS-SAM SA-10 Kumisi"].unit_names), 11)
        self.assertEqual(by_name["TBS-SAM SA-10 Kumisi"].coalition, "red")


if __name__ == "__main__":
    unittest.main()
