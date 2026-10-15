#!/usr/bin/env python3
"""Generate a deterministic, generics-heavy Lanius benchmark program.

The program looks like a small standard library plus user code that leans on
it: generic containers (Box<T>, Pair<A, B>, fixed-capacity Stack<T>,
Buffer<T, const N>, View<T> over slices), an Option-like Maybe<T> and a
Result-like Outcome<T, E>, generic functions with and without trait bounds,
traits implemented by every generated record type, generic methods
(`impl<T> Stack<T>`, `impl<T, const N: usize> Wrap<[T; N]>`), a generic trait
implemented for a generic struct (`impl<T> Get<T> for Slot<T>`), nested
instantiations such as `Pair<Box<i32>, Maybe<[i32; 4]>>`, and slices.

Every value is an i32 kept in [0, 4095] by masking, so the generator evaluates
the whole program in Python and knows its exact stdout: one checksum line per
area, then the total. `main` returns 0. A miscompile changes a checksum and
points at the area whose functions went wrong.

Layout
------
* `single-file`: one module, `generic.lani`, padded with a trailing comment to
  exactly `--target-bytes` (like tools/generate_compiler_stress.py).
* `project`: `lanius/main.lani` plus `lanius/src/gen/lib.lani` (the library)
  and one module per area under `lanius/src/gen/`, compiled with
  `--source-root lanius/src`. Library items are reached through qualified
  paths (`gen::lib::Box<T>`), as stdlib items are. Area modules implement the
  library's traits for their records (`pub impl gen::lib::Score for Rec`), as
  user code implements stdlib traits; the compiler rejects that today (LNC0007
  on the trait path, see tests/fixtures/generics_backlog/README.md), so the
  project presets fail until cross-module trait impls work.

Mix and calibration
-------------------
Calibration corpora (measured 2026-10-14 by regex over nonblank code lines,
comments and strings stripped):
* stdlib-like: Rust core option/result/cmp/slice/array, alloc vec, arrayvec,
  smallvec, hashbrown, indexmap, either (36k lines). 21% of fns declare their
  own type parameters, 87% of impl blocks are generic, 129 type applications
  and 26 where-clauses per KSLOC, 8.5 impls per implemented trait, method
  calls are 50% of calls.
* user: ~/code/game, naga, wgpu-core (116k lines). 8% generic fns, 22%
  generic impls, 59 type applications per KSLOC, 5.7 impls per trait, method
  calls 60% of calls.

The generated program sits between the two, as stdlib-heavy user code does.
Measured on the 1 MB, seed 20 program (`--stats`):
* 28.2k nonblank lines (29.8k physical) in 1,000,000 bytes; the canonical
  single-file-1mb corpus has 31.7k shorter lines;
* 87% of lines are leaf functions, 6% record types with their impls, 4% area
  dispatchers, 2% per-area generic helpers, 1% the shared library. Leaf sizes
  follow tools/typical_project_profile.json's step bands (65% 1-3 steps, 25%
  4-8, 8% 9-20, 2% 21-55): median 16 lines, p90 46, p99 121;
* 30% of steps are plain scalar arithmetic like the canonical benchmark; 70%
  go through the generic library, weighted towards the common stdlib shapes
  (Box/Pair/Option/Result/Stack/slices first, then methods of generic types,
  nested applications, trait bounds and const-length arrays); see STEP_KINDS;
* 114 type applications per KSLOC (corpora: 59 user, 129 stdlib-like); 66% of
  free-function call sites call generic functions; method calls are 25% of
  calls (the Lanius library leans on free functions, as stdlib/core does);
* each area declares 4 record types (2 or 3 i32 fields), each with a `Score`
  impl, a `Weight` impl and an inherent `borrow(&self)`, so traits have ~88
  impls each; one generic `Ledger<T>` with an `impl<T>` block; and one bounded
  generic fold `fold<T>(items: [T], ...) where T: Score`;
* 80% of record steps use the area's own records, 20% another area's: 808
  distinct concrete type applications and ~2,260 concrete generic bodies
  (functions and methods per type-argument list).
`--type-pool N` draws record type arguments from the first N record types
only (N = 4: 59 applications, ~160 bodies), which fits the compiler's current
256-body specialization limit (LNC0017) without changing the mix.

Only shapes that tests/fixtures/generics_matrix shows working, and
combinations of them validated with `--probes` on the GPU, are emitted by
default. `--backlog` adds steps that need features that do not work yet:
methods of generic impls called through a trait bound
(tests/fixtures/generics_backlog/b00), conditional marker impls (matrix p27)
and const-generic structs (matrix p24 shape). Match arms are kept to `name`
or `a + b`, because an arm like `(v ^ x) & 4095` is a syntax error today.

`--probes DIR` writes one small program per step kind, plus one mixing all of
them, with a matrix-style `// expect: N` first line (N is the checksum modulo
128, returned from main), for `tools/generics_matrix.py --probes DIR`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


M = 4095
MASK = f"& {M}"
AREAS = (
    "accounts", "billing", "catalog", "checkout", "delivery", "inventory",
    "metrics", "orders", "pricing", "routing", "scheduling", "sessions",
    "storage", "telemetry", "validation",
)
ROLES = ("policy", "processor", "service", "planner", "tracker", "summary")
LEAVES_PER_AREA = 48
RECORDS_PER_AREA = 4
STEP_BANDS = ((6500, 1, 3), (9000, 4, 8), (9800, 9, 20), (10000, 21, 55))
PLAIN_SHARE = 30  # percent of steps that are plain scalar arithmetic

# kind -> (weight, library items it needs, needs a record type)
STEP_KINDS: dict[str, tuple[int, tuple[str, ...], bool]] = {
    "box_i32": (6, ("Box", "boxed", "unbox"), False),
    "box_rec": (6, ("Box", "boxed", "unbox"), True),
    "pair_rec_i32": (6, ("Pair", "make_pair", "pair_first", "pair_second"), True),
    "pair_i32_bool": (4, ("Pair", "make_pair", "pair_first", "pair_second"), False),
    "pair_rec_rec": (4, ("Pair", "make_pair", "pair_first", "pair_second", "Score", "score_of"), True),
    "maybe_i32_match": (6, ("Maybe", "just"), False),
    "maybe_rec": (6, ("Maybe", "maybe_if", "unwrap_or"), True),
    "outcome_rec": (5, ("Outcome", "good_if"), True),
    "stack_i32": (5, ("Stack", "Stack_impl"), False),
    "stack_rec": (4, ("Stack", "Stack_impl"), True),
    "slice_i32": (5, ("get", "swap", "count"), False),
    "slice_rec": (4, ("get", "swap"), True),
    "trait_total": (5, ("Score", "total"), True),
    "heavier": (3, ("Weight", "heavier"), True),
    "nested_box_maybe_arr": (3, ("Pair", "Box", "unbox", "Maybe", "unwrap_or"), False),
    "nested_box_pair": (3, ("Pair", "make_pair", "Box", "boxed", "unbox"), True),
    "nested_maybe_box": (3, ("Maybe", "just", "Box", "boxed"), True),
    "wrap_const": (3, ("Wrap", "Wrap_impl"), False),
    "repeat_rec": (3, ("repeat3",), True),
    "view_i32": (3, ("View", "view_first"), False),
    "pick_ref": (3, ("pick",), True),
    "slot_get": (4, ("Get", "Slot", "Slot_impl"), True),
    "cell_get": (4, ("Cell", "Cell_impl"), False),
    "choose": (4, ("choose",), False),
    "fold": (4, ("Score",), True),
    "ledger": (4, ("Score", "score_of"), True),
    "maybe_method": (6, ("Maybe", "maybe_if", "Maybe_impl"), True),
    "stack_push": (4, ("Stack", "Stack_impl"), False),
    "score_i32": (3, ("Score", "Score_i32", "total"), False),
    "twice_box": (3, ("Box", "boxed", "twice_box"), True),
    "pair_methods": (5, ("Pair", "Pair_impl"), True),
}
# Steps that need features the matrix does not pass yet (generics_backlog).
BACKLOG_KINDS: dict[str, tuple[int, tuple[str, ...], bool]] = {
    "twice_bound": (3, ("Score", "score_of", "Twice", "Twice_impl"), True),
    # Conditional marker impls over generic structs and const-length arrays
    # (generics_matrix p27, failing on the code-38 bug).
    "marker_bound": (3, ("Cell", "Mark", "keep"), False),
    # Const-generic structs (generics_matrix p24 shape): the semantic
    # interface export fails with status 0x80 on the 2026-10-14 build.
    "const_buffer": (4, ("Buffer", "keep_length", "buffer_first"), False),
    "const_buffer_rec": (2, ("Buffer", "buffer_first"), True),
}
PLAIN_KINDS = ("add", "mul", "xor", "branch")

LIBRARY = {
    "Box": "struct Box<T> {\n    value: T,\n}\n",
    "boxed": "fn boxed<T>(value: T) -> Box<T> {\n    return Box { value: value };\n}\n",
    "unbox": "fn unbox<T>(b: Box<T>) -> T {\n    return b.value;\n}\n",
    "twice_box": "fn twice_box<T>(value: T) -> Box<Box<T>> {\n    return boxed(boxed(value));\n}\n",
    "Pair": "struct Pair<A, B> {\n    first: A,\n    second: B,\n}\n",
    "make_pair": "fn make_pair<A, B>(a: A, b: B) -> Pair<A, B> {\n    return Pair { first: a, second: b };\n}\n",
    "Pair_impl": (
        "impl<A, B> Pair<A, B> {\n"
        "    fn swapped(self) -> Pair<B, A> {\n"
        "        return Pair { first: self.second, second: self.first };\n    }\n\n"
        "    fn left(&self) -> A {\n        return self.first;\n    }\n}\n"
    ),
    "pair_first": "fn pair_first<A, B>(p: Pair<A, B>) -> A {\n    return p.first;\n}\n",
    "pair_second": "fn pair_second<A, B>(p: Pair<A, B>) -> B {\n    return p.second;\n}\n",
    "Maybe": "enum Maybe<T> {\n    Nothing,\n    Just(T),\n}\n",
    "just": "fn just<T>(value: T) -> Maybe<T> {\n    return Just(value);\n}\n",
    "maybe_if": (
        "fn maybe_if<T>(present: bool, value: T) -> Maybe<T> {\n"
        "    if (present) {\n        return Just(value);\n    }\n"
        "    return Nothing;\n}\n"
    ),
    "unwrap_or": (
        "fn unwrap_or<T>(m: Maybe<T>, fallback: T) -> T {\n"
        "    return match (m) { Nothing => fallback, Just(v) => v };\n}\n"
    ),
    "Maybe_impl": (
        "impl<T> Maybe<T> {\n"
        "    fn or_value(self, fallback: T) -> T {\n"
        "        return match (self) { Nothing => fallback, Just(v) => v };\n    }\n\n"
        "    fn is_just(&self) -> bool {\n"
        "        return match (self) { Nothing => false, Just(v) => true };\n    }\n}\n"
    ),
    "Outcome": "enum Outcome<T, E> {\n    Good(T),\n    Bad(E),\n}\n",
    "good_if": (
        "fn good_if<T, E>(ok: bool, value: T, error: E) -> Outcome<T, E> {\n"
        "    if (ok) {\n        return Good(value);\n    }\n"
        "    return Bad(error);\n}\n"
    ),
    "Stack": "struct Stack<T> {\n    items: [T; 4],\n    len: i32,\n}\n",
    "Stack_impl": (
        "impl<T> Stack<T> {\n"
        "    fn top(&self) -> T {\n        return self.items[self.len - 1];\n    }\n\n"
        "    fn at(&self, index: i32) -> T {\n        return self.items[index];\n    }\n\n"
        "    fn size(&self) -> i32 {\n        return self.len;\n    }\n\n"
        "    fn pushed(self, value: T) -> Stack<T> {\n"
        "        let items: [T; 4] = self.items;\n        items[self.len] = value;\n"
        "        return Stack { items: items, len: self.len + 1 };\n    }\n}\n"
    ),
    "get": "fn get<T>(values: [T], index: i32) -> T {\n    return values[index];\n}\n",
    "swap": (
        "fn swap<T>(values: [T], i: i32, j: i32) {\n"
        "    let t: T = values[i];\n    values[i] = values[j];\n    values[j] = t;\n}\n"
    ),
    "count": (
        "fn count<T>(values: [T], len: i32) -> i32 {\n"
        "    let n: i32 = 0;\n    let i: i32 = 0;\n"
        "    while (i < len) {\n        let v: T = values[i];\n        n += 1;\n        i += 1;\n    }\n"
        "    return n;\n}\n"
    ),
    "repeat3": "fn repeat3<T>(value: T) -> [T; 3] {\n    return [value, value, value];\n}\n",
    "pick": "fn pick<T>(value: &T) -> &T {\n    return value;\n}\n",
    "choose": (
        "fn choose<T>(left: T, right: T, first: bool) -> T {\n"
        "    if (first) {\n        return left;\n    }\n    return right;\n}\n"
    ),
    "View": "struct View<T> {\n    items: [T],\n    len: i32,\n}\n",
    "view_first": "fn view_first<T>(v: View<T>) -> T {\n    return v.items[0];\n}\n",
    "Buffer": "struct Buffer<T, const N: usize> {\n    values: [T; N],\n}\n",
    "keep_length": "fn keep_length<T, const M: usize>(value: [T; M]) -> [T; M] {\n    return value;\n}\n",
    "buffer_first": "fn buffer_first<T, const N: usize>(b: Buffer<T, N>) -> T {\n    return b.values[0];\n}\n",
    "Wrap": "struct Wrap<A> {\n    value: A,\n}\n",
    "Wrap_impl": (
        "impl<T, const N: usize> Wrap<[T; N]> {\n"
        "    fn length(&self) -> usize {\n        return N;\n    }\n\n"
        "    fn copy(&self) -> [T; N] {\n        return self.value;\n    }\n}\n"
    ),
    "Cell": "struct Cell<T> {\n    value: T,\n}\n",
    "Cell_impl": "impl<T> Cell<T> {\n    fn get(self) -> T {\n        return self.value;\n    }\n}\n",
    "Get": "trait Get<T> {\n    fn get(self) -> T;\n}\n",
    "Slot": "struct Slot<T> {\n    value: T,\n}\n",
    "Slot_impl": "impl<T> Get<T> for Slot<T> {\n    fn get(self) -> T {\n        return self.value;\n    }\n}\n",
    "Score": "trait Score {\n    fn score(self) -> i32;\n}\n",
    "total": (
        "fn total<T>(a: T, b: T) -> i32 where T: Score {\n"
        f"    return (a.score() + b.score()) {MASK};\n}}\n"
    ),
    "score_of": "fn score_of<T>(value: T) -> i32 where T: Score {\n    return value.score();\n}\n",
    "Score_i32": f"impl Score for i32 {{\n    fn score(self) -> i32 {{\n        return (self * 3 + 1) {MASK};\n    }}\n}}\n",
    "Weight": "trait Weight {\n    fn weight(self) -> i32;\n}\n",
    "heavier": (
        "fn heavier<T>(a: T, b: T) -> T where T: Weight {\n"
        "    if (a.weight() >= b.weight()) {\n        return a;\n    }\n    return b;\n}\n"
    ),
    "Twice": "struct Twice<T> {\n    inner: T,\n}\n",
    "Twice_impl": (
        "impl<T> Score for Twice<T> where T: Score {\n"
        f"    fn score(self) -> i32 {{\n        return (self.inner.score() * 2) {MASK};\n    }}\n}}\n"
    ),
    "Mark": (
        "trait Mark {}\n\n"
        "impl Mark for i32 {}\n\n"
        "impl<T> Mark for Cell<T> where T: Mark {}\n\n"
        "impl<T, const N: usize> Mark for [T; N] where T: Mark {}\n"
    ),
    "keep": "fn keep<T>(value: T) -> T where T: Mark {\n    return value;\n}\n",
}
LIBRARY_ORDER = tuple(LIBRARY)
LIBRARY_TRAITS = ("Score", "Weight", "Get")
LIBRARY_ENUM_VARIANTS = {"Maybe": ("Nothing", "Just"), "Outcome": ("Good", "Bad")}


@dataclass(frozen=True)
class Record:
    name: str
    area: int
    coefficients: tuple[int, ...]  # one per field
    bias: int
    weight_factor: int

    @property
    def fields(self) -> int:
        return len(self.coefficients)

    def score(self, values: tuple[int, ...]) -> int:
        return (sum(c * v for c, v in zip(self.coefficients, values)) + self.bias) & M

    def weight(self, values: tuple[int, ...]) -> int:
        return (values[0] + values[1] * self.weight_factor) & M


@dataclass(frozen=True)
class Step:
    kind: str
    a: int
    b: int
    c: int
    record: Record | None = None
    other: Record | None = None


@dataclass(frozen=True)
class Leaf:
    name: str
    area: int
    factor: int
    bias: int
    steps: tuple[Step, ...]


@dataclass
class Area:
    index: int
    name: str
    records: list[Record]
    leaves: list[Leaf] = field(default_factory=list)
    salts: list[int] = field(default_factory=list)


@dataclass
class Workload:
    seed: int
    areas: list[Area]
    kinds: dict[str, tuple[int, tuple[str, ...], bool]]

    @property
    def leaves(self) -> list[Leaf]:
        return [leaf for area in self.areas for leaf in area.leaves]


def area_name(index: int) -> str:
    return f"{AREAS[index % len(AREAS)]}{index // len(AREAS)}"


def camel(name: str) -> str:
    return re.sub(r"(^|_)([a-z])", lambda m: m.group(2).upper(), name)


def stable_random(*parts: object) -> random.Random:
    digest = hashlib.sha256(":".join(str(part) for part in parts).encode()).digest()
    return random.Random(int.from_bytes(digest[:8], "little"))


def build_area(seed: int, index: int) -> Area:
    rng = stable_random("area", seed, index)
    name = area_name(index)
    records = [
        Record(
            name=f"{camel(name)}Rec{j}",
            area=index,
            coefficients=tuple(rng.randint(1, 7) for _ in range(rng.choice((2, 2, 3)))),
            bias=rng.randint(0, M),
            weight_factor=rng.randint(1, 5),
        )
        for j in range(RECORDS_PER_AREA)
    ]
    return Area(index, name, records)


def build_workload(
    seed: int,
    leaf_count: int,
    kinds: dict[str, tuple[int, tuple[str, ...], bool]],
    only_kind: str | None = None,
    type_pool: int | None = None,
) -> Workload:
    """`type_pool` limits record type arguments to the first N record types."""
    area_count = (leaf_count + LEAVES_PER_AREA - 1) // LEAVES_PER_AREA
    areas = [build_area(seed, index) for index in range(area_count)]
    all_records = [record for area in areas for record in area.records]
    pool_records = all_records[:type_pool] if type_pool else None
    names = sorted(kinds)
    weights = [kinds[name][0] for name in names]
    for leaf_index in range(leaf_count):
        area = areas[leaf_index // LEAVES_PER_AREA]
        rng = stable_random("leaf", seed, leaf_index)
        roll = rng.randrange(10000)
        low, high = next((lo, hi) for limit, lo, hi in STEP_BANDS if roll < limit)
        steps = []
        for position in range(rng.randint(low, high)):
            if only_kind is not None:
                kind = only_kind
            elif rng.randrange(100) < PLAIN_SHARE:
                kind = rng.choice(PLAIN_KINDS)
            else:
                kind = rng.choices(names, weights)[0]
            record = other = None
            if kind not in PLAIN_KINDS and kinds[kind][2]:
                if pool_records:
                    pool = pool_records
                elif rng.randrange(100) < 80 or len(areas) == 1:
                    pool = area.records
                else:
                    pool = rng.choice(areas).records
                index = rng.randrange(len(pool))
                record = pool[index]
                # Pairs of records use the next record type, so each record
                # adds one two-record application rather than len(pool).
                other = pool[(index + 1) % len(pool)]
            a = rng.randint(1, 9) if kind == "mul" else rng.randint(0, M)
            steps.append(Step(kind, a, rng.randint(0, M), rng.randint(0, 1 << 30), record, other))
        role = ROLES[leaf_index % len(ROLES)]
        leaf = Leaf(
            name=f"{area.name}_{role}_{leaf_index}",
            area=area.index,
            factor=rng.randint(1, 9),
            bias=rng.randint(0, M),
            steps=tuple(steps),
        )
        area.leaves.append(leaf)
        area.salts.append(rng.randint(0, M))
    return Workload(seed, areas, kinds)


# ---------------------------------------------------------------------------
# Evaluation (the exact semantics of the rendered program)


def evaluate_step(step: Step, value: int, x: int) -> int:
    a, b, c, r, o = step.a, step.b, step.c, step.record, step.other
    kind = step.kind
    if kind == "add":
        return (value + a + x) & M
    if kind == "mul":
        return (value * a + b) & M
    if kind == "xor":
        return (value ^ a ^ x) & M
    if kind == "branch":
        return (value + (a if value & a else b)) & M
    if kind == "box_i32":
        return (((value + a) & M) ^ x) & M
    if kind == "box_rec":
        return (value + a + x) & M
    if kind == "pair_rec_i32":
        return (x * 3 + a + value) & M
    if kind == "pair_i32_bool":
        bit = 1 << (c % 12)
        return (value + a) & M if x & bit else (value * 3 + b) & M
    if kind == "pair_rec_rec":
        return (r.score(record_values(r, value, a, x)) + x) & M
    if kind == "maybe_i32_match":
        return (((value + a) & M) + x) & M
    if kind == "maybe_rec":
        bit = 1 << (c % 12)
        return (value + a) & M if value & bit else (b + x) & M
    if kind == "outcome_rec":
        bit = 1 << (c % 12)
        return (value + a) & M if (value & bit) == 0 else (x + b) & M
    if kind == "stack_i32":
        items = (value, x, a, b)
        length = 1 + c % 4
        return (items[length - 1] + items[(c >> 2) % length] + length) & M
    if kind == "stack_rec":
        items = ((value, 1), (x, 2), (a, 3), (b, 4))
        length = 1 + c % 4
        top = items[length - 1]
        return (top[0] + top[1] + length) & M
    if kind == "slice_i32":
        items = [value, x, a, b]
        j = 1 + c % 3
        items[0], items[j] = items[j], items[0]
        return (items[(c >> 2) % 4] + 4) & M
    if kind == "slice_rec":
        items = [(value, a), (x, b)]
        items.reverse()
        chosen = items[c % 2]
        return (chosen[0] * 2 + chosen[1]) & M
    if kind == "trait_total":
        left = r.score(record_values(r, value, a, x))
        right = r.score(record_values(r, x, b, value))
        return (((left + right) & M) + value) & M
    if kind == "heavier":
        left = record_values(r, value, a, x)
        right = record_values(r, x, b, value)
        chosen = left if r.weight(left) >= r.weight(right) else right
        return (chosen[0] + chosen[1]) & M
    if kind == "nested_box_maybe_arr":
        return (value + (x, a, b, value)[c % 4]) & M
    if kind == "nested_box_pair":
        return (a + x + value) & M
    if kind == "nested_maybe_box":
        return (value + a) & M
    if kind == "const_buffer":
        n = 2 + c % 4
        values = (value, x, a, b, (a + b) & M)[:n]
        return (values[0] + values[(c >> 2) % n]) & M
    if kind == "const_buffer_rec":
        return (value + a + x) & M
    if kind == "wrap_const":
        n = 2 + c % 3
        values = (value, x, a, b)[:n]
        return (values[0] + values[n - 1] + a) & M
    if kind == "repeat_rec":
        return (value + a + x) & M
    if kind == "view_i32":
        return (value + 3 + a) & M
    if kind == "pick_ref":
        return (value + a + x) & M
    if kind == "slot_get":
        return (value ^ a) & M
    if kind == "cell_get":
        return (((value + a) & M) * 3 + x) & M
    if kind == "choose":
        bit = 1 << (c % 12)
        return value if value & bit else (x + a) & M
    if kind == "fold":
        acc = value
        for values in (record_values(r, value, a, x), record_values(r, x, b, value), record_values(r, a, b, x)):
            acc = (acc + r.score(values)) & M
        return acc
    if kind == "ledger":
        head = record_values(r, value, a, x)
        tail = record_values(r, b, x, value)
        return (head[0] + area_ledger_count(step) + r.score(tail)) & M
    if kind == "twice_bound":
        return (r.score(record_values(r, value, a, x)) * 2) & M
    if kind == "maybe_method":
        bit = 1 << (c % 12)
        return (value + a + 1) & M if value & bit else (b + x) & M
    if kind == "stack_push":
        return (((value + a) & M) + 3 + 2) & M
    if kind == "score_i32":
        return ((((value * 3 + 1) & M) + ((x * 3 + 1) & M)) & M) + a & M
    if kind == "twice_box":
        return (value + a) & M
    if kind == "pair_methods":
        return (((x + b) & M) + a + value) & M
    if kind == "marker_bound":
        return (value + x + a) & M
    raise ValueError(f"unknown step kind {kind}")


def step_specializations(step: Step) -> list[str]:
    """Concrete generic bodies a step needs (functions and methods with type arguments)."""
    r = step.record.name if step.record else ""
    o = step.other.name if step.other else ""
    area = area_name(step.record.area) if step.record else ""
    ledger = f"{camel(area)}Ledger"
    c = step.c
    table = {
        "box_i32": ["boxed<i32>", "unbox<i32>"],
        "box_rec": [f"boxed<{r}>", f"unbox<{r}>"],
        "pair_rec_i32": [f"make_pair<{r},i32>", f"pair_first<{r},i32>", f"pair_second<{r},i32>"],
        "pair_i32_bool": ["make_pair<i32,bool>", "pair_first<i32,bool>", "pair_second<i32,bool>"],
        "pair_rec_rec": [f"make_pair<{r},{o}>", f"pair_first<{r},{o}>", f"pair_second<{r},{o}>", f"score_of<{r}>"],
        "maybe_i32_match": ["just<i32>"],
        "maybe_rec": [f"maybe_if<{r}>", f"unwrap_or<{r}>"],
        "outcome_rec": [f"good_if<i32,{r}>"],
        "stack_i32": ["Stack<i32>::top", "Stack<i32>::at", "Stack<i32>::size"],
        "stack_rec": [f"Stack<{r}>::top", f"Stack<{r}>::size"],
        "slice_i32": ["swap<i32>", "get<i32>", "count<i32>"],
        "slice_rec": [f"swap<{r}>", f"get<{r}>"],
        "trait_total": [f"total<{r}>"],
        "heavier": [f"heavier<{r}>"],
        "nested_box_maybe_arr": ["unwrap_or<[i32;4]>", "unbox<i32>"],
        "nested_box_pair": [f"make_pair<{r},i32>", f"boxed<Pair<{r},i32>>", f"unbox<Pair<{r},i32>>"],
        "nested_maybe_box": [f"boxed<{r}>", f"just<Box<{r}>>"],
        "const_buffer": [f"keep_length<i32,{2 + c % 4}>", f"buffer_first<i32,{2 + c % 4}>"],
        "const_buffer_rec": [f"buffer_first<{r},2>"],
        "wrap_const": [f"Wrap<[i32;{2 + c % 3}]>::copy", f"Wrap<[i32;{2 + c % 3}]>::length"],
        "repeat_rec": [f"repeat3<{r}>"],
        "view_i32": ["view_first<i32>"],
        "pick_ref": [f"pick<{r}>"],
        "slot_get": [f"Slot<{r}>::get"],
        "cell_get": ["Cell<i32>::get"],
        "choose": ["choose<i32>"],
        "fold": [f"{area}_fold<{r}>"],
        "ledger": [f"{ledger}<{r}>::head", f"{ledger}<{r}>::tail", f"{ledger}<{r}>::count", f"score_of<{r}>"],
        "maybe_method": [f"maybe_if<{r}>", f"Maybe<{r}>::or_value", f"Maybe<{r}>::is_just"],
        "stack_push": ["Stack<i32>::pushed", "Stack<i32>::top", "Stack<i32>::size"],
        "score_i32": ["total<i32>"],
        "twice_box": [f"twice_box<{r}>", f"boxed<{r}>", f"boxed<Box<{r}>>"],
        "pair_methods": [f"Pair<{r},i32>::swapped", f"Pair<{r},i32>::left", f"Pair<i32,{r}>::left"],
        "twice_bound": [f"score_of<Twice<{r}>>", f"Twice<{r}>::score"],
        "marker_bound": ["keep<[i32;2]>", "keep<Cell<Cell<i32>>>"],
    }
    return table.get(step.kind, [])


def record_values(record: Record, f0: int, f1: int, f2: int) -> tuple[int, ...]:
    return (f0, f1, f2)[: record.fields]


def area_ledger_count(step: Step) -> int:
    return step.c % 7 + 1


def evaluate_leaf(leaf: Leaf, x: int) -> int:
    value = (x * leaf.factor + leaf.bias) & M
    for step in leaf.steps:
        value = evaluate_step(step, value, x)
    return value


def evaluate_area(area: Area, seed: int) -> int:
    total = 0
    for leaf, salt in zip(area.leaves, area.salts):
        total = (total + evaluate_leaf(leaf, (seed + salt) & M)) & M
    return total


def expected_stdout(workload: Workload) -> str:
    lines = []
    total = 0
    for area in workload.areas:
        part = evaluate_area(area, 7)
        lines.append(str(part))
        total = (total + part) & M
    lines.append(str(total))
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Rendering


class Names:
    """Qualifies library items: bare in one file, `gen::lib::` in a project."""

    def __init__(self, prefix: str = ""):
        self.prefix = prefix

    def __call__(self, name: str) -> str:
        return self.prefix + name

    def lib_item(self, text: str) -> str:
        if not self.prefix:
            return text
        return re.sub(r"^(struct|enum|fn|trait|impl)\b", r"pub \1", text, flags=re.M).replace(
            "\n    fn ", "\n    pub fn "
        )


def record_literal(q: Names, record: Record, f0: str, f1: str, f2: str) -> str:
    values = (f0, f1, f2)[: record.fields]
    inner = ", ".join(f"f{index}: {value}" for index, value in enumerate(values))
    return f"{record.name} {{ {inner} }}"


def render_step(q: Names, area: Area, step: Step, n: int) -> list[str]:
    a, b, c, r, o = step.a, step.b, step.c, step.record, step.other
    kind = step.kind
    if kind == "add":
        return [f"    value = (value + {a} + x) {MASK};"]
    if kind == "mul":
        return [f"    value = (value * {a} + {b}) {MASK};"]
    if kind == "xor":
        return [f"    value = (value ^ {a} ^ x) {MASK};"]
    if kind == "branch":
        return [
            f"    if ((value & {a}) != 0) {{",
            f"        value = (value + {a}) {MASK};",
            "    } else {",
            f"        value = (value + {b}) {MASK};",
            "    }",
        ]
    if kind == "box_i32":
        return [
            f"    let b{n}: {q('Box')}<i32> = {q('boxed')}((value + {a}) {MASK});",
            f"    value = ({q('unbox')}(b{n}) ^ x) {MASK};",
        ]
    if kind == "box_rec":
        return [
            f"    let b{n}: {q('Box')}<{r.name}> = {q('boxed')}({record_literal(q, r, 'value', str(a), 'x')});",
            f"    let r{n}: {r.name} = {q('unbox')}(b{n});",
            f"    value = (r{n}.f0 + r{n}.f1 + x) {MASK};",
        ]
    if kind == "pair_rec_i32":
        return [
            f"    let p{n}: {q('Pair')}<{r.name}, i32> = {q('make_pair')}(",
            f"        {record_literal(q, r, 'value', 'x', str(b))},",
            f"        {a},",
            "    );",
            f"    let q{n}: {r.name} = {q('pair_first')}(p{n});",
            f"    value = (q{n}.f1 * 3 + {q('pair_second')}(p{n}) + p{n}.first.f0) {MASK};",
        ]
    if kind == "pair_i32_bool":
        bit = 1 << (c % 12)
        return [
            f"    let p{n}: {q('Pair')}<i32, bool> = {q('make_pair')}(value, (x & {bit}) != 0);",
            f"    if ({q('pair_second')}(p{n})) {{",
            f"        value = ({q('pair_first')}(p{n}) + {a}) {MASK};",
            "    } else {",
            f"        value = ({q('pair_first')}(p{n}) * 3 + {b}) {MASK};",
            "    }",
        ]
    if kind == "pair_rec_rec":
        return [
            f"    let p{n}: {q('Pair')}<{r.name}, {o.name}> = {q('make_pair')}(",
            f"        {record_literal(q, r, 'value', str(a), 'x')},",
            f"        {record_literal(q, o, 'x', str(b), 'value')},",
            "    );",
            f"    let r{n}: {r.name} = {q('pair_first')}(p{n});",
            f"    let s{n}: {o.name} = {q('pair_second')}(p{n});",
            f"    value = ({q('score_of')}(r{n}) + s{n}.f0) {MASK};",
        ]
    if kind == "maybe_i32_match":
        return [
            f"    let m{n}: {q('Maybe')}<i32> = {q('just')}((value + {a}) {MASK});",
            f"    value = match (m{n}) {{",
            f"        {q('Nothing')} => {b},",
            f"        {q('Just')}(inner{n}) => inner{n} + x,",
            "    };",
            f"    value = value {MASK};",
        ]
    if kind == "maybe_rec":
        bit = 1 << (c % 12)
        return [
            f"    let m{n}: {q('Maybe')}<{r.name}> = {q('maybe_if')}(",
            f"        (value & {bit}) != 0,",
            f"        {record_literal(q, r, 'value', str(a), 'x')},",
            "    );",
            f"    let r{n}: {r.name} = {q('unwrap_or')}(m{n}, {record_literal(q, r, str(b), 'x', str(a))});",
            f"    value = (r{n}.f0 + r{n}.f1) {MASK};",
        ]
    if kind == "outcome_rec":
        bit = 1 << (c % 12)
        return [
            f"    let o{n}: {q('Outcome')}<i32, {r.name}> = {q('good_if')}(",
            f"        (value & {bit}) == 0,",
            f"        (value + {a}) {MASK},",
            f"        {record_literal(q, r, 'x', str(b), 'value')},",
            "    );",
            f"    value = match (o{n}) {{",
            f"        {q('Good')}(g{n}) => g{n},",
            f"        {q('Bad')}(e{n}) => e{n}.f0 + e{n}.f1,",
            "    };",
            f"    value = value {MASK};",
        ]
    if kind == "stack_i32":
        length = 1 + c % 4
        index = (c >> 2) % length
        return [
            f"    let s{n}: {q('Stack')}<i32> = {q('Stack')} {{ items: [value, x, {a}, {b}], len: {length} }};",
            f"    value = (s{n}.top() + s{n}.at({index}) + s{n}.size()) {MASK};",
        ]
    if kind == "stack_rec":
        length = 1 + c % 4
        items = [record_literal(q, r, v, str(i + 1), "x") for i, v in enumerate(("value", "x", str(a), str(b)))]
        return [
            f"    let s{n}: {q('Stack')}<{r.name}> = {q('Stack')} {{",
            "        items: [",
            *[f"            {item}," for item in items],
            "        ],",
            f"        len: {length},",
            "    };",
            f"    let t{n}: {r.name} = s{n}.top();",
            f"    value = (t{n}.f0 + t{n}.f1 + s{n}.size()) {MASK};",
        ]
    if kind == "slice_i32":
        j = 1 + c % 3
        index = (c >> 2) % 4
        return [
            f"    let a{n}: [i32; 4] = [value, x, {a}, {b}];",
            f"    {q('swap')}(a{n}, 0, {j});",
            f"    value = ({q('get')}(a{n}, {index}) + {q('count')}(a{n}, 4)) {MASK};",
        ]
    if kind == "slice_rec":
        return [
            f"    let a{n}: [{r.name}; 2] = [",
            f"        {record_literal(q, r, 'value', str(a), 'x')},",
            f"        {record_literal(q, r, 'x', str(b), 'value')},",
            "    ];",
            f"    {q('swap')}(a{n}, 0, 1);",
            f"    let r{n}: {r.name} = {q('get')}(a{n}, {c % 2});",
            f"    value = (r{n}.f0 * 2 + r{n}.f1) {MASK};",
        ]
    if kind == "trait_total":
        return [
            f"    let t{n}: i32 = {q('total')}(",
            f"        {record_literal(q, r, 'value', str(a), 'x')},",
            f"        {record_literal(q, r, 'x', str(b), 'value')},",
            "    );",
            f"    value = (t{n} + value) {MASK};",
        ]
    if kind == "heavier":
        return [
            f"    let w{n}: {r.name} = {q('heavier')}(",
            f"        {record_literal(q, r, 'value', str(a), 'x')},",
            f"        {record_literal(q, r, 'x', str(b), 'value')},",
            "    );",
            f"    value = (w{n}.f0 + w{n}.f1) {MASK};",
        ]
    if kind == "nested_box_maybe_arr":
        return [
            f"    let n{n}: {q('Pair')}<{q('Box')}<i32>, {q('Maybe')}<[i32; 4]>> = {q('Pair')} {{",
            f"        first: {q('Box')} {{ value: value }},",
            f"        second: {q('Just')}([x, {a}, {b}, value]),",
            "    };",
            f"    let arr{n}: [i32; 4] = {q('unwrap_or')}(n{n}.second, [0, 0, 0, 0]);",
            f"    value = ({q('unbox')}(n{n}.first) + arr{n}[{c % 4}]) {MASK};",
        ]
    if kind == "nested_box_pair":
        return [
            f"    let n{n}: {q('Box')}<{q('Pair')}<{r.name}, i32>> = {q('boxed')}({q('make_pair')}(",
            f"        {record_literal(q, r, 'value', str(a), str(b))},",
            "        x,",
            "    ));",
            f"    let p{n}: {q('Pair')}<{r.name}, i32> = {q('unbox')}(n{n});",
            f"    value = (p{n}.first.f1 + p{n}.second + value) {MASK};",
        ]
    if kind == "nested_maybe_box":
        return [
            f"    let m{n}: {q('Maybe')}<{q('Box')}<{r.name}>> = {q('just')}({q('boxed')}(",
            f"        {record_literal(q, r, 'value', 'x', str(b))},",
            "    ));",
            f"    value = match (m{n}) {{",
            f"        {q('Nothing')} => {b},",
            f"        {q('Just')}(bx{n}) => bx{n}.value.f0 + {a},",
            "    };",
            f"    value = value {MASK};",
        ]
    if kind == "const_buffer":
        size = 2 + c % 4
        values = ", ".join(("value", "x", str(a), str(b), f"{(a + b) & M}")[:size])
        return [
            f"    let buf{n}: {q('Buffer')}<i32, {size}> = {q('Buffer')}<i32, {size}> {{ values: [{values}] }};",
            f"    let kept{n}: [i32; {size}] = {q('keep_length')}(buf{n}.values);",
            f"    value = ({q('buffer_first')}(buf{n}) + kept{n}[{(c >> 2) % size}]) {MASK};",
        ]
    if kind == "const_buffer_rec":
        return [
            f"    let buf{n}: {q('Buffer')}<{r.name}, 2> = {q('Buffer')}<{r.name}, 2> {{",
            "        values: [",
            f"            {record_literal(q, r, 'value', str(a), 'x')},",
            f"            {record_literal(q, r, 'x', str(b), 'value')},",
            "        ],",
            "    };",
            f"    let h{n}: {r.name} = {q('buffer_first')}(buf{n});",
            f"    value = (h{n}.f0 + h{n}.f1 + x) {MASK};",
        ]
    if kind == "wrap_const":
        size = 2 + c % 3
        values = ", ".join(("value", "x", str(a), str(b))[:size])
        return [
            f"    let w{n}: {q('Wrap')}<[i32; {size}]> = {q('Wrap')} {{ value: [{values}] }};",
            f"    let c{n}: [i32; {size}] = w{n}.copy();",
            f"    if (w{n}.length() == {size}) {{",
            f"        value = (c{n}[0] + c{n}[{size - 1}] + {a}) {MASK};",
            "    }",
        ]
    if kind == "repeat_rec":
        return [
            f"    let t{n}: [{r.name}; 3] = {q('repeat3')}({record_literal(q, r, 'value', str(a), 'x')});",
            f"    value = (t{n}[0].f0 + t{n}[2].f1 + x) {MASK};",
        ]
    if kind == "view_i32":
        return [
            f"    let a{n}: [i32; 3] = [value, x, {a}];",
            f"    let v{n}: {q('View')}<i32> = {q('View')} {{ items: a{n}, len: 3 }};",
            f"    value = ({q('view_first')}(v{n}) + v{n}.len + v{n}.items[2]) {MASK};",
        ]
    if kind == "pick_ref":
        return [
            f"    let r{n}: {r.name} = {record_literal(q, r, 'value', str(a), 'x')};",
            f"    let q{n}: &{r.name} = {q('pick')}(r{n}.borrow());",
            f"    value = (q{n}.f0 + q{n}.f1 + x) {MASK};",
        ]
    if kind == "slot_get":
        return [
            f"    let s{n}: {q('Slot')}<{r.name}> = {q('Slot')} {{",
            f"        value: {record_literal(q, r, 'value', str(a), 'x')},",
            "    };",
            f"    let r{n}: {r.name} = s{n}.get();",
            f"    value = (r{n}.f0 ^ r{n}.f1) {MASK};",
        ]
    if kind == "cell_get":
        return [
            f"    let c{n}: {q('Cell')}<i32> = {q('Cell')} {{ value: (value + {a}) {MASK} }};",
            f"    value = (c{n}.get() * 3 + x) {MASK};",
        ]
    if kind == "choose":
        bit = 1 << (c % 12)
        return [f"    value = {q('choose')}(value, (x + {a}) {MASK}, (value & {bit}) != 0);"]
    if kind == "fold":
        return [
            f"    let a{n}: [{r.name}; 3] = [",
            f"        {record_literal(q, r, 'value', str(a), 'x')},",
            f"        {record_literal(q, r, 'x', str(b), 'value')},",
            f"        {record_literal(q, r, str(a), str(b), 'x')},",
            "    ];",
            f"    value = {area_prefix(q, r, area)}fold(a{n}, 3, value);",
        ]
    if kind == "ledger":
        ledger = f"{camel(area_name(r.area))}Ledger"
        if q.prefix and r.area != area.index:
            ledger = f"gen::{area_name(r.area)}::{ledger}"
        return [
            f"    let l{n}: {ledger}<{r.name}> = {ledger} {{",
            f"        head: {record_literal(q, r, 'value', str(a), 'x')},",
            f"        tail: {record_literal(q, r, str(b), 'x', 'value')},",
            f"        count: {c % 7 + 1},",
            "    };",
            f"    let h{n}: {r.name} = l{n}.head();",
            f"    let t{n}: {r.name} = l{n}.tail();",
            f"    value = (h{n}.f0 + l{n}.count() + {q('score_of')}(t{n})) {MASK};",
        ]
    if kind == "marker_bound":
        return [
            f"    let k{n}: [i32; 2] = {q('keep')}([value, x]);",
            f"    let c{n}: {q('Cell')}<{q('Cell')}<i32>> = {q('keep')}({q('Cell')} {{ value: {q('Cell')} {{ value: {a} }} }});",
            f"    value = (k{n}[0] + k{n}[1] + c{n}.value.value) {MASK};",
        ]
    if kind == "maybe_method":
        bit = 1 << (c % 12)
        return [
            f"    let m{n}: {q('Maybe')}<{r.name}> = {q('maybe_if')}(",
            f"        (value & {bit}) != 0,",
            f"        {record_literal(q, r, 'value', str(a), 'x')},",
            "    );",
            f"    let r{n}: {r.name} = m{n}.or_value({record_literal(q, r, str(b), 'x', str(a))});",
            f"    if (m{n}.is_just()) {{",
            f"        value = (r{n}.f0 + r{n}.f1 + 1) {MASK};",
            "    } else {",
            f"        value = (r{n}.f0 + r{n}.f1) {MASK};",
            "    }",
        ]
    if kind == "stack_push":
        return [
            f"    let s{n}: {q('Stack')}<i32> = {q('Stack')} {{ items: [value, x, 0, 0], len: 2 }};",
            f"    let t{n}: {q('Stack')}<i32> = s{n}.pushed((value + {a}) {MASK});",
            f"    value = (t{n}.top() + t{n}.size() + s{n}.size()) {MASK};",
        ]
    if kind == "score_i32":
        return [f"    value = ({q('total')}(value, x) + {a}) {MASK};"]
    if kind == "twice_box":
        return [
            f"    let b{n}: {q('Box')}<{q('Box')}<{r.name}>> = {q('twice_box')}(",
            f"        {record_literal(q, r, 'value', str(a), 'x')},",
            "    );",
            f"    value = (b{n}.value.value.f0 + b{n}.value.value.f1) {MASK};",
        ]
    if kind == "pair_methods":
        return [
            f"    let p{n}: {q('Pair')}<{r.name}, i32> = {q('Pair')} {{",
            f"        first: {record_literal(q, r, 'value', str(a), 'x')},",
            f"        second: (x + {b}) {MASK},",
            "    };",
            f"    let q{n}: {q('Pair')}<i32, {r.name}> = p{n}.swapped();",
            f"    let r{n}: {r.name} = p{n}.left();",
            f"    value = (q{n}.left() + r{n}.f1 + q{n}.second.f0) {MASK};",
        ]
    if kind == "twice_bound":
        return [
            f"    let t{n}: {q('Twice')}<{r.name}> = {q('Twice')} {{",
            f"        inner: {record_literal(q, r, 'value', str(a), 'x')},",
            "    };",
            f"    value = {q('score_of')}(t{n});",
        ]
    raise ValueError(f"unknown step kind {kind}")


def area_prefix(q: Names, record: Record, area: Area) -> str:
    """Per-area generic helpers live with the record's area."""
    if record.area == area.index:
        return "" if q.prefix else f"{area_name(record.area)}_"
    return f"gen::{area_name(record.area)}::" if q.prefix else f"{area_name(record.area)}_"


