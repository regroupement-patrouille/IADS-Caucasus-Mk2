"""Read the groups and units of a DCS `mission` file (the Lua table the Mission Editor saves).

`read_entries` walks `mission.coalition.<side>.country[i].<category>.group[j]` and returns each group's
name, unit names and unit types. Standard library only.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


class LuaSyntaxError(Exception):
    """The file is not the Lua table subset this reader understands."""


@dataclass
class Entry:
    coalition: str
    category: str
    group_name: str
    unit_names: list[str]
    unit_types: list[str]
    x: float
    y: float


# ── Reader ────────────────────────────────────────────────────────────────────

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}
_NUMBER = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)")
_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


class _Parser:
    def __init__(self, text: str):
        self.t = text
        self.i = 0

    def error(self, what: str):
        line = self.t.count("\n", 0, self.i) + 1
        raise LuaSyntaxError(f"line {line}: {what}")

    def skip(self):
        t, n = self.t, len(self.t)
        while self.i < n:
            c = t[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif t.startswith("--", self.i):
                end = t.find("\n", self.i)
                self.i = n if end < 0 else end + 1
            else:
                return

    def expect(self, s: str):
        self.skip()
        if not self.t.startswith(s, self.i):
            self.error(f"expected {s!r}")
        self.i += len(s)

    def string(self) -> str:
        quote = self.t[self.i]
        start = self.i + 1
        j, out = start, []
        while True:
            if j >= len(self.t):
                self.error("unterminated string")
            c = self.t[j]
            if c == quote:
                break
            if c == "\\":
                nxt = self.t[j + 1]
                if nxt.isdigit():
                    m = re.match(r"\d{1,3}", self.t[j + 1 :])
                    out.append(chr(int(m.group())))
                    j += 1 + len(m.group())
                    continue
                out.append(_ESCAPES.get(nxt, nxt))
                j += 2
                continue
            out.append(c)
            j += 1
        self.i = j + 1
        return "".join(out)

    def value(self):
        self.skip()
        c = self.t[self.i]
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string()
        m = _NUMBER.match(self.t, self.i)
        if m:
            self.i = m.end()
            return float(m.group()) if any(ch in m.group() for ch in ".eE") else int(m.group(), 0)
        m = _NAME.match(self.t, self.i)
        if m and m.group() in ("true", "false", "nil"):
            self.i = m.end()
            return {"true": True, "false": False, "nil": None}[m.group()]
        self.error("unexpected value")

    def table(self) -> dict:
        self.expect("{")
        result, n = {}, 1
        while True:
            self.skip()
            if self.t.startswith("}", self.i):
                self.i += 1
                return result
            if self.t.startswith("[", self.i):
                self.i += 1
                key = self.value()
                self.expect("]")
                self.expect("=")
            else:
                m = _NAME.match(self.t, self.i)
                save = self.i
                if m:
                    self.i = m.end()
                    self.skip()
                    if self.t.startswith("=", self.i) and not self.t.startswith("==", self.i):
                        self.i += 1
                        key = m.group()
                    else:
                        self.i, key = save, None
                else:
                    key = None
                if key is None:
                    key, n = n, n + 1
            result[str(key) if isinstance(key, str) else key] = self.value()
            self.skip()
            if self.t.startswith(",", self.i) or self.t.startswith(";", self.i):
                self.i += 1


def _parse_mission(text: str) -> dict:
    p = _Parser(text)
    p.skip()
    m = _NAME.match(text, p.i)
    if not m or m.group() != "mission":
        p.error("expected 'mission ='")
    p.i = m.end()
    p.expect("=")
    return p.table()


def _ordered(table) -> list:
    if not isinstance(table, dict):
        return []
    return [table[k] for k in sorted(k for k in table if isinstance(k, int))]


def read_entries(text: str) -> list[Entry]:
    """Every group of every coalition, in file order of coalition key, country and category."""
    mission = _parse_mission(text)
    entries = []
    for side, coal in (mission.get("coalition") or {}).items():
        for country in _ordered((coal or {}).get("country")):
            for category, block in country.items():
                if not isinstance(block, dict) or "group" not in block:
                    continue
                for group in _ordered(block["group"]):
                    units = _ordered(group.get("units"))
                    gname = group.get("name")
                    if not isinstance(gname, str):
                        continue
                    first = units[0] if units else {}
                    entries.append(
                        Entry(
                            coalition=str(side),
                            category=str(category),
                            group_name=str(gname),
                            unit_names=[str(u.get("name")) for u in units],
                            unit_types=[str(u.get("type")) for u in units],
                            x=float(first.get("x", 0)),
                            y=float(first.get("y", 0)),
                        )
                    )
    return entries

