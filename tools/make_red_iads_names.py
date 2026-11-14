"""Generate the red IADS rename table from the mission's current names.

    python tools/make_red_iads_names.py src/mission/mission tools/red-iads-names.csv

Rules: docs/superpowers/specs/2026-11-14-red-iads-networks-design.md ("Naming scheme"). Stops with
NameRuleError, writing nothing, when a red ground group or static fits no rule. Standard library only.
"""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from mission_names import Entry, read_entries  # noqa: E402


class NameRuleError(Exception):
    """A name or unit type the rules do not cover."""


TBS_PLACES = {"Tbilissi", "Vaziani", "Kumisi", "Martkobi"}

STATICS = {
    "CommandCenterRed": "TBS-CC Tbilissi",
    "Static Diesel Power Station 5I57A-1": "TBS-CC Tbilissi Power",
}

AWACS = {
    "Awacs #1": ("MAP", "MAP-EW Awacs Mozdok"),
    "Awacs #2": ("MAP", "MAP-EW Awacs Turkey"),
    "Awacs #3": ("TBS", "TBS-EW Awacs Tbilisi"),
    "Awacs #4": ("MAP", "MAP-EW Awacs Dzhvari"),
}

PD_TYPES = {"CHAP_TorM2", "CHAP_PantsirS1", "HEMTT_C-RAM_Phalanx"}
EW_TYPES = {"Dog Ear radar"}
SAM_ESCORT_TYPES = {"2S6 Tunguska", "Gepard", "ZSU-23-4 Shilka", "SA-11 Buk LN 9A310M1"}
OUTSIDE_TYPES = {
    "SA-18 Igla comm",
    "SA-18 Igla manpad",
    "SA-18 Igla-S comm",
    "SA-18 Igla-S manpad",
    "Ural-375",
    "Ural-4320-31",
    "Ural-4320T",
}

FIELDS = ["old_group", "new_group", "network", "role", "parent_site", "old_unit", "new_unit", "unit_type"]

_SITE_PART = re.compile(r"^(?P<sys>SA-?\d+|HQ-?7|IRIS-T|Rapier|EWR)(?: Pantsir)?\s*(?:-\s*)?(?P<place>\S.*?)\s*$")
_ESCORT = re.compile(r"^(?P<site>.+?)\s*-\s*Sol-(?P<n>\d+)\s*$")


def _normalize_system(system: str) -> str:
    m = re.fullmatch(r"SA-?(\d+)", system)
    if m:
        return f"SA-{m.group(1)}"
    if re.fullmatch(r"HQ-?7", system):
        return "HQ-7"
    return system


def _parse_site_part(text: str) -> tuple[str, str] | None:
    m = _SITE_PART.match(text)
    if not m:
        return None
    return _normalize_system(m.group("sys")), m.group("place")


def parse_site_name(old: str) -> tuple[str, str] | None:
    """`(system, place)` of a site's current group name; `system` is `EWR` for an EW site."""
    if _ESCORT.match(old):
        return None
    return _parse_site_part(old)


def parse_escort_name(old: str) -> tuple[str, str, int] | None:
    """`(system, place, sol_number)` of an escort's current group name (`<site> - Sol-N`)."""
    m = _ESCORT.match(old)
    if not m:
        return None
    site = _parse_site_part(m.group("site"))
    if not site:
        return None
    return site[0], site[1], int(m.group("n"))


def escort_role(unit_types: list[str]) -> str:
    """`PD`, `EW`, `SAM` or `none` from an escort's unit types."""
    unknown = sorted(set(unit_types) - PD_TYPES - EW_TYPES - SAM_ESCORT_TYPES - OUTSIDE_TYPES)
    if unknown:
        raise NameRuleError(f"unit types not covered by the escort rules: {', '.join(unknown)}")
    types = set(unit_types)
    if types & PD_TYPES:
        return "PD"
    if types & EW_TYPES:
        return "EW"
    if types & SAM_ESCORT_TYPES:
        return "SAM"
    return "none"


def _site_label(system: str, place: str) -> str:
    return place if system == "EWR" else f"{system} {place}"


def _network(place: str) -> str:
    return "TBS" if re.sub(r"-\d+$", "", place) in TBS_PLACES else "MAP"


def _units(group: str, role: str, entry: Entry) -> list[str]:
    if role in ("EW", "CC"):
        if len(entry.unit_names) != 1:
            raise NameRuleError(f"{entry.group_name!r}: role {role} needs exactly one unit, has {len(entry.unit_names)}")
        return [group]
    return [f"{group}-{i:02d}" for i in range(1, len(entry.unit_names) + 1)]


def _rows(entry: Entry, new_group: str, network: str, role: str, parent: str) -> list[dict]:
    return [
        dict(
            old_group=entry.group_name,
            new_group=new_group,
            network=network,
            role=role,
            parent_site=parent,
            old_unit=old_unit,
            new_unit=new_unit,
            unit_type=unit_type,
        )
        for old_unit, new_unit, unit_type in zip(entry.unit_names, _units(new_group, role, entry), entry.unit_types)
    ]


def build_rows(entries: list[Entry]) -> list[dict]:
    """One row per unit of every red ground group, red static and A-50 group."""
    problems: list[str] = []
    rows: list[dict] = []
    sites: dict[tuple[str, str], str] = {}  # (system, place) -> network
    escorts: dict[tuple[str, str], list[tuple[int, str, Entry]]] = {}

    for e in entries:
        if e.coalition != "red":
            continue
        if e.category == "plane" and e.group_name in AWACS:
            net, new = AWACS[e.group_name]
            rows += _rows(e, new, net, "EW", "")
        elif e.category == "static":
            if e.group_name not in STATICS:
                problems.append(f"red static {e.group_name!r} has no rule")
                continue
            rows += _rows(e, STATICS[e.group_name], "TBS", "CC", "")
        elif e.category == "vehicle":
            escort = parse_escort_name(e.group_name)
            site = parse_site_name(e.group_name)
            if escort:
                escorts.setdefault(escort[:2], []).append((escort[2], e.group_name, e))
            elif site:
                net = _network(site[1])
                role = "EW" if site[0] == "EWR" else "SAM"
                sites[site] = net
                try:
                    rows += _rows(e, f"{net}-{role} {_site_label(*site)}", net, role, "")
                except NameRuleError as err:
                    problems.append(str(err))
            else:
                problems.append(f"red group {e.group_name!r} matches no site or escort name")

    for key, members in escorts.items():
        if key not in sites:
            problems += [f"escort {old!r} has no parent site {_site_label(*key)!r}" for _, old, _ in members]
            continue
        net, label = sites[key], _site_label(*key)
        for n, (_, old, e) in enumerate(sorted(members, key=lambda m: (m[0], m[1])), start=1):
            try:
                role = escort_role(e.unit_types)
                if role == "none":
                    rows += _rows(e, f"{label} #{n}", "", "none", label)
                else:
                    rows += _rows(e, f"{net}-{role} {label} #{n}", net, role, label)
            except NameRuleError as err:
                problems.append(f"{old!r}: {err}")

    if problems:
        raise NameRuleError("\n".join(problems))
    return rows


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    mission, out = Path(argv[1]), Path(argv[2])
    try:
        rows = build_rows(read_entries(mission.read_text(encoding="utf-8")))
    except NameRuleError as err:
        print(f"Not written, rules do not cover:\n{err}", file=sys.stderr)
        return 1
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"{out}: {len(rows)} units in {len({r['old_group'] for r in rows})} groups")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