def qualified_records(q: Names, area: Area, text: str, areas: list[Area]) -> str:
    """In a project, records of other areas are reached through their module."""
    if not q.prefix:
        return text
    owners = {record.name: other.name for other in areas if other.index != area.index for record in other.records}
    if not owners:
        return text
    pattern = re.compile(r"(?<![\w:])(" + "|".join(sorted(owners, key=len, reverse=True)) + r")\b")
    return pattern.sub(lambda match: f"gen::{owners[match.group(1)]}::{match.group(1)}", text)


def render_leaf(q: Names, area: Area, leaf: Leaf) -> str:
    lines = [
        f"fn {leaf.name}(x: i32) -> i32 {{",
        f"    let value: i32 = (x * {leaf.factor} + {leaf.bias}) {MASK};",
    ]
    for n, step in enumerate(leaf.steps):
        lines.extend(render_step(q, area, step, n))
    lines.extend(["    return value;", "}", ""])
    return "\n".join(lines) + "\n"


def render_record(q: Names, record: Record) -> str:
    pub = "pub " if q.prefix else ""
    fields = "".join(f"    f{index}: i32,\n" for index in range(record.fields))
    terms = " + ".join(f"self.f{index} * {coef}" for index, coef in enumerate(record.coefficients))
    return (
        f"{pub}struct {record.name} {{\n{fields}}}\n\n"
        f"{pub}impl {q('Score')} for {record.name} {{\n"
        f"    {pub}fn score(self) -> i32 {{\n"
        f"        return ({terms} + {record.bias}) {MASK};\n    }}\n}}\n\n"
        f"{pub}impl {q('Weight')} for {record.name} {{\n"
        f"    {pub}fn weight(self) -> i32 {{\n"
        f"        return (self.f0 + self.f1 * {record.weight_factor}) {MASK};\n    }}\n}}\n\n"
        f"{pub}impl {record.name} {{\n"
        f"    {pub}fn borrow(&self) -> &{record.name} {{\n        return self;\n    }}\n}}\n\n"
    )


