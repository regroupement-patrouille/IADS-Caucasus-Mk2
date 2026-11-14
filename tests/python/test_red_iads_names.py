"""Tests for tools/make_red_iads_names.py."""

import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from make_red_iads_names import (  # noqa: E402
    NameRuleError,
    build_rows,
    escort_role,
    parse_escort_name,
    parse_site_name,
)
from mission_names import Entry, read_entries  # noqa: E402

REAL_ENTRIES = read_entries((ROOT / "src" / "mission" / "mission").read_text(encoding="utf-8"))


class ParseTest(unittest.TestCase):
    def test_parse_site_name(self):
        cases = {
            "SA10 - Kumisi": ("SA-10", "Kumisi"),
            "SA-22 Pantsir - Turquie": ("SA-22", "Turquie"),
            "HQ7 - Dzhvari": ("HQ-7", "Dzhvari"),
            "SA-15 - Dzhvari-4": ("SA-15", "Dzhvari-4"),
            "EWR - Gelen": ("EWR", "Gelen"),
            "SA-11 - Nadezhnaya": ("SA-11", "Nadezhnaya"),
            "IRIS-T - Gelendzhik": ("IRIS-T", "Gelendzhik"),
            "SA19 - Tbilissi-1": ("SA-19", "Tbilissi-1"),
        }
        for old, expected in cases.items():
            self.assertEqual(parse_site_name(old), expected, old)
        self.assertIsNone(parse_site_name("SA-10 - Gudauta - Sol-1"))
        self.assertIsNone(parse_site_name("Random group"))

    def test_parse_escort_name(self):
        cases = {
            "SA2- Maykop - Sol-2": ("SA-2", "Maykop", 2),
            "SA-2 - Shahe- Sol-1": ("SA-2", "Shahe", 1),
            "SA11 Nadezhnaya - Sol-1": ("SA-11", "Nadezhnaya", 1),
            "EWR - Pervo - Sol-3": ("EWR", "Pervo", 3),
            "SA-15 - Dzhvari-4 - Sol-2": ("SA-15", "Dzhvari-4", 2),
        }
        for old, expected in cases.items():
            self.assertEqual(parse_escort_name(old), expected, old)
        self.assertIsNone(parse_escort_name("SA10 - Kumisi"))

    def test_escort_role(self):
        self.assertEqual(escort_role(["CHAP_TorM2"]), "PD")
        self.assertEqual(escort_role(["CHAP_TorM2", "Ural-375"]), "PD")
        self.assertEqual(escort_role(["Dog Ear radar"]), "EW")
        self.assertEqual(escort_role(["Gepard"]), "SAM")
        self.assertEqual(escort_role(["SA-18 Igla-S comm", "SA-18 Igla-S manpad", "Ural-4320T"]), "none")
        with self.assertRaises(NameRuleError):
            escort_role(["T-72B"])


class RealMissionRowsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = build_rows(REAL_ENTRIES)
        cls.groups = {}
        for r in cls.rows:
            cls.groups.setdefault(r["old_group"], []).append(r)

    def group(self, old):
        rows = self.groups[old]
        return rows[0]["new_group"], rows[0]["network"], rows[0]["role"], rows[0]["parent_site"], [r["new_unit"] for r in rows]

    def test_sites(self):
        name, net, role, parent, units = self.group("SA10 - Kumisi")
        self.assertEqual((name, net, role, parent), ("TBS-SAM SA-10 Kumisi", "TBS", "SAM", ""))
        self.assertEqual(units, [f"TBS-SAM SA-10 Kumisi-{i:02d}" for i in range(1, 12)])
        self.assertEqual(self.group("EWR - Gelen")[:3], ("MAP-EW Gelen", "MAP", "EW"))
        self.assertEqual(self.group("EWR - Gelen")[4], ["MAP-EW Gelen"])
        self.assertEqual(self.group("SA-22 - Dzhvari")[:3], ("MAP-SAM SA-22 Dzhvari", "MAP", "SAM"))
        self.assertEqual(self.group("SA-22 Pantsir - Turquie")[0], "MAP-SAM SA-22 Turquie")

    def test_escorts(self):
        self.assertEqual(self.group("SA-10 - Gudauta - Sol-1")[:4], ("MAP-PD SA-10 Gudauta #1", "MAP", "PD", "SA-10 Gudauta"))
        self.assertEqual(self.group("SA-10 - Gudauta - Sol-6")[:3], ("MAP-SAM SA-10 Gudauta #6", "MAP", "SAM"))
        name, net, role, parent, units = self.group("SA-10 - Gudauta - Sol-3")
        self.assertEqual((name, role, units), ("MAP-EW SA-10 Gudauta #3", "EW", ["MAP-EW SA-10 Gudauta #3"]))
        name, net, role, parent, units = self.group("Rapier - Dzhvari - Sol-1")
        self.assertEqual((name, net, role), ("Rapier Dzhvari #1", "", "none"))
        self.assertEqual(units[0], "Rapier Dzhvari #1-01")
        self.assertEqual(self.group("SA2- Maykop - Sol-2")[3], "SA-2 Maykop")
        self.assertEqual(self.group("SA-11 Nadezhnaya - Sol-1")[3], "SA-11 Nadezhnaya")
        self.assertEqual(self.group("EWR - Pervo - Sol-3")[:4], ("MAP-PD Pervo #3", "MAP", "PD", "Pervo"))

    def test_shahe_duplicates_renumbered(self):
        shahe = sorted(self.group(old)[0] for old in ("SA-2 - Shahe - Sol-1", "SA-2 - Shahe- Sol-1"))
        self.assertEqual([n.rsplit("#", 1)[1] for n in shahe], ["1", "2"])

    def test_statics_and_awacs(self):
        self.assertEqual(self.group("CommandCenterRed")[:3], ("TBS-CC Tbilissi", "TBS", "CC"))
        self.assertEqual(self.group("CommandCenterRed")[4], ["TBS-CC Tbilissi"])
        self.assertEqual(self.group("Static Diesel Power Station 5I57A-1")[0], "TBS-CC Tbilissi Power")
        awacs = {old: self.group(old)[:3] for old in ("Awacs #1", "Awacs #2", "Awacs #3", "Awacs #4")}
        self.assertEqual(
            awacs,
            {
                "Awacs #1": ("MAP-EW Awacs Mozdok", "MAP", "EW"),
                "Awacs #2": ("MAP-EW Awacs Turkey", "MAP", "EW"),
                "Awacs #3": ("TBS-EW Awacs Tbilisi", "TBS", "EW"),
                "Awacs #4": ("MAP-EW Awacs Dzhvari", "MAP", "EW"),
            },
        )
        self.assertEqual(self.group("Awacs #3")[4], ["TBS-EW Awacs Tbilisi"])

    def test_scope(self):
        olds = set(self.groups)
        self.assertFalse([o for o in olds if o.startswith(("Qra_", "veafSpawn-"))])
        self.assertNotIn("EWR - Blue", olds)
        red_ground = {e.group_name for e in REAL_ENTRIES if e.coalition == "red" and e.category in ("vehicle", "static")}
        self.assertEqual(red_ground, olds - {"Awacs #1", "Awacs #2", "Awacs #3", "Awacs #4"})

    def test_networks_match_distance(self):
        cc = [e for e in REAL_ENTRIES if e.group_name == "CommandCenterRed"][0]
        by_old = {e.group_name: e for e in REAL_ENTRIES}
        for old, rows in self.groups.items():
            e = by_old[old]
            if e.category == "plane":
                continue
            km = math.hypot(e.x - cc.x, e.y - cc.y) / 1000
            if rows[0]["network"] == "TBS" or rows[0]["new_group"].startswith("Tbilissi"):
                self.assertLess(km, 18, old)
            elif rows[0]["network"] == "MAP":
                self.assertGreater(km, 18, old)

    def test_new_names_unique(self):
        groups = [rows[0]["new_group"] for rows in self.groups.values()]
        units = [r["new_unit"] for r in self.rows]
        self.assertEqual(len(groups), len(set(groups)))
        self.assertEqual(len(units), len(set(units)))


class UnknownNameTest(unittest.TestCase):
    def test_unknown_group_name_is_an_error(self):
        extra = Entry("red", "vehicle", "Random group", ["u1"], ["T-72B"], 0.0, 0.0)
        with self.assertRaises(NameRuleError) as ctx:
            build_rows([*REAL_ENTRIES, extra])
        self.assertIn("Random group", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
