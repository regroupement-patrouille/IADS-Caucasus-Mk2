"""Tests for tools/mission_names.py (run: python -m unittest discover -s tests/python -v)."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from mission_names import RenameError, apply_renames, read_entries  # noqa: E402

FIXTURE = (Path(__file__).parent / "fixtures" / "mini_mission.lua").read_text(encoding="utf-8")
REAL_MISSION = ROOT / "src" / "mission" / "mission"


def red(entry):
    return entry.coalition == "red"


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
        self.assertIn("CommandCenterRed", by_name)
        self.assertIn("Awacs #3", by_name)
        self.assertEqual(len(by_name["SA10 - Kumisi"].unit_names), 11)
        self.assertEqual(by_name["SA10 - Kumisi"].coalition, "red")


class ApplyRenamesTest(unittest.TestCase):
    def test_only_targeted_names_change(self):
        out = apply_renames(
            FIXTURE,
            groups={"SA-2 - Poti": "MAP-SAM SA-2 Poti"},
            units={"SA-2 - Poti-unit-1": "MAP-SAM SA-2 Poti-01", "SA-2 - Poti-unit-2": "MAP-SAM SA-2 Poti-02"},
            scope=red,
        )
        expected = (
            FIXTURE.replace('groupId = 2,\n                name = "SA-2 - Poti"', 'groupId = 2,\n                name = "MAP-SAM SA-2 Poti"')
            .replace('name = "SA-2 - Poti-unit-1",\n                    x = 1000', 'name = "MAP-SAM SA-2 Poti-01",\n                    x = 1000')
            .replace('name = "SA-2 - Poti-unit-2"', 'name = "MAP-SAM SA-2 Poti-02"')
        )
        self.assertNotEqual(expected, FIXTURE)
        self.assertEqual(out, expected)
        # waypoint, blue group, script text and single-quoted note are untouched
        self.assertIn('[1] = {\n                      name = "SA-2 - Poti",', out)
        self.assertIn('name = "SA-2 - Poti-unit-1",\n                units', out)
        self.assertIn('note = \'single quoted name = "SA-2 - Poti"\'', out)

    def test_missing_old_name_refuses(self):
        with self.assertRaises(RenameError) as ctx:
            apply_renames(FIXTURE, groups={"SA-2 - Batumi": "MAP-SAM SA-2 Batumi"}, units={}, scope=red)
        self.assertIn("SA-2 - Batumi", str(ctx.exception))

    def test_out_of_scope_name_refuses(self):
        # the blue group carries this name; it is out of scope, so it counts as missing
        with self.assertRaises(RenameError):
            apply_renames(FIXTURE, groups={"SA-2 - Poti-unit-1": "X"}, units={}, scope=red)

    def test_collision_refuses(self):
        with self.assertRaises(RenameError) as ctx:
            apply_renames(FIXTURE, groups={"SA-2 - Poti": "Awacs #3"}, units={}, scope=red)
        self.assertIn("Awacs #3", str(ctx.exception))

    def test_group_and_unit_may_share_new_name(self):
        # EW sites and statics: the unit carries exactly the group's name
        out = apply_renames(
            FIXTURE,
            groups={"CommandCenterRed": "TBS-CC Tbilissi"},
            units={"CommandCenterRed": "TBS-CC Tbilissi"},
            scope=red,
        )
        cc = [e for e in read_entries(out) if e.category == "static"][0]
        self.assertEqual((cc.group_name, cc.unit_names), ("TBS-CC Tbilissi", ["TBS-CC Tbilissi"]))

    def test_unit_collision_refuses(self):
        with self.assertRaises(RenameError):
            apply_renames(FIXTURE, groups={}, units={"SA-2 - Poti-unit-1": "Awacs #3"}, scope=red)

    def test_swap_is_not_a_collision(self):
        out = apply_renames(
            FIXTURE,
            groups={},
            units={"SA-2 - Poti-unit-1": "SA-2 - Poti-unit-2", "SA-2 - Poti-unit-2": "SA-2 - Poti-unit-1"},
            scope=red,
        )
        poti = [e for e in read_entries(out) if e.group_name == "SA-2 - Poti"][0]
        self.assertEqual(poti.unit_names, ["SA-2 - Poti-unit-2", "SA-2 - Poti-unit-1"])


if __name__ == "__main__":
    unittest.main()