def render_area_helpers(q: Names, area: Area, needed: set[str]) -> str:
    pub = "pub " if q.prefix else ""
    prefix = "" if q.prefix else f"{area.name}_"
    ledger = f"{camel(area.name)}Ledger"
    parts = []
    if "ledger" in needed:
        parts.append(
            f"{pub}struct {ledger}<T> {{\n    head: T,\n    tail: T,\n    count: i32,\n}}\n\n"
            f"{pub}impl<T> {ledger}<T> {{\n"
            f"    {pub}fn head(&self) -> T {{\n        return self.head;\n    }}\n\n"
            f"    {pub}fn tail(&self) -> T {{\n        return self.tail;\n    }}\n\n"
            f"    {pub}fn count(&self) -> i32 {{\n        return self.count;\n    }}\n}}\n\n"
        )
    if "fold" in needed:
        parts.append(
            f"{pub}fn {prefix}fold<T>(items: [T], len: i32, seed: i32) -> i32 where T: {q('Score')} {{\n"
            "    let acc: i32 = seed;\n    let i: i32 = 0;\n"
            "    while (i < len) {\n"
            "        let item: T = items[i];\n"
            f"        acc = (acc + item.score()) {MASK};\n"
            "        i += 1;\n    }\n"
            "    return acc;\n}\n\n"
        )
    return "".join(parts)


