"""Read and rename group and unit names in a DCS `mission` file (the Lua table the Mission Editor saves).

Only the `name` of groups and of their units is ever touched: the path
`mission.coalition.<side>.country[i].<category>.group[j].name` and `...units[k].name`. Waypoint names,
script text and everything else stay byte-identical. Standard library only.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Callable


class RenameError(Exception):
    """A rename was refused; the text was not changed."""


class LuaSyntaxError(Exception):
    """The file is not the Lua table subset this reader understands."""


@dataclass
class NameSpan:
    """The content of a string literal: text[start:end] is the raw (still escaped) content."""

    start: int
    end: int
    value: str


@dataclass
class Entry:
    coalition: str
    category: str
    group_name: str
    unit_names: list[str]
    unit_types: list[str]
    x: float
    y: float
    group_span: NameSpan = field(repr=False, compare=False, default=None)
    unit_spans: list[NameSpan] = field(repr=False, compare=False, default_factory=list)


# ── Reader ────────────────────────────────────────────────────────────────────

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}
_NUMBER = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)")
_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


class _Str(str):
    """A decoded string that remembers where its literal sits in the text."""

    span: NameSpan


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

    def string(self) -> _Str:
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
        s = _Str("".join(out))
        s.span = NameSpan(start, j, str(s))
        self.i = j + 1
        return s

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
                    if not isinstance(gname, _Str):
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
                            group_span=gname.span,
                            unit_spans=[u["name"].span for u in units if isinstance(u.get("name"), _Str)],
                        )
                    )
    return entries


# ── Renamer ───────────────────────────────────────────────────────────────────


def _encode(name: str) -> str:
    return name.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def apply_renames(text: str, groups: dict[str, str], units: dict[str, str], scope: Callable[[Entry], bool]) -> str:
    """Rename groups and units of the entries in `scope`; return the new text.

    Raises RenameError, changing nothing, when an old name is not found exactly once among the names
    in scope, or when a new name would equal a name that remains in the file after the renames.
    """
    entries = read_entries(text)
    in_scope = [e for e in entries if scope(e)]

    found: dict[tuple[str, str], list[NameSpan]] = {}
    for e in in_scope:
        found.setdefault(("group", e.group_name), []).append(e.group_span)
        for uname, span in zip(e.unit_names, e.unit_spans):
            found.setdefault(("unit", uname), []).append(span)

    problems = []
    edits: list[tuple[NameSpan, str]] = []
    for kind, mapping in (("group", groups), ("unit", units)):
        for old, new in mapping.items():
            spans = found.get((kind, old), [])
            if len(spans) != 1:
                problems.append(f"{kind} {old!r}: found {len(spans)} times in scope (expected 1)")
            else:
                edits.append((spans[0], new))

    # DCS keeps group names and unit names apart: a group and a unit may share a name (EW sites,
    # statics), two groups or two units may not.
    remaining = {"group": set(), "unit": set()}
    for e in entries:
        if not (scope(e) and e.group_name in groups):
            remaining["group"].add(e.group_name)
        for uname in e.unit_names:
            if not (scope(e) and uname in units):
                remaining["unit"].add(uname)
    for kind, mapping in (("group", groups), ("unit", units)):
        new_names = list(mapping.values())
        for new in new_names:
            if new in remaining[kind]:
                problems.append(f"new {kind} name {new!r} collides with an existing {kind} name")
        for new in sorted({n for n in new_names if new_names.count(n) > 1}):
            problems.append(f"new {kind} name {new!r} is given more than once")

    if problems:
        raise RenameError("; ".join(problems))

    out = text
    for span, new in sorted(edits, key=lambda e: e[0].start, reverse=True):
        out = out[: span.start] + _encode(new) + out[span.end :]
    return out
