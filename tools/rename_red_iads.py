"""Apply the red IADS rename table to the mission, or check its names against the naming rule.

    python tools/rename_red_iads.py src/mission/mission tools/red-iads-names.csv           # rename
    python tools/rename_red_iads.py src/mission/mission tools/red-iads-names.csv --check   # check only

The file is written only if every rename applies and the result passes the check. Run `--check` after
editing red units in the Mission Editor. Rules: docs/superpowers/specs/2026-11-14-red-iads-networks-design.md.
"""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from mission_names import Entry, RenameError, apply_renames, read_entries  # noqa: E402

_PREFIX = re.compile(r"^(?P<net>TBS|MAP)-(?P<role>EW|SAM|PD|CC) \S")
_NUMBERED = re.compile(r" #\d+$")


def _checked(e: Entry) -> bool:
    if e.coalition != "red":
        return False
    if e.category in ("vehicle", "static"):
        return True
    return bool(_PREFIX.match(e.group_name))  # the A-50s; QRA and veafSpawn aircraft are not ours


def check_names(entries: list[Entry]) -> list[str]:
    """Problems against the naming rule, one line each; empty when every red name follows it."""
    problems = []
    for e in filter(_checked, entries):
        m = _PREFIX.match(e.group_name)
        role = m.group("role") if m else None
        if (role in (None, "PD")) and not _NUMBERED.search(e.group_name):
            problems.append(f"{e.group_name!r}: {'a PD' if role else 'an unprefixed group'} must end with ' #<n>'")
        if role in ("EW", "CC"):
            expected = [e.group_name]
        else:
            expected = [f"{e.group_name}-{i:02d}" for i in range(1, len(e.unit_names) + 1)]
        if e.unit_names != expected:
            wrong = [u for u, x in zip(e.unit_names, expected) if u != x] or e.unit_names
            problems.append(f"{e.group_name!r}: unit names {wrong} should be {expected}")
    return problems


def apply_table(text: str, rows: list[dict]) -> str:
    """Rename the groups and units the table lists (red side only); raises RenameError."""
    groups = {r["old_group"]: r["new_group"] for r in rows}
    units = {r["old_unit"]: r["new_unit"] for r in rows}

    def scope(e: Entry) -> bool:
        return e.coalition == "red" and (e.category in ("vehicle", "static") or e.group_name in groups)

    return apply_renames(text, groups=groups, units=units, scope=scope)


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if a != "--check"]
    if len(args) != 2:
        print(__doc__)
        return 2
    mission, table = Path(args[0]), Path(args[1])
    raw = mission.read_bytes()
    text = raw.decode("utf-8")

    if "--check" not in argv:
        with table.open(newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        try:
            new_text = apply_table(text, rows)
        except RenameError as err:
            print(f"Not renamed: {err}", file=sys.stderr)
            return 1
        problems = check_names(read_entries(new_text))
        if problems:
            print("Not renamed, the result would break the naming rule:", *problems, sep="\n  ", file=sys.stderr)
            return 1
        mission.write_bytes(new_text.encode("utf-8"))
        print(f"{mission}: renamed {len({r['old_group'] for r in rows})} groups, {len(rows)} units")
        text = new_text

    problems = check_names(read_entries(text))
    print(f"{len(problems)} problems", *problems, sep="\n  ")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