def render_area_body(q: Names, area: Area, needed: set[str], areas: list[Area]) -> str:
    pub = "pub " if q.prefix else ""
    evaluate = "evaluate" if q.prefix else f"{area.name}_evaluate"
    text = f"// area {area.name}\n\n"
    text += "".join(render_record(q, record) for record in area.records)
    text += render_area_helpers(q, area, needed)
    text += "".join(render_leaf(q, area, leaf) for leaf in area.leaves)
    calls = "".join(
        f"    total = (total + {leaf.name}((seed + {salt}) {MASK})) {MASK};\n"
        for leaf, salt in zip(area.leaves, area.salts)
    )
    text += f"{pub}fn {evaluate}(seed: i32) -> i32 {{\n    let total: i32 = 0;\n{calls}    return total;\n}}\n\n"
    return qualified_records(q, area, text, areas)


def needed_library(workload: Workload) -> list[str]:
    used = {step.kind for leaf in workload.leaves for step in leaf.steps}
    items = {"Score", "Weight"}  # every record implements both
    for kind in used:
        if kind in workload.kinds:
            items.update(workload.kinds[kind][1])
    return [name for name in LIBRARY_ORDER if name in items]


def used_kinds(workload: Workload) -> set[str]:
    return {step.kind for leaf in workload.leaves for step in leaf.steps}


