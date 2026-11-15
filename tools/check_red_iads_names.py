"""Check the red group and unit names of a mission against the red IADS naming rule (README, "Red IADS naming").

    python tools/check_red_iads_names.py src/mission/mission

Run it after editing red units in the Mission Editor and extracting the mission. It changes nothing;
exit 0 when every name follows the rule, 1 otherwise.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from mission_names import Entry, read_entries  # noqa: E402

_PREFIX = re.compile(r"^(?P<net>TBS|MAP)-(?P<role>EW|SAM|PD|CC) \S")
_NUMBERED = re.compile(r" #\d+$")


def _checked(e: Entry) -> bool:
    if e.coalition != "red":
        return False
    if e.category == "vehicle":
        return True
    # statics: only the command center and its generator; aircraft: only the A-50s (QRA and veafSpawn are not ours)
    return bool(_PREFIX.match(e.group_name))


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


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    problems = check_names(read_entries(Path(argv[1]).read_text(encoding="utf-8")))
    print(f"{len(problems)} problems", *problems, sep="\n  ")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
