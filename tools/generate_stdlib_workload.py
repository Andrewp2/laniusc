#!/usr/bin/env python3
"""Generate deterministic native workloads using the actual stdlib generics.

Programs exercise core::vec::Vec<T,N>, core::set::Set<T,N>, Pair, Option and
Result over scalars, records and nested types. Containers use the canonical
borrowed free APIs. Every expected successful mutation unwraps its Result;
intentional invalid replacement checks the error outcome before continuing.
The independent Python model predicts complete checksum stdout.

The optional --record-generics mix contains the historical record-generic probes:
full-record Eq sets, borrowed symbolic-capacity helpers and Queue<T>. The name
identifies the historical mix; support is established by native execution,
not by the old compiler-failure descriptions. Default presets retain their
step weights so workload changes can be attributed to the API migration.

Seeds, areas, leaves, type-pool size and the plain scalar share follow
generate_generic_workload.py. --probes writes small matrix programs with an
expected checksum exit code, while ordinary programs print area totals.
--target-bytes pads a single source to an exact byte size for the existing
import-focused stdlib_gpu_perf.rs measurements. Compile with --stdlib-root stdlib.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import generate_generic_workload as base
from generate_generic_workload import (
    LEAVES_PER_AREA,
    M,
    MASK,
    PLAIN_KINDS,
    Area,
    Leaf,
    Names,
    Record,
    Step,
    Workload,
    build_workload,
    padding_comment,
    record_literal,
)


# kind -> (weight, user library items it needs, needs a record type)
STEP_KINDS: dict[str, tuple[int, tuple[str, ...], bool]] = {
    # core::vec over i32, Option<i32> and Pair<i32, i32>
    "vec_push": (6, ("vec",), False),
    "vec_edit": (5, ("vec",), False),
    "vec_reverse": (3, ("vec",), False),
    "vec_pop": (3, ("vec",), False),
    "vec_option": (3, ("vec", "some_if"), False),
    "vec_pair": (3, ("vec", "pair"), False),
    # core::vec over records
    "vec_get_rec": (4, ("vec",), True),
    # core::set over i32
    "set_insert": (5, ("set",), False),
    "set_remove": (3, ("set",), False),
    # core::pair
    "pair_swap": (4, ("pair",), False),
    "pair_flag": (3, ("pair",), False),
    "pair_rec": (4, ("pair", "score_of"), True),
    "pair_zip": (3, ("pair", "some_if"), False),
    # core::option
    "option_match": (6, ("some_if",), False),
    "option_methods": (5, ("some_if",), False),
    # core::result
    "result_budget": (5, ("result", "checked_budget"), False),
    "result_match": (4, ("result", "ok_if"), True),
    "result_score": (3, ("result", "checked_score"), True),
}
# Historical record-generic workload mix, checked against current native output.
RECORD_KINDS: dict[str, tuple[int, tuple[str, ...], bool]] = {
    # User record equality uses every field through core::cmp::Eq<T>.
    "set_rec": (4, ("set", "record_equality"), True),
    # Borrowed symbolic-capacity helpers and a value-semantic Queue<T>.
    "vec_total": (5, ("vec", "vec_total"), True),
    "vec_heaviest": (4, ("vec", "heaviest"), True),
    "vec_first_odd": (3, ("vec", "first_odd"), True),
    "queue_rec": (3, ("vec", "Queue"), True),
}

# Stdlib modules; "option" is always imported, since Vec and Set return Options.
IMPORTS = ("option", "pair", "result", "set", "vec", "cmp")

USER_LIBRARY = {
    "Score": "trait Score {\n    fn score(self) -> i32;\n}\n",
    "Weight": "trait Weight {\n    fn weight(self) -> i32;\n}\n",
    "score_of": "fn score_of<T>(item: T) -> i32 where T: Score {\n    return item.score();\n}\n",
    "some_if": (
        "fn some_if<T>(present: bool, value: T) -> core::option::Option<T> {\n"
        "    if (present) {\n        return core::option::Some(value);\n    }\n"
        "    return core::option::None();\n}\n"
    ),
    "ok_if": (
        "fn ok_if<T, E>(ok: bool, value: T, error: E) -> core::result::Result<T, E> {\n"
        "    if (ok) {\n        return core::result::Ok(value);\n    }\n"
        "    return core::result::Err(error);\n}\n"
    ),
    "checked_budget": (
        "fn checked_budget(base: i32, extra: i32, limit: i32) -> core::result::Result<i32, i32> {\n"
        "    let total: i32 = base + extra;\n"
        "    if (total > limit) {\n        return core::result::Err(total - limit);\n    }\n"
        "    return core::result::Ok(total);\n}\n"
    ),
    "checked_score": (
        "fn checked_score<T>(item: T, limit: i32) -> core::result::Result<i32, i32> where T: Score {\n"
        "    let score: i32 = item.score();\n"
        "    if (score > limit) {\n        return core::result::Err(score - limit);\n    }\n"
        "    return core::result::Ok(score);\n}\n"
    ),
    "vec_total": (
        "fn vec_total<T, const N: usize>(items: &core::vec::Vec<T, N>, fallback: T, seed: i32) -> i32 where T: Score {\n"
        "    let acc: i32 = seed;\n    let i: i32 = 0;\n"
        "    while (i < core::vec::len(items)) {\n"
        "        let item: T = core::vec::get_or(items, i, fallback);\n"
        f"        acc = (acc + item.score()) {MASK};\n"
        "        i += 1;\n    }\n"
        "    return acc;\n}\n"
    ),
    "heaviest": (
        "// The first of the heaviest items; None for an empty vector.\n"
        "fn heaviest<T, const N: usize>(items: &core::vec::Vec<T, N>, fallback: T) -> core::option::Option<T> where T: Weight {\n"
        "    if (core::vec::is_empty(items)) {\n        return core::option::None();\n    }\n"
        "    let best: T = core::vec::get_or(items, 0, fallback);\n"
        "    let i: i32 = 1;\n"
        "    while (i < core::vec::len(items)) {\n"
        "        let item: T = core::vec::get_or(items, i, fallback);\n"
        "        if (item.weight() > best.weight()) {\n            best = item;\n        }\n"
        "        i += 1;\n    }\n"
        "    return core::option::Some(best);\n}\n"
    ),
    "first_odd": (
        "// The index of the first item with an odd score.\n"
        "fn first_odd<T, const N: usize>(items: &core::vec::Vec<T, N>, fallback: T) -> core::option::Option<i32> where T: Score {\n"
        "    let i: i32 = 0;\n"
        "    while (i < core::vec::len(items)) {\n"
        "        let item: T = core::vec::get_or(items, i, fallback);\n"
        "        if ((item.score() & 1) == 1) {\n            return core::option::Some(i);\n        }\n"
        "        i += 1;\n    }\n"
        "    return core::option::None();\n}\n"
    ),
    "Queue": (
        "// A value-semantic first-in, first-out queue over a stdlib vector.\n"
        "struct Queue<T> {\n    items: core::vec::Vec<T, 4>,\n    served: i32,\n}\n\n"
        "impl<T> Queue<T> {\n"
        "    fn enqueue(self, item: T) -> Queue<T> {\n"
        "        core::result::unwrap(core::vec::try_push(self.items.borrow(), item));\n"
        "        return self;\n    }\n\n"
        "    fn dequeue(self) -> Queue<T> {\n"
        "        core::result::unwrap(core::vec::try_remove(self.items.borrow(), 0));\n"
        "        self.served += 1;\n        return self;\n    }\n\n"
        "    fn size(&self) -> i32 {\n        return core::vec::len(self.items.borrow());\n    }\n\n"
        "    fn front_or(&self, fallback: T) -> T {\n"
        "        return core::vec::get_or(self.items.borrow(), 0, fallback);\n    }\n}\n"
    ),
}
USER_LIBRARY_ORDER = tuple(USER_LIBRARY)

# `--string-helpers N` (0 by default, which leaves the output byte-identical):
# string literals in generic bodies, as messages and labels. The user library
# generics below get one message each, and every area gets N generic audit
# helpers with two labels each, called once from its evaluate function. None
# of them changes a value: each string goes to a diagnostics helper (`expect`,
# `annotate`) that passes its condition or code through. `str` has no methods
# yet, so passing a string to a function is all real code does with it today.
STRING_HELPERS = 0
STRING_PRELUDE = (
    "// Diagnostics sinks: the message documents the check; the value passes through.\n"
    "fn expect(condition: bool, message: str) -> bool {\n    return condition;\n}\n\n"
    "fn annotate(code: i32, context: str, hint: str) -> i32 {\n    return code;\n}\n\n"
)
STRING_LIBRARY = {
    "some_if": (
        "fn some_if<T>(present: bool, value: T) -> core::option::Option<T> {\n"
        "    let reason: str = \"value withheld: present flag not set\";\n"
        "    if (expect(present, reason)) {\n        return core::option::Some(value);\n    }\n"
        "    return core::option::None();\n}\n"
    ),
    "ok_if": (
        "fn ok_if<T, E>(ok: bool, value: T, error: E) -> core::result::Result<T, E> {\n"
        "    let reason: str = \"check failed; returning the caller's error\";\n"
        "    if (expect(ok, reason)) {\n        return core::result::Ok(value);\n    }\n"
        "    return core::result::Err(error);\n}\n"
    ),
    "checked_score": (
        "fn checked_score<T>(item: T, limit: i32) -> core::result::Result<i32, i32> where T: Score {\n"
        "    let score: i32 = item.score();\n"
        "    let message: str = \"score exceeds the configured limit\";\n"
        "    if (expect(score > limit, message)) {\n        return core::result::Err(score - limit);\n    }\n"
        "    return core::result::Ok(score);\n}\n"
    ),
}
STRING_MESSAGES = (
    "index out of range",
    "capacity exhausted; dropping the newest item",
    "unexpected empty container",
    "budget exceeded by the requested amount",
    "duplicate key ignored",
    "value outside the accepted band [0, 4095]",
    "retrying with the fallback value",
    "invalid state: queue drained twice",
    "record weight below threshold",
    "no matching entry for the requested key",
    "overflow while accumulating the checksum",
    "pair components were swapped",
    "configuration missing; using defaults",
    "cannot remove from an empty set",
    "stale handle rejected",
    "expected a non-negative count",
)


def string_label(area: Area, helper: int, slot: int) -> str:
    message = STRING_MESSAGES[(area.index * 7 + helper * 3 + slot) % len(STRING_MESSAGES)]
    return f"{area.name}/audit{helper}: {message}" if slot == 0 else message


def render_string_helpers(area: Area) -> str:
    text = ""
    for helper in range(STRING_HELPERS):
        text += (
            f"// Explains why a value would fail audit {helper}; the code passes through.\n"
            f"fn {area.name}_audit{helper}<T>(value: T, code: i32) -> i32 {{\n"
            f"    let context: str = \"{string_label(area, helper, 0)}\";\n"
            f"    let hint: str = \"{string_label(area, helper, 1)}\";\n"
            "    return annotate(code, context, hint);\n}\n\n"
        )
    return text


def string_helper_calls(area: Area) -> str:
    calls = ""
    for helper in range(STRING_HELPERS):
        argument = "total" if helper % 2 == 0 else "total > 2048"
        calls += f"    total = {area.name}_audit{helper}({argument}, total);\n"
    return calls

# Record field terms: "value" and "x" are the leaf's variables, "a" and "b"
# the step's constants, anything else a literal.
ROWS = (("value", "a", "x"), ("x", "b", "value"), ("a", "b", "x"), ("b", "value", "a"))


# ---------------------------------------------------------------------------
# Models of the stdlib containers (stdlib/core/vec.lani, set.lani)


class Vec:
    """core::vec::Vec<T, N>: value semantics; a failed operation changes nothing."""

    def __init__(self, capacity: int, items: list | None = None):
        self.capacity = capacity
        self.items = list(items or [])
        assert len(self.items) <= capacity

    def copy(self, items: list) -> "Vec":
        return Vec(self.capacity, items)

    def try_push(self, item) -> "Vec":
        return self if len(self.items) == self.capacity else self.copy([*self.items, item])

    def try_pop(self) -> "Vec":
        return self.copy(self.items[:-1]) if self.items else self

    def get(self, index: int):
        return self.items[index] if 0 <= index < len(self.items) else None

    def get_or(self, index: int, fallback):
        found = self.get(index)
        return fallback if found is None else found

    def first(self):
        return self.items[0] if self.items else None

    def last(self):
        return self.items[-1] if self.items else None

    def try_set(self, index: int, item) -> "Vec":
        if not 0 <= index < len(self.items):
            return self
        items = list(self.items)
        items[index] = item
        return self.copy(items)

    def try_insert(self, index: int, item) -> "Vec":
        if not 0 <= index <= len(self.items) or len(self.items) == self.capacity:
            return self
        return self.copy([*self.items[:index], item, *self.items[index:]])

    def try_remove(self, index: int) -> "Vec":
        if not 0 <= index < len(self.items):
            return self
        return self.copy(self.items[:index] + self.items[index + 1:])

    def try_swap(self, left: int, right: int) -> "Vec":
        if not (0 <= left < len(self.items) and 0 <= right < len(self.items)):
            return self
        items = list(self.items)
        items[left], items[right] = items[right], items[left]
        return self.copy(items)

    def reverse(self) -> "Vec":
        return self.copy(self.items[::-1])

    def truncate(self, new_len: int) -> "Vec":
        if new_len < 0 or new_len >= len(self.items):
            return self
        return self.copy(self.items[:new_len])


class Set:
    """Reference insertion-ordered set using complete value equality."""

    def __init__(self, capacity: int, items: list | None = None):
        self.capacity = capacity
        self.items = list(items or [])

    def position_or(self, item, fallback: int) -> int:
        return next((i for i, current in enumerate(self.items) if current == item), fallback)

    def contains(self, item) -> bool:
        return self.position_or(item, -1) >= 0

    def try_insert(self, item) -> "Set":
        if len(self.items) == self.capacity or self.contains(item):
            return self
        return Set(self.capacity, [*self.items, item])

    def try_remove(self, item) -> "Set":
        found = self.position_or(item, -1)
        if found < 0:
            return self
        return Set(self.capacity, self.items[:found] + self.items[found + 1:])

    def is_subset(self, other: "Set") -> bool:
        return all(other.contains(item) for item in self.items)

    def get(self, ordinal: int):
        return self.items[ordinal] if 0 <= ordinal < len(self.items) else None

    def at_or(self, ordinal: int, fallback):
        found = self.get(ordinal)
        return fallback if found is None else found



# ---------------------------------------------------------------------------
# Steps: parameters shared by rendering and evaluation


def bit(c: int, shift: int = 0) -> int:
    return 1 << ((c >> shift) % 12)


def rows(step: Step) -> int:
    """How many records a vector step pushes (1..4)."""
    return 1 + step.c % 4


def term_source(step: Step, term: str) -> str:
    return {"a": str(step.a), "b": str(step.b)}.get(term, term)


def term_value(step: Step, term: str, value: int, x: int) -> int:
    return {"value": value, "x": x, "a": step.a, "b": step.b}[term]


def row_literal(record: Record, step: Step, row: tuple[str, str, str]) -> str:
    return record_literal(Names(), record, *(term_source(step, term) for term in row))


def row_values(record: Record, step: Step, row: tuple[str, str, str], value: int, x: int) -> tuple[int, ...]:
    return tuple(term_value(step, term, value, x) for term in row)[: record.fields]


def blank_literal(record: Record) -> str:
    return record_literal(Names(), record, "0", "0", "0")


def blank_values(record: Record) -> tuple[int, ...]:
    return (0,) * record.fields


def evaluate_step(step: Step, value: int, x: int) -> int:
    a, b, c, r = step.a, step.b, step.c, step.record
    kind = step.kind
    if kind in PLAIN_KINDS:
        return base.evaluate_step(step, value, x)
    if kind == "vec_push":
        v = Vec(8)
        for item in (value, x, a)[: 1 + c % 3]:
            v = v.try_push(item)
        return (v.get_or((c >> 2) % 4, b) + len(v.items)) & M
    if kind == "vec_edit":
        v = Vec(4, [value, x, a, b])
        v = v.try_remove(c % 4)
        v = v.try_insert((c >> 2) % 4, (value + x) & M)
        v = v.try_swap((c >> 4) % 4, (c >> 6) % 4)
        v = v.try_set((c >> 8) % 4, (x ^ a) & M)
        return (v.get_or((c >> 10) % 4, 0) * 2 + v.get_or(0, 0) + len(v.items)) & M
    if kind == "vec_reverse":
        v = Vec(8, [value, x, a]).reverse().truncate(c % 4)
        last = v.last()
        return ((b if last is None else last) + len(v.items)) & M
    if kind == "vec_pop":
        v = Vec(3, [value, x, a])
        for _ in range(c % 4):
            v = v.try_pop()
        result = b if not v.items else (v.last() + v.capacity) & M
        return (result + 1) & M if len(v.items) == v.capacity else result
    if kind == "vec_option":
        v = Vec(4, [x if value & bit(c) else None, a])
        found = v.get_or((c >> 4) % 3, None)
        return (value + (b if found is None else found)) & M
    if kind == "vec_pair":
        pairs = [(value, x), (a, b)][: 1 + c % 2]
        first, last = pairs[0], pairs[-1]
        return (first[0] + last[1] + first[1]) & M
    if kind in ("vec_total", "vec_first_odd"):
        items = [row_values(r, step, row, value, x) for row in ROWS[: rows(step)]]
        if kind == "vec_total":
            acc = value
            for item in items:
                acc = (acc + r.score(item)) & M
            return acc
        odd = next((i for i, item in enumerate(items) if r.score(item) & 1), 5)
        return (value + odd * 3 + x) & M
    if kind == "vec_heaviest":
        v = Vec(4, [row_values(r, step, row, value, x) for row in ROWS]).truncate(c % 5)
        if not v.items:
            return b & M
        best = v.items[0]
        for item in v.items[1:]:
            if r.weight(item) > r.weight(best):
                best = item
        return (best[0] + best[1]) & M
    if kind == "vec_get_rec":
        v = Vec(4, [row_values(r, step, row, value, x) for row in ROWS])
        v = v.try_set((c >> 3) % 5, row_values(r, step, ("x", "a", "b"), value, x))
        found = v.get(c % 6)
        chosen = row_values(r, step, ("b", "x", "value"), value, x) if found is None else found
        return (chosen[0] + chosen[1] * 2) & M
    if kind == "queue_rec":
        items = [row_values(r, step, row, value, x) for row in ROWS[: 1 + c % 3]]
        served = (c >> 2) % 5
        if (c >> 4) & 1:
            items, served = items[1:], served + 1
        front = items[0] if items else blank_values(r)
        return (front[1] + len(items) + served) & M
    if kind == "set_insert":
        s = Set(8)
        for item in (value & 7, x & 7, a & 7, (value + x) & 7):
            s = s.try_insert(item)
        probe = (c >> 2) % 8
        if s.contains(probe):
            return (value + s.position_or(probe, 0) + 1) & M
        return (value + len(s.items) * (c % 7 + 1)) & M
    if kind == "set_remove":
        u = Set(4)
        for item in (x & 3, value & 3, a & 3):
            u = u.try_insert(item)
        v = u.try_remove(c % 4)
        if u.is_subset(v):
            value = (value + v.at_or(0, b)) & M
        found = u.get((c >> 2) % 4)
        return (value + (5 if found is None else found) + len(v.items)) & M
    if kind == "pair_swap":
        return (((x + a) & M) * 2 + value) & M
    if kind == "pair_flag":
        return (value + a) & M if x & bit(c) else (value * 3 + b) & M
    if kind == "pair_rec":
        return (r.score(row_values(r, step, ROWS[0], value, x)) + b) & M
    if kind == "pair_zip":
        left = value if value & bit(c) else None
        right = (x + a) & M if x & bit(c, 4) else None
        pair = (left, right) if left is not None and right is not None else (b, 1)
        return (pair[0] + pair[1]) & M
    if kind == "option_match":
        return (((value + a) & M) + x) & M if value & bit(c) else b & M
    if kind == "option_methods":
        own = x if value & bit(c) else None
        other = a if x & bit(c, 4) else None
        either = own if own is not None else other
        result = (value + either) & M if either is not None else (value ^ b) & M
        if (own is None) == (other is None):  # xor is None
            result = (result + 7) & M
        return result
    if kind == "result_budget":
        total, limit = value + x, a * 2
        return (total - limit + b) & M if total > limit else total & M
    if kind == "result_match":
        if (value & bit(c)) == 0:
            return (value + a) & M
        error = row_values(r, step, ("x", "b", "value"), value, x)
        return (error[0] + error[1]) & M
    if kind == "result_score":
        score = r.score(row_values(r, step, ROWS[0], value, x))
        return (b + (score - a) + x) & M if score > a else (score + x) & M
    if kind == "set_rec":
        s = Set(4)
        first = row_values(r, step, ROWS[0], value, x)
        second = row_values(r, step, ROWS[1], value, x)
        for item in (first, second, first):
            s = s.try_insert(item)
        return (value + len(s.items) + s.position_or(second, 9)) & M
    raise ValueError(f"unknown step kind {kind}")


def evaluate_leaf(leaf: Leaf, x: int) -> int:
    value = (x * leaf.factor + leaf.bias) & M
    for step in leaf.steps:
        value = evaluate_step(step, value, x)
    return value


def expected_stdout(workload: Workload) -> str:
    lines = []
    total = 0
    for area in workload.areas:
        part = 0
        for leaf, salt in zip(area.leaves, area.salts):
            part = (part + evaluate_leaf(leaf, (7 + salt) & M)) & M
        lines.append(str(part))
        total = (total + part) & M
    lines.append(str(total))
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Rendering

VEC = "core::vec::"
SET = "core::set::"
PAIR = "core::pair::"
OPT = "core::option::"
RES = "core::result::"


def zeros(count: int) -> str:
    return "[" + ", ".join("0" for _ in range(count)) + "]"


def repeated(name: str, count: int) -> str:
    return "[" + ", ".join(name for _ in range(count)) + "]"


def render_step(area: Area, step: Step, n: int) -> list[str]:
    a, b, c, r = step.a, step.b, step.c, step.record
    kind = step.kind
    if kind in PLAIN_KINDS:
        return base.render_step(Names(), area, step, n)
    if kind == "vec_push":
        pushes = [f"    {RES}unwrap({VEC}try_push(v{n}.borrow(), {item}));" for item in ("value", "x", str(a))[: 1 + c % 3]]
        return [
            f"    let v{n}: {VEC}Vec<i32, 8> = {VEC}from_storage({zeros(8)});",
            *pushes,
            f"    value = ({VEC}get_or(v{n}.borrow(), {(c >> 2) % 4}, {b}) + {VEC}len(v{n}.borrow())) {MASK};",
        ]
    if kind == "vec_edit":
        return [
            f"    let e{n}: {VEC}Vec<i32, 4> = {VEC}from_array([value, x, {a}, {b}]);",
            f"    {RES}unwrap({VEC}try_remove(e{n}.borrow(), {c % 4}));",
            f"    {RES}unwrap({VEC}try_insert(e{n}.borrow(), {(c >> 2) % 4}, (value + x) {MASK}));",
            f"    {RES}unwrap({VEC}try_swap(e{n}.borrow(), {(c >> 4) % 4}, {(c >> 6) % 4}));",
            f"    {RES}unwrap({VEC}try_set(e{n}.borrow(), {(c >> 8) % 4}, (x ^ {a}) {MASK}));",
            f"    value = ({VEC}get_or(e{n}.borrow(), {(c >> 10) % 4}, 0) * 2 + {VEC}get_or(e{n}.borrow(), 0, 0) + {VEC}len(e{n}.borrow())) {MASK};",
        ]
    if kind == "vec_reverse":
        return [
            f"    let r{n}: {VEC}Vec<i32, 8> = {VEC}from_storage({zeros(8)});",
            f"    {RES}unwrap({VEC}try_push(r{n}.borrow(), value));",
            f"    {RES}unwrap({VEC}try_push(r{n}.borrow(), x));",
            f"    {RES}unwrap({VEC}try_push(r{n}.borrow(), {a}));",
            f"    {VEC}reverse(r{n}.borrow());",
            f"    {RES}unwrap({VEC}truncate(r{n}.borrow(), {c % 4}));",
            f"    value = ({OPT}unwrap_or({VEC}last(r{n}.borrow()), {b}) + {VEC}len(r{n}.borrow())) {MASK};",
        ]
    if kind == "vec_pop":
        return [
            f"    let s{n}: {VEC}Vec<i32, 3> = {VEC}from_array([value, x, {a}]);",
            *[f"    {OPT}unwrap({VEC}pop(s{n}.borrow()));" for _ in range(c % 4)],
            f"    if ({VEC}is_empty(s{n}.borrow())) {{",
            f"        value = {b};",
            "    } else {",
            f"        value = ({OPT}unwrap_or({VEC}last(s{n}.borrow()), 0) + {VEC}capacity(s{n}.borrow())) {MASK};",
            "    }",
            f"    if ({VEC}is_full(s{n}.borrow())) {{",
            f"        value = (value + 1) {MASK};",
            "    }",
        ]
    if kind == "vec_option":
        return [
            f"    let none{n}: {OPT}Option<i32> = {OPT}None();",
            f"    let m{n}: {VEC}Vec<{OPT}Option<i32>, 4> = {VEC}from_storage({repeated(f'none{n}', 4)});",
            f"    {RES}unwrap({VEC}try_push(m{n}.borrow(), some_if((value & {bit(c)}) != 0, x)));",
            f"    {RES}unwrap({VEC}try_push(m{n}.borrow(), {OPT}Some({a})));",
            f"    value = (value + {OPT}unwrap_or({VEC}get_or(m{n}.borrow(), {(c >> 4) % 3}, none{n}), {b})) {MASK};",
        ]
    if kind == "vec_pair":
        pairs = [f"{PAIR}new(value, x)", f"{PAIR}new({a}, {b})"][: 1 + c % 2]
        return [
            f"    let blank{n}: {PAIR}Pair<i32, i32> = {PAIR}new(0, 0);",
            f"    let t{n}: {VEC}Vec<{PAIR}Pair<i32, i32>, 4> = {VEC}from_storage({repeated(f'blank{n}', 4)});",
            *[f"    {RES}unwrap({VEC}try_push(t{n}.borrow(), {pair}));" for pair in pairs],
            f"    let f{n}: {PAIR}Pair<i32, i32> = {OPT}unwrap_or({VEC}first(t{n}.borrow()), blank{n});",
            f"    let l{n}: {PAIR}Pair<i32, i32> = {OPT}unwrap_or({VEC}last(t{n}.borrow()), blank{n});",
            f"    value = ({PAIR}first(f{n}) + {PAIR}second(l{n}) + {PAIR}second(f{n})) {MASK};",
        ]
    if kind in ("vec_total", "vec_first_odd"):
        lines = [
            f"    let blank{n}: {r.name} = {blank_literal(r)};",
            f"    let w{n}: {VEC}Vec<{r.name}, 4> = {VEC}from_storage({repeated(f'blank{n}', 4)});",
            *[f"    {RES}unwrap({VEC}try_push(w{n}.borrow(), {row_literal(r, step, row)}));" for row in ROWS[: rows(step)]],
        ]
        if kind == "vec_total":
            return [*lines, f"    value = vec_total(w{n}.borrow(), blank{n}, value);"]
        return [
            *lines,
            f"    let o{n}: {OPT}Option<i32> = first_odd(w{n}.borrow(), blank{n});",
            f"    value = (value + o{n}.unwrap_or(5) * 3 + x) {MASK};",
        ]
    if kind == "vec_heaviest":
        return [
            f"    let h{n}: {VEC}Vec<{r.name}, 4> = {VEC}from_array([",
            *[f"        {row_literal(r, step, row)}," for row in ROWS],
            "    ]);",
            f"    {RES}unwrap({VEC}truncate(h{n}.borrow(), {c % 5}));",
            f"    let best{n}: {OPT}Option<{r.name}> = heaviest(h{n}.borrow(), {blank_literal(r)});",
            f"    value = match (best{n}) {{",
            f"        {OPT}Some(top{n}) -> top{n}.f0 + top{n}.f1,",
            f"        {OPT}None -> {b},",
            "    };",
            f"    value = value {MASK};",
        ]
    if kind == "vec_get_rec":
        return [
            f"    let g{n}: {VEC}Vec<{r.name}, 4> = {VEC}from_array([",
            *[f"        {row_literal(r, step, row)}," for row in ROWS],
            "    ]);",
            f"    let changed{n}: {RES}Result<{r.name}, {VEC}Error> = {VEC}try_set(g{n}.borrow(), {(c >> 3) % 5}, {row_literal(r, step, ('x', 'a', 'b'))});",
            f"    assert({RES}is_ok(changed{n}) == {str((c >> 3) % 5 < 4).lower()});",
            f"    let o{n}: {OPT}Option<{r.name}> = {VEC}get(g{n}.borrow(), {c % 6});",
            f"    let r{n}: {r.name} = {OPT}unwrap_or(o{n}, {row_literal(r, step, ('b', 'x', 'value'))});",
            f"    value = (r{n}.f0 + r{n}.f1 * 2) {MASK};",
        ]
    if kind == "queue_rec":
        return [
            f"    let blank{n}: {r.name} = {blank_literal(r)};",
            f"    let q{n}: Queue<{r.name}> = Queue {{",
            f"        items: {VEC}from_storage({repeated(f'blank{n}', 4)}),",
            f"        served: {(c >> 2) % 5},",
            "    };",
            *[f"    q{n} = q{n}.enqueue({row_literal(r, step, row)});" for row in ROWS[: 1 + c % 3]],
            *([f"    q{n} = q{n}.dequeue();"] if (c >> 4) & 1 else []),
            f"    let f{n}: {r.name} = q{n}.front_or(blank{n});",
            f"    value = (f{n}.f1 + q{n}.size() + q{n}.served) {MASK};",
        ]
    if kind == "set_insert":
        probe = (c >> 2) % 8
        return [
            f"    let k{n}: {SET}Set<i32, 8> = {SET}from_storage({zeros(8)});",
            *[f"    {RES}unwrap({SET}try_insert(k{n}.borrow(), {item}));" for item in ("value & 7", "x & 7", str(a & 7), "(value + x) & 7")],
            f"    if ({SET}contains(k{n}.borrow(), {probe})) {{",
            f"        value = (value + {SET}position_or(k{n}.borrow(), {probe}, 0) + 1) {MASK};",
            "    } else {",
            f"        value = (value + {SET}len(k{n}.borrow()) * {c % 7 + 1}) {MASK};",
            "    }",
        ]
    if kind == "set_remove":
        return [
            f"    let u{n}: {SET}Set<i32, 4> = {SET}from_storage({zeros(4)});",
            *[f"    {RES}unwrap({SET}try_insert(u{n}.borrow(), {item}));" for item in ("x & 3", "value & 3", str(a & 3))],
            f"    let v{n}: {SET}Set<i32, 4> = u{n};",
            f"    let removed{n}: {OPT}Option<i32> = {SET}remove(v{n}.borrow(), {c % 4});",
            f"    assert({OPT}is_some(removed{n}) == {SET}contains(u{n}.borrow(), {c % 4}));",
            f"    if ({SET}is_subset(u{n}.borrow(), v{n}.borrow())) {{",
            f"        value = (value + {SET}at_or(v{n}.borrow(), 0, {b})) {MASK};",
            "    }",
            f"    value = (value + {OPT}unwrap_or({SET}get(u{n}.borrow(), {(c >> 2) % 4}), 5) + {SET}len(v{n}.borrow())) {MASK};",
        ]
    if kind == "pair_swap":
        return [
            f"    let p{n}: {PAIR}Pair<i32, i32> = {PAIR}new(value, (x + {a}) {MASK});",
            f"    let s{n}: {PAIR}Pair<i32, i32> = {PAIR}swap(p{n});",
            f"    value = ({PAIR}first(s{n}) * 2 + {PAIR}second(s{n})) {MASK};",
        ]
    if kind == "pair_flag":
        return [
            f"    let p{n}: {PAIR}Pair<bool, i32> = {PAIR}new((x & {bit(c)}) != 0, value);",
            f"    if ({PAIR}first(p{n})) {{",
            f"        value = ({PAIR}second(p{n}) + {a}) {MASK};",
            "    } else {",
            f"        value = ({PAIR}second(p{n}) * 3 + {b}) {MASK};",
            "    }",
        ]
    if kind == "pair_rec":
        return [
            f"    let p{n}: {PAIR}Pair<{r.name}, i32> = {PAIR}new({row_literal(r, step, ROWS[0])}, {b});",
            f"    let q{n}: {PAIR}Pair<i32, {r.name}> = {PAIR}swap(p{n});",
            f"    let r{n}: {r.name} = {PAIR}second(q{n});",
            f"    value = (score_of(r{n}) + {PAIR}first(q{n})) {MASK};",
        ]
    if kind == "pair_zip":
        return [
            f"    let l{n}: {OPT}Option<i32> = some_if((value & {bit(c)}) != 0, value);",
            f"    let r{n}: {OPT}Option<i32> = some_if((x & {bit(c, 4)}) != 0, (x + {a}) {MASK});",
            f"    let z{n}: {OPT}Option<{PAIR}Pair<i32, i32>> = {PAIR}zip(l{n}, r{n});",
            f"    let d{n}: {PAIR}Pair<i32, i32> = {OPT}unwrap_or(z{n}, {PAIR}new({b}, 1));",
            f"    value = ({PAIR}first(d{n}) + {PAIR}second(d{n})) {MASK};",
        ]
    if kind == "option_match":
        return [
            f"    let o{n}: {OPT}Option<i32> = some_if((value & {bit(c)}) != 0, (value + {a}) {MASK});",
            f"    value = match (o{n}) {{",
            f"        {OPT}Some(v{n}) -> v{n} + x,",
            f"        {OPT}None -> {b},",
            "    };",
            f"    value = value {MASK};",
        ]
    if kind == "option_methods":
        return [
            f"    let o{n}: {OPT}Option<i32> = some_if((value & {bit(c)}) != 0, x);",
            f"    let f{n}: {OPT}Option<i32> = some_if((x & {bit(c, 4)}) != 0, {a});",
            f"    let g{n}: {OPT}Option<i32> = o{n}.or(f{n});",
            f"    if (g{n}.is_some()) {{",
            f"        value = (value + g{n}.unwrap_or(0)) {MASK};",
            "    } else {",
            f"        value = (value ^ {b}) {MASK};",
            "    }",
            f"    let h{n}: {OPT}Option<i32> = o{n}.xor(f{n});",
            f"    if (h{n}.is_none()) {{",
            f"        value = (value + 7) {MASK};",
            "    }",
        ]
    if kind == "result_budget":
        return [
            f"    let c{n}: {RES}Result<i32, i32> = checked_budget(value, x, {a * 2});",
            f"    if (c{n}.is_ok()) {{",
            f"        value = c{n}.unwrap_or(0) {MASK};",
            "    } else {",
            f"        value = (c{n}.unwrap_err_or(0) + {b}) {MASK};",
            "    }",
        ]
    if kind == "result_match":
        return [
            f"    let o{n}: {RES}Result<i32, {r.name}> = ok_if(",
            f"        (value & {bit(c)}) == 0,",
            f"        (value + {a}) {MASK},",
            f"        {row_literal(r, step, ('x', 'b', 'value'))},",
            "    );",
            f"    value = match (o{n}) {{",
            f"        {RES}Ok(g{n}) -> g{n},",
            f"        {RES}Err(e{n}) -> e{n}.f0 + e{n}.f1,",
            "    };",
            f"    value = value {MASK};",
        ]
    if kind == "result_score":
        return [
            f"    let s{n}: {RES}Result<i32, i32> = checked_score({row_literal(r, step, ROWS[0])}, {a});",
            f"    value = ({RES}unwrap_or(s{n}, {b}) + {RES}unwrap_err_or(s{n}, 0) + x) {MASK};",
        ]
    if kind == "set_rec":
        first, second = row_literal(r, step, ROWS[0]), row_literal(r, step, ROWS[1])
        return [
            f"    let blank{n}: {r.name} = {blank_literal(r)};",
            f"    let k{n}: {SET}Set<{r.name}, 4> = {SET}from_storage({repeated(f'blank{n}', 4)});",
            *[f"    {RES}unwrap({SET}try_insert(k{n}.borrow(), {item}));" for item in (first, second, first)],
            f"    value = (value + {SET}len(k{n}.borrow()) + {SET}position_or(k{n}.borrow(), {second}, 9)) {MASK};",
        ]
    raise ValueError(f"unknown step kind {kind}")


def render_leaf(area: Area, leaf: Leaf) -> str:
    lines = [
        f"fn {leaf.name}(x: i32) -> i32 {{",
        f"    let value: i32 = (x * {leaf.factor} + {leaf.bias}) {MASK};",
    ]
    for n, step in enumerate(leaf.steps):
        lines.extend(render_step(area, step, n))
    lines.extend(["    return value;", "}", ""])
    return "\n".join(lines) + "\n"


def render_record(record: Record, keyed: bool) -> str:
    fields = "".join(f"    f{index}: i32,\n" for index in range(record.fields))
    terms = " + ".join(f"self.f{index} * {coef}" for index, coef in enumerate(record.coefficients))
    text = (
        f"struct {record.name} {{\n{fields}}}\n\n"
        f"impl Score for {record.name} {{\n"
        f"    fn score(self) -> i32 {{\n"
        f"        return ({terms} + {record.bias}) {MASK};\n    }}\n}}\n\n"
        f"impl Weight for {record.name} {{\n"
        f"    fn weight(self) -> i32 {{\n"
        f"        return (self.f0 + self.f1 * {record.weight_factor}) {MASK};\n    }}\n}}\n\n"
    )
    if keyed:
        comparison = " && ".join(f"left.f{i} == right.f{i}" for i in range(record.fields))
        text += (
            f"pub impl core::cmp::Eq<{record.name}> for {record.name} {{\n"
            f"    pub fn eq(left: {record.name}, right: {record.name}) -> bool {{\n"
            f"        return {comparison};\n    }}\n"
            f"    pub fn ne(left: {record.name}, right: {record.name}) -> bool {{\n"
            f"        return !{record.name}::eq(left, right);\n    }}\n}}\n\n"
        )
    return text


def used_kinds(workload: Workload) -> set[str]:
    return {step.kind for leaf in workload.leaves for step in leaf.steps}


def needed_items(workload: Workload) -> set[str]:
    items = {"Score", "Weight", "option"}  # every record implements both traits
    for kind in used_kinds(workload):
        if kind in workload.kinds:
            items.update(workload.kinds[kind][1])
    return items


def render_area_body(area: Area, keyed: bool) -> str:
    text = f"// area {area.name}\n\n"
    text += "".join(render_record(record, keyed) for record in area.records)
    text += "".join(render_leaf(area, leaf) for leaf in area.leaves)
    text += render_string_helpers(area)
    calls = "".join(
        f"    total = (total + {leaf.name}((seed + {salt}) {MASK})) {MASK};\n"
        for leaf, salt in zip(area.leaves, area.salts)
    )
    calls += string_helper_calls(area)
    return text + f"fn {area.name}_evaluate(seed: i32) -> i32 {{\n    let total: i32 = 0;\n{calls}    return total;\n}}\n\n"


def render_single_file(workload: Workload, target_bytes: int | None = None, matrix_probe: bool = False) -> str:
    """One module; a matrix probe returns the checksum modulo 128 and says so on line 1."""
    items = needed_items(workload)
    header = ""
    if matrix_probe:
        header = f"// expect: {int(expected_stdout(workload).split()[-1]) & 127}\n"
    if {"vec", "set"} & items:
        items.add("result")  # every emitted mutation checks its Result
    if "record_equality" in items:
        items.add("cmp")
    imports = "".join(f"import core::{name};\n" for name in IMPORTS if name in items)
    library = "".join(
        (STRING_LIBRARY.get(name, USER_LIBRARY[name]) if STRING_HELPERS else USER_LIBRARY[name]) + "\n"
        for name in USER_LIBRARY_ORDER
        if name in items
    )
    if STRING_HELPERS:
        library = STRING_PRELUDE + library
    prefix = f"{header}module bench::stdlib_generic;\n\n{imports}\n// user library\n\n{library}"
    body = "".join(render_area_body(area, "record_equality" in items) for area in workload.areas)
    suffix = base.render_main(Names(), workload, "total & 127" if matrix_probe else "0")
    source = prefix + body + suffix
    if target_bytes is None:
        return source
    remaining = target_bytes - len(source.encode())
    if remaining < 0:
        raise ValueError("workload exceeds target source size")
    if remaining:
        source = prefix + body + padding_comment(remaining) + suffix
    assert len(source.encode()) == target_bytes
    return source


# ---------------------------------------------------------------------------
# Statistics


def step_specializations(step: Step) -> list[str]:
    """Step-based specialization estimate, excluding complete transitive compiler instantiations."""
    r = step.record.name if step.record else ""
    pii = "Pair<i32,i32>"
    table = {
        "vec_push": ["vec::from_storage<i32,8>", "vec::try_push<i32,8>", "vec::get_or<i32,8>", "vec::len<i32,8>"],
        "vec_edit": ["vec::from_array<i32,4>", "vec::try_remove<i32,4>", "vec::try_insert<i32,4>",
                     "vec::try_swap<i32,4>", "vec::try_set<i32,4>", "vec::get_or<i32,4>", "vec::len<i32,4>"],
        "vec_reverse": ["vec::from_storage<i32,8>", "vec::try_push<i32,8>", "vec::reverse<i32,8>",
                        "vec::truncate<i32,8>", "vec::last<i32,8>", "option::unwrap_or<i32>", "vec::len<i32,8>"],
        "vec_pop": ["vec::from_array<i32,3>", "vec::pop<i32,3>", "vec::is_empty<i32,3>", "vec::last<i32,3>",
                    "option::unwrap_or<i32>", "vec::capacity<i32,3>", "vec::is_full<i32,3>"],
        "vec_option": ["vec::from_storage<Option<i32>,4>", "vec::try_push<Option<i32>,4>",
                       "vec::get_or<Option<i32>,4>", "some_if<i32>", "option::unwrap_or<i32>"],
        "vec_pair": ["pair::new<i32,i32>", f"vec::from_storage<{pii},4>", f"vec::try_push<{pii},4>",
                     f"vec::first<{pii},4>", f"vec::last<{pii},4>", f"option::unwrap_or<{pii}>",
                     "pair::first<i32,i32>", "pair::second<i32,i32>"],
        "vec_total": [f"vec::from_storage<{r},4>", f"vec::try_push<{r},4>", f"vec_total<{r},4>",
                      f"vec::len<{r},4>", f"vec::get_or<{r},4>"],
        "vec_heaviest": [f"vec::from_array<{r},4>", f"vec::truncate<{r},4>", f"heaviest<{r},4>",
                         f"vec::is_empty<{r},4>", f"vec::get_or<{r},4>", f"vec::len<{r},4>"],
        "vec_get_rec": [f"vec::from_array<{r},4>", f"vec::try_set<{r},4>", f"vec::get<{r},4>",
                        f"option::unwrap_or<{r}>"],
        "vec_first_odd": [f"vec::from_storage<{r},4>", f"vec::try_push<{r},4>", f"first_odd<{r},4>",
                          f"vec::len<{r},4>", f"vec::get_or<{r},4>", "Option<i32>::unwrap_or"],
        "queue_rec": [f"vec::from_storage<{r},4>", f"Queue<{r}>::enqueue", f"Queue<{r}>::size",
                      f"Queue<{r}>::front_or", f"vec::try_push<{r},4>", f"vec::len<{r},4>", f"vec::get_or<{r},4>"]
        + ([f"Queue<{r}>::dequeue", f"vec::try_remove<{r},4>"] if (step.c >> 4) & 1 else []),
        "set_insert": ["set::from_storage<i32,8>", "set::try_insert<i32,8>", "set::contains<i32,8>",
                       "set::position_or<i32,8>", "set::len<i32,8>"],
        "set_remove": ["set::from_storage<i32,4>", "set::try_insert<i32,4>", "set::remove<i32,4>",
                       "set::is_subset<i32,4,4>", "set::at_or<i32,4>", "set::get<i32,4>", "set::len<i32,4>",
                       "set::position_or<i32,4>", "option::unwrap_or<i32>"],
        "pair_swap": ["pair::new<i32,i32>", "pair::swap<i32,i32>", "pair::first<i32,i32>", "pair::second<i32,i32>"],
        "pair_flag": ["pair::new<bool,i32>", "pair::first<bool,i32>", "pair::second<bool,i32>"],
        "pair_rec": [f"pair::new<{r},i32>", f"pair::swap<{r},i32>", f"pair::second<i32,{r}>",
                     f"pair::first<i32,{r}>", f"score_of<{r}>"],
        "pair_zip": ["some_if<i32>", "pair::zip<i32,i32>", "pair::zip_right<i32,i32>", "pair::new<i32,i32>",
                     f"option::unwrap_or<{pii}>", "pair::first<i32,i32>", "pair::second<i32,i32>"],
        "option_match": ["some_if<i32>"],
        "option_methods": ["some_if<i32>", "Option<i32>::or", "Option<i32>::is_some", "Option<i32>::unwrap_or",
                           "Option<i32>::xor", "Option<i32>::is_none"],
        "result_budget": ["Result<i32,i32>::is_ok", "Result<i32,i32>::unwrap_or", "Result<i32,i32>::unwrap_err_or"],
        "result_match": [f"ok_if<i32,{r}>"],
        "result_score": [f"checked_score<{r}>", "result::unwrap_or<i32,i32>", "result::unwrap_err_or<i32,i32>"],
        "set_rec": [f"set::from_storage<{r},4>", f"set::try_insert<{r},4>", f"set::position_or<{r},4>",
                    f"set::len<{r},4>"],
    }
    return table.get(step.kind, [])


TYPE_APP = re.compile(r"\b[A-Z][A-Za-z0-9]*<")


def statistics(source: str, workload: Workload) -> dict[str, object]:
    code = re.sub(r"//[^\n]*", "", source)
    lines = [line for line in code.splitlines() if line.strip()]
    kloc = len(lines) / 1000.0
    stdlib_calls = re.findall(r"\bcore::(\w+)::(\w+)\s*\(", code)
    method_calls = re.findall(r"\.\s*(\w+)\s*\(", code)
    bodies = {name for leaf in workload.leaves for step in leaf.steps for name in step_specializations(step)}
    return {
        "nonblank_code_lines": len(lines),
        "physical_lines": source.count("\n"),
        "bytes": len(source.encode()),
        "areas": len(workload.areas),
        "leaf_functions": len(workload.leaves),
        "record_types": sum(len(area.records) for area in workload.areas),
        "stdlib_call_sites": len(stdlib_calls),
        "stdlib_call_sites_by_module": {
            module: sum(1 for found, _ in stdlib_calls if found == module)
            for module in sorted({module for module, _ in stdlib_calls})
        },
        "method_call_sites": len(method_calls),
        "type_applications": len(TYPE_APP.findall(code)),
        "type_applications_per_kloc": round(len(TYPE_APP.findall(code)) / kloc, 1) if kloc else 0.0,
        "generic_body_specializations": len(bodies),
        "stdlib_body_specializations": sum(1 for name in bodies if name.split("::")[0] in IMPORTS
                                           or name.startswith(("Option<", "Result<"))),
        "step_kinds": {kind: sum(1 for leaf in workload.leaves for step in leaf.steps if step.kind == kind)
                       for kind in sorted(used_kinds(workload))},
    }


# ---------------------------------------------------------------------------
# Command line


def kinds_for(record_generics: bool, without: list[str] | None = None) -> dict[str, tuple[int, tuple[str, ...], bool]]:
    kinds = dict(STEP_KINDS)
    if record_generics:
        kinds.update(RECORD_KINDS)
    for kind in without or []:
        if kind not in kinds:
            raise SystemExit(f"unknown step kind {kind!r}; known: {', '.join(sorted(kinds))}")
        del kinds[kind]
    return kinds


def largest_workload_that_fits(seed: int, target_bytes: int, kinds, type_pool: int | None = None) -> int:
    def size(leaf_count: int) -> int:
        return len(render_single_file(build_workload(seed, leaf_count, kinds, type_pool=type_pool)).encode())

    low, high = 1, 2
    while size(high) <= target_bytes:
        low, high = high, high * 2
    while low + 1 < high:
        middle = (low + high) // 2
        if size(middle) <= target_bytes:
            low = middle
        else:
            high = middle
    return low


def write_probes(out: Path, seed: int, kinds) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for kind in sorted(kinds):
        workload = build_workload(seed, 2, kinds, only_kind=kind)
        for leaf_index, leaf in enumerate(workload.areas[0].leaves):
            workload.areas[0].leaves[leaf_index] = Leaf(leaf.name, leaf.area, leaf.factor, leaf.bias, leaf.steps[:3])
        (out / f"s_{kind}.lani").write_text(render_single_file(workload, matrix_probe=True))
    # One program mixing every kind, like a slice of the benchmark.
    workload = build_workload(seed, 2 * LEAVES_PER_AREA, kinds)
    (out / "s_zz_mix.lani").write_text(render_single_file(workload, matrix_probe=True))
    print(f"wrote {len(kinds) + 1} probes to {out}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--layout", choices=("single-file",), default="single-file",
                        help="only single-file output is implemented")
    parser.add_argument("--target-bytes", type=int, default=1_000_000, help="exact program size")
    parser.add_argument("--seed", type=int, default=20)
    parser.add_argument("--leaves", type=int, help="force the number of leaf functions (no padding)")
    parser.add_argument("--record-generics", action="store_true",
                        help="include the historical record-generic workload mix")
    parser.add_argument("--type-pool", type=int, metavar="N",
                        help="use only the first N record types as type arguments (fewer specializations)")
    parser.add_argument("--without", action="append", default=[], metavar="KIND",
                        help="leave out a step kind (repeatable)")
    parser.add_argument("--probes", action="store_true",
                        help="write one small matrix-style probe per step kind into --out")
    parser.add_argument("--matrix-probe", action="store_true",
                        help="single file whose main returns the checksum mod 128, with a `// expect:` line")
    parser.add_argument("--stats", action="store_true", help="print workload statistics")
    parser.add_argument("--string-helpers", type=int, default=0, metavar="N",
                        help="put string literals in generic bodies: messages in the user library "
                             "generics and N generic audit helpers per area (0: none)")
    args = parser.parse_args()
    global STRING_HELPERS
    STRING_HELPERS = args.string_helpers

    kinds = kinds_for(args.record_generics, args.without)
    if args.probes:
        write_probes(args.out, args.seed, kinds)
        return 0
    pool = args.type_pool
    leaf_count = args.leaves or largest_workload_that_fits(args.seed, args.target_bytes, kinds, pool)
    workload = build_workload(args.seed, leaf_count, kinds, type_pool=pool)
    target = None if args.leaves or args.matrix_probe else args.target_bytes
    source = render_single_file(workload, target, args.matrix_probe)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "stdlib_generic.lani").write_text(source)
    stats = statistics(source, workload)
    stdout = expected_stdout(workload)
    manifest = {
        "schema": "lanius.generic-workload.v1",
        "generator": "tools/generate_stdlib_workload.py",
        "layout": "single-file",
        "seed": args.seed,
        "record_generics": args.record_generics,
        "without": sorted(args.without),
        "type_pool": args.type_pool,
        **({"string_helpers": args.string_helpers} if args.string_helpers else {}),
        "entry": "stdlib_generic.lani",
        "source_root": None,
        "expected_stdout": stdout,
        "expected_exit_code": int(stdout.split()[-1]) & 127 if args.matrix_probe else 0,
        "statistics": stats,
        "sources": {
            "stdlib_generic.lani": {
                "bytes": len(source.encode()),
                "sha256": hashlib.sha256(source.encode()).hexdigest(),
            }
        },
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    if args.stats:
        json.dump(stats, sys.stdout, indent=2)
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