def render_main(q: Names, workload: Workload, return_expr: str = "0") -> str:
    lines = ["fn main() -> i32 {", "    let total: i32 = 0;", "    let part: i32 = 0;"]
    for area in workload.areas:
        call = f"gen::{area.name}::evaluate" if q.prefix else f"{area.name}_evaluate"
        lines.extend([
            f"    part = {call}(7);",
            "    print(part);",
            f"    total = (total + part) {MASK};",
        ])
    lines.extend(["    print(total);", f"    return {return_expr};", "}", ""])
    return "\n".join(lines)


def render_single_file(workload: Workload, target_bytes: int | None = None, matrix_probe: bool = False) -> str:
    """One module; a matrix probe returns the checksum modulo 128 and says so on line 1."""
    q = Names()
    needed = used_kinds(workload)
    library = "".join(LIBRARY[name] + "\n" for name in needed_library(workload))
    header = ""
    if matrix_probe:
        header = f"// expect: {int(expected_stdout(workload).split()[-1]) & 127}\n"
    prefix = header + "module bench::generic;\n\n// library\n\n" + library
    body = "".join(render_area_body(q, area, needed, workload.areas) for area in workload.areas)
    suffix = render_main(q, workload, "total & 127" if matrix_probe else "0")
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


def render_project(workload: Workload) -> dict[str, str]:
    q = Names("gen::lib::")
    needed = used_kinds(workload)
    lib = "module gen::lib;\n\n" + "".join(q.lib_item(LIBRARY[name]) + "\n" for name in needed_library(workload))
    files = {"lanius/src/gen/lib.lani": lib}
    for area in workload.areas:
        body = render_area_body(q, area, needed, workload.areas)
        imports = "import gen::lib;\n" + "".join(
            f"import gen::{other.name};\n"
            for other in workload.areas
            if other.index != area.index and f"gen::{other.name}::" in body
        )
        files[f"lanius/src/gen/{area.name}.lani"] = f"module gen::{area.name};\n\n{imports}\n" + body
    imports = "import gen::lib;\n" + "".join(f"import gen::{area.name};\n" for area in workload.areas)
    files["lanius/main.lani"] = "module app::main;\n\n" + imports + "\n" + render_main(q, workload)
    return files


def padding_comment(byte_count: int) -> str:
    if byte_count <= 2:
        return "\n" * byte_count
    return "//" + "p" * (byte_count - 3) + "\n"


# ---------------------------------------------------------------------------
# Statistics


TYPE_APP = re.compile(r"\b[A-Z][A-Za-z0-9]*<")


def statistics(sources: dict[str, str], workload: Workload) -> dict[str, object]:
    text = "\n".join(sources.values())
    code = re.sub(r"//[^\n]*", "", text)
    lines = [line for line in code.splitlines() if line.strip()]
    kloc = len(lines) / 1000.0
    generic_fns = set(re.findall(r"\bfn\s+(\w+)\s*<", code))
    generic_types = set(re.findall(r"\b(?:struct|enum)\s+(\w+)\s*<", code))
    calls = re.findall(r"(?<![\w.])(\w+)\s*\(", code)
    keywords = {"if", "while", "match", "return", "fn", "print"} | set(LIBRARY_ENUM_VARIANTS["Maybe"]) | set(
        LIBRARY_ENUM_VARIANTS["Outcome"]
    )
    function_calls = [name for name in calls if name not in keywords and not re.match(r"[A-Z]", name)]
    method_calls = re.findall(r"\.\s*(\w+)\s*\(", code)
    generic_methods = {"top", "at", "size", "length", "copy", "get", "head", "tail", "count", "score", "weight"}
    instantiations = set()
    for match in re.finditer(r"\b(\w+)<", code):
        name = match.group(1)
        if name not in generic_types:
            continue
        depth, index = 1, match.end()
        while depth and index < len(code):
            depth += {"<": 1, ">": -1}.get(code[index], 0)
            index += 1
        args = code[match.end(): index - 1]
        if not re.search(r"\b(T|A|B|E|N|M)\b", args):
            instantiations.add(f"{name}<{args}>")
    generic_calls = [name for name in function_calls if name in generic_fns or re.sub(r"^\w+?_", "", name) in generic_fns]
    return {
        "nonblank_code_lines": len(lines),
        "physical_lines": text.count("\n"),
        "bytes": len(text.encode()),
        "areas": len(workload.areas),
        "leaf_functions": len(workload.leaves),
        "record_types": sum(len(area.records) for area in workload.areas),
        "generic_type_declarations": len(generic_types),
        "generic_function_declarations": len(generic_fns),
        "trait_impls": len(re.findall(r"^(?:pub )?impl(?:<[^>]*>)?\s+[\w:<>]+\s+for\s", code, re.M)),
        "generic_impl_blocks": len(re.findall(r"^(?:pub )?impl<", code, re.M)),
        "function_call_sites": len(function_calls),
        "generic_function_call_sites": len(generic_calls),
        "method_call_sites": len(method_calls),
        "generic_method_call_sites": sum(1 for name in method_calls if name in generic_methods),
        "type_applications": len(TYPE_APP.findall(code)),
        "type_applications_per_kloc": round(len(TYPE_APP.findall(code)) / kloc, 1),
        "distinct_concrete_type_applications": len(instantiations),
        "generic_body_specializations": len({
            name for leaf in workload.leaves for step in leaf.steps for name in step_specializations(step)
        }),
        "step_kinds": {kind: sum(1 for leaf in workload.leaves for step in leaf.steps if step.kind == kind)
                       for kind in sorted(used_kinds(workload))},
    }


# ---------------------------------------------------------------------------
# Command line


def kinds_for(backlog: bool, without: list[str] | None = None) -> dict[str, tuple[int, tuple[str, ...], bool]]:
    kinds = dict(STEP_KINDS)
    if backlog:
        kinds.update(BACKLOG_KINDS)
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
        (out / f"g_{kind}.lani").write_text(render_single_file(workload, matrix_probe=True))
    # One program mixing every kind, like a slice of the benchmark.
    workload = build_workload(seed, 2 * LEAVES_PER_AREA, kinds)
    (out / "g_zz_mix.lani").write_text(render_single_file(workload, matrix_probe=True))
    print(f"wrote {len(kinds) + 1} probes to {out}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--layout", choices=("single-file", "project"), default="single-file")
    parser.add_argument("--target-bytes", type=int, default=1_000_000,
                        help="exact single-file size (project: approximate total size)")
    parser.add_argument("--seed", type=int, default=20)
    parser.add_argument("--leaves", type=int, help="force the number of leaf functions")
    parser.add_argument("--backlog", action="store_true",
                        help="also emit steps that need features in tests/fixtures/generics_backlog")
    parser.add_argument("--type-pool", type=int, metavar="N",
                        help="use only the first N record types as type arguments (fewer specializations)")
    parser.add_argument("--without", action="append", default=[], metavar="KIND",
                        help="leave out a step kind (repeatable)")
    parser.add_argument("--probes", action="store_true",
                        help="write one small matrix-style probe per step kind into --out")
    parser.add_argument("--matrix-probe", action="store_true",
                        help="single file whose main returns the checksum mod 128, with a `// expect:` line")
    parser.add_argument("--stats", action="store_true", help="print workload statistics")
    args = parser.parse_args()

    kinds = kinds_for(args.backlog, args.without)
    if args.probes:
        write_probes(args.out, args.seed, kinds)
        return 0
    pool = args.type_pool
    leaf_count = args.leaves or largest_workload_that_fits(args.seed, args.target_bytes, kinds, pool)
    if args.layout == "project" and not args.leaves:
        # Qualified paths make the project larger than the single file; scale
        # the leaf count so the project's total size is close to the target.
        project = render_project(build_workload(args.seed, leaf_count, kinds, type_pool=pool))
        size = sum(len(text.encode()) for text in project.values())
        leaf_count = max(1, leaf_count * args.target_bytes // size)
    workload = build_workload(args.seed, leaf_count, kinds, type_pool=pool)
    args.out.mkdir(parents=True, exist_ok=True)
    if args.layout == "single-file":
        target = None if args.leaves or args.matrix_probe else args.target_bytes
        sources = {"generic.lani": render_single_file(workload, target, args.matrix_probe)}
        entry, source_root = "generic.lani", None
    else:
        sources = render_project(workload)
        entry, source_root = "lanius/main.lani", "lanius/src"
    for relative, text in sources.items():
        path = args.out / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    stats = statistics(sources, workload)
    manifest = {
        "schema": "lanius.generic-workload.v1",
        "generator": "tools/generate_generic_workload.py",
        "layout": args.layout,
        "seed": args.seed,
        "backlog": args.backlog,
        "without": sorted(args.without),
        "type_pool": args.type_pool,
        "entry": entry,
        "source_root": source_root,
        "expected_stdout": expected_stdout(workload),
        "expected_exit_code": int(expected_stdout(workload).split()[-1]) & 127 if args.matrix_probe else 0,
        "statistics": stats,
        "sources": {
            relative: {"bytes": len(text.encode()), "sha256": hashlib.sha256(text.encode()).hexdigest()}
            for relative, text in sources.items()
        },
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    if args.stats:
        json.dump(stats, sys.stdout, indent=2)
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
