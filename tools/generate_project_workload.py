#!/usr/bin/env python3
"""Generate a deterministic multi-file Lanius project shaped like real code, and its Rust twin.

The headline benchmark (tools/generate_stdlib_workload.py, "stdlibr") is a stdlib-call stress
test: one file of straight-line i32 functions, no loops, no recursion, ~70 generic
specializations. This generator instead follows the static shape of verified_compiler/src (the
largest real Lanius program) and, for generics, a scaled-down version of the density measured on
Rust library crates (wgpu-core, petgraph, chrono):

  per KSLOC (SLOC = nonblank code lines)     target     verified_compiler/src
  loops (mostly while, some for)              14         13.9
  fn length median / p90 (SLOC)               8 / 42     8 / 42 (tail to ~400)
  params per free fn                          ~2.5       2.65
  calls per fn                                ~5         4.7
  directly recursive free fns                 ~4%        4%
  call-graph depth (modules form a DAG)       >= 20      45
  generic fns (with trait bounds)             6 (4)      0
  impls (trait share)                         14 (70%)   0
  methods                                     35         0
  generic user structs/enums                  1          0
  distinct concrete instantiations            ~6         0
  files                                       ~4, ~240 SLOC each

Every value is an i32 kept in [0, 4095] by masking, so nothing overflows in either language.
The generator builds the program as a small AST, evaluates it to get the exact stdout (one line
per module entry, then the total), and prints the AST as a Lanius source-root project and, with
--rust-out, as a Rust crate with the same items, bodies and output. The Rust side uses only what
the Lanius side uses: structs, enums, inherent and trait impls, generic fns and types with trait
bounds, while/for loops, match, recursion and consts. There are no closures, iterators, trait
objects or macros apart from `println!` in main and `#[derive(Clone, Copy)]` (Lanius copies
values; Rust needs Copy for the same by-value code). Idiomatic Rust would use other constructs
and might compile faster or slower.

usage:
  generate_project_workload.py --preset 30k --out DIR [--rust-out DIR] [--seed N]
  generate_project_workload.py --modules N --out DIR ...

DIR gets manifest.json (schema lanius.generic-workload.v1, layout "project", entry
lanius/main.lani, source_root lanius/src) like tools/generate_generic_workload.py writes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from dataclasses import dataclass, field
from pathlib import Path

MASK = 4095
# Target SLOC per preset. The module count is solved for: generate at an estimate of ~270
# SLOC per module, then retry at the count each try implies (up to 5 tries, until within 3%),
# keeping the closest.
PRESETS = {"1k": 1_000, "5k": 5_000, "10k": 10_000, "30k": 30_000, "60k": 60_000}
SLOC_PER_MODULE_GUESS = 270

AREAS = [
    "ledger", "stock", "route", "bill", "catalog", "session", "metric", "store", "plan",
    "price", "ship", "audit", "quota", "search", "render", "parse", "cache", "index",
    "policy", "report", "account", "net", "journal", "order",
]
NOUNS = [
    "entry", "batch", "window", "record", "bucket", "segment", "slot", "range", "token",
    "frame", "budget", "cursor", "packet", "region", "ticket", "shard", "layer", "step",
]
VERBS = [
    "settle", "balance", "merge", "scan", "fold", "rank", "trim", "score", "resolve", "adjust",
    "measure", "collect", "advance", "reconcile", "estimate", "filter", "combine", "derive",
    "normalize", "project", "weigh", "split", "align", "commit",
]
LOCALS = [
    "total", "pending", "offset", "limit", "carry", "weight", "cursor", "remaining", "bias",
    "accum", "span", "delta", "factor", "level", "count", "budget", "score", "rank", "depth",
]
TRAIT_NAMES = ["Score", "Weigh", "Rank", "Cost", "Grade", "Span", "Load", "Blend", "Order", "Shape"]
TRAIT_SUFFIXES = ["of", "with"]
OPS = ["+", "+", "-", "^", "|", "&"]


@dataclass
class FnDef:
    module: int
    name: str
    params: list  # [(name, type)]
    ret: object
    kind: str = "free"
    body: list = field(default_factory=list)
    generics: list = field(default_factory=list)  # [(name, [trait keys])]
    cost: int = 1
    bound: str | None = None  # trait key of the single bound, if any
    owner: object = None  # inherent methods: their TypeDef


@dataclass
class TypeDef:
    """A struct or an enum. Types are "i32", "bool", ("param", "T") or ("struct", key, [args])."""

    key: str
    module: int
    name: str
    fields: list = field(default_factory=list)  # [(name, type)]
    generic: bool = False  # one parameter T
    is_enum: bool = False
    variants: list = field(default_factory=list)  # [(name, payload type or None)]
    traits: list = field(default_factory=list)  # trait keys it implements
    bound: str | None = None  # generic types: T must implement this (and holders implement it too)
    methods: list = field(default_factory=list)  # inherent methods
    trait_methods: dict = field(default_factory=dict)  # trait key -> [FnDef]
    reader: FnDef | None = None  # enums: the fn matching on it


@dataclass
class TraitDef:
    key: str
    module: int
    name: str
    methods: list  # method names; each is fn(self, k: i32) -> i32


@dataclass
class Module:
    index: int
    name: str
    visible: list = field(default_factory=list)
    consts: list = field(default_factory=list)  # [(name, value)]
    types: list = field(default_factory=list)
    fns: list = field(default_factory=list)
    traits: list = field(default_factory=list)
    imports: set = field(default_factory=set)
    entry: FnDef | None = None


def mask(e):
    return ("mask", e)


def stype(td, arg=None):
    return ("struct", td.key, [arg] if arg is not None else [])


class Program:
    def __init__(self, n_modules):
        self.modules: list[Module] = []
        self.types: dict[str, TypeDef] = {}
        self.traits: dict[str, TraitDef] = {}
        self.fns: dict[tuple, FnDef] = {}
        self.n_modules = n_modules
        self.used_names: set[str] = set()
        self.main_seeds = []
        self.instances = set()  # (generic item, concrete type argument)
        self.instance_pool = {}  # generic item -> concrete types it was used with

    def unique(self, base):
        name, k = base, 2
        while name in self.used_names:
            name, k = f"{base}_{k}", k + 1
        self.used_names.add(name)
        return name


# ---------------------------------------------------------------------------------------------
# Evaluation


class Return(Exception):
    def __init__(self, value):
        self.value = value


class Evaluator:
    def __init__(self, program):
        self.p = program
        self.steps = 0

    def call(self, fn, args):
        env = {name: value for (name, _), value in zip(fn.params, args)}
        try:
            self.block(fn.body, env)
        except Return as r:
            return r.value
        raise RuntimeError(f"{fn.name} fell off its end")

    def block(self, stmts, env):
        for s in stmts:
            self.stmt(s, env)

    def stmt(self, s, env):
        self.steps += 1
        if self.steps > 50_000_000:
            raise RuntimeError("program runs too long")
        k = s[0]
        if k in ("let", "assign"):
            env[s[1]] = self.expr(s[-1], env)
        elif k == "if":
            self.block(s[2] if self.expr(s[1], env) else s[3], env)
        elif k == "while":
            while self.expr(s[1], env):
                self.block(s[2], env)
        elif k == "for":
            for value in range(self.expr(s[2], env), self.expr(s[3], env)):
                env[s[1]] = value
                self.block(s[4], env)
        elif k == "return":
            raise Return(self.expr(s[1], env))
        else:
            raise ValueError(k)

    def expr(self, e, env):
        k = e[0]
        if k == "int":
            return e[1]
        if k == "var":
            return env[e[1]]
        if k == "const":
            return e[3]
        if k == "mask":
            return self.expr(e[1], env) & MASK
        if k == "bin":
            a, b = self.expr(e[2], env), self.expr(e[3], env)
            return {"+": a + b, "-": a - b, "*": a * b, "&": a & b, "^": a ^ b, "|": a | b}[e[1]]
        if k == "cmp":
            a, b = self.expr(e[2], env), self.expr(e[3], env)
            return {"<": a < b, "<=": a <= b, ">": a > b, ">=": a >= b, "==": a == b, "!=": a != b}[e[1]]
        if k == "call":
            return self.call(self.p.fns[e[1]], [self.expr(a, env) for a in e[2]])
        if k == "mcall":
            recv = self.expr(e[1], env)
            return self.call(self.method(recv, e[2]), [recv] + [self.expr(a, env) for a in e[3]])
        if k == "field":
            return self.expr(e[1], env)[2][e[2]]
        if k == "struct":
            return ("S", e[1], {name: self.expr(v, env) for name, v in e[2]})
        if k == "variant":
            return ("E", e[1], e[2], self.expr(e[3], env) if e[3] is not None else None)
        if k == "match":
            value = self.expr(e[1], env)
            for variant, binder, arm in e[3]:
                if value[2] == variant:
                    if binder:
                        env[binder] = value[3]
                    return self.expr(arm, env)
            raise RuntimeError("no match arm")
        raise ValueError(k)

    def method(self, recv, name):
        td = self.p.types[recv[1]]
        for fn in td.methods + [f for fs in td.trait_methods.values() for f in fs]:
            if fn.name == name:
                return fn
        raise RuntimeError(f"{td.name} has no method {name}")


# ---------------------------------------------------------------------------------------------
# Generation


class Generator:
    def __init__(self, program, args, rng):
        self.p = program
        self.rng = rng
        self.a = args

    def choice(self, xs):
        return xs[self.rng.randrange(len(xs))]

    def chance(self, p):
        return self.rng.random() < p

    def cap(self, s):
        return "".join(part.capitalize() for part in s.split("_"))

    def target_fn_sloc(self):
        # verified_compiler/src: p25 4, median 8, p75 18, p90 42, p99 ~210, max ~400.
        r = self.rng.random()
        for limit, lo, hi in ((0.17, 2, 3), (0.45, 4, 7), (0.62, 8, 12), (0.77, 13, 22),
                              (0.89, 23, 45), (0.96, 46, 90), (0.99, 91, 180)):
            if r < limit:
                return self.rng.randint(lo, hi)
        return self.rng.randint(181, 380)

    def seen_modules(self, mod):
        return [mod.index] + mod.visible

    def note_use(self, mod, other):
        if other != mod.index:
            mod.imports.add(other)

    def traits_visible(self, mod):
        mods = set(self.seen_modules(mod))
        return [t for t in self.p.traits.values() if t.module in mods]

    def types_visible(self, mod, pred):
        return [td for i in self.seen_modules(mod) for td in self.p.modules[i].types if pred(td)]

    def records(self, mod, trait=None):
        return self.types_visible(mod, lambda td: not td.is_enum and not td.generic
                                  and (trait is None or trait in td.traits))

    # -- skeleton
    def build(self):
        p = self.p
        n = p.n_modules
        for i in range(n):
            p.modules.append(Module(index=i, name=f"{AREAS[i % len(AREAS)]}_{i:03d}"))
        # Traits live in the first few modules (a "core" layer every module imports, as Rust
        # crates do with their trait modules). Besides those, each module sees its two
        # predecessors and up to two random earlier modules: long cross-module call chains
        # without a huge fan-in.
        n_traits = max(2, round(n / self.a.modules_per_trait))
        trait_modules = list(range(min(n, 3)))
        for mod in p.modules:
            earlier = list(range(mod.index))
            seen = set(earlier[-2:]) | {t for t in trait_modules if t < mod.index}
            for _ in range(self.a.random_imports):
                if earlier:
                    seen.add(self.choice(earlier))
            mod.visible = sorted(seen, reverse=True)
        for t in range(n_traits):
            mod = p.modules[trait_modules[t % len(trait_modules)]]
            base = TRAIT_NAMES[t % len(TRAIT_NAMES)]
            name = base if t < len(TRAIT_NAMES) else f"{base}{t // len(TRAIT_NAMES)}"
            td = TraitDef(key=f"t{t}", module=mod.index, name=name,
                          methods=[f"{name.lower()}_{s}" for s in TRAIT_SUFFIXES])
            p.traits[td.key] = td
            mod.traits.append(td)
        for mod in p.modules:
            self.build_module(mod)
        p.main_seeds = [(mod, self.rng.randint(1, 4000)) for mod in p.modules]

    def build_module(self, mod):
        rng, i = self.rng, mod.index
        for k in range(rng.randint(3, 8)):
            mod.consts.append((f"{self.choice(LOCALS).upper()}_{i:03d}_{k}", rng.randint(1, 97)))
        traits = self.traits_visible(mod)
        for k in range(rng.randint(2, 3)):
            fields = [(f"{self.choice(LOCALS)}_{f}", "i32") for f in range(rng.randint(2, 5))]
            nested = [td for td in self.records(mod) if td.module != i]
            if nested and self.chance(0.25):
                inner = self.choice(nested)
                fields.append((f"inner_{len(fields)}", stype(inner)))
            td = TypeDef(key=f"s{i}_{k}", module=i,
                         name=self.cap(f"{self.choice(NOUNS)}_{self.choice(NOUNS)}_{i:03d}_{k}"), fields=fields)
            if traits and self.chance(self.a.trait_impl_rate):
                td.traits.append(self.choice(traits).key)
            if traits and self.chance(0.15):
                other = self.choice(traits).key
                if other not in td.traits:
                    td.traits.append(other)
            self.add_type(mod, td)
        if self.chance(0.75):
            variants = [("idle", None), ("active", "i32"), ("blocked", "i32"), ("done", None)][: rng.randint(2, 4)]
            td = TypeDef(key=f"e{i}", module=i, name=self.cap(f"{self.choice(NOUNS)}_state_{i:03d}"), is_enum=True,
                         variants=[(self.cap(f"{v}_{i:03d}"), t) for v, t in variants])
            self.add_type(mod, td)
        # Generic user types: about one per KSLOC, i.e. one in four modules.
        bounds = [t for t in traits if self.records(mod, t.key)]
        if bounds and self.chance(self.a.generic_type_rate):
            bound = self.choice(bounds).key
            if self.a.generic_enums and self.chance(0.4):
                td = TypeDef(key=f"ge{i}", module=i, name=self.cap(f"{self.choice(NOUNS)}_slot_{i:03d}"),
                             generic=True, is_enum=True, bound=bound,
                             variants=[(f"Vacant{i:03d}", None), (f"Held{i:03d}", ("param", "T"))])
            else:
                td = TypeDef(key=f"g{i}", module=i, name=self.cap(f"{self.choice(NOUNS)}_holder_{i:03d}"),
                             generic=True, bound=bound, traits=[bound],
                             fields=[("item", ("param", "T")), ("weight", "i32")])
            self.note_use(mod, self.p.traits[bound].module)
            self.add_type(mod, td)
        for g in range(3):
            if self.chance(self.a.generic_fn_rate):
                self.make_generic_fn(mod, g)
        for td in mod.types:
            self.make_type_items(mod, td)
        for f in range(rng.randint(self.a.free_fns_min, self.a.free_fns_max)):
            self.make_free_fn(mod, f)
        self.make_entry(mod)

    def add_type(self, mod, td):
        self.p.types[td.key] = td
        mod.types.append(td)
        for _, t in td.fields:
            if isinstance(t, tuple) and t[0] == "struct":
                self.note_use(mod, self.p.types[t[1]].module)
        for tk in td.traits:
            self.note_use(mod, self.p.traits[tk].module)

    def new_fn(self, mod, name, params, ret, kind, unique=True, generics=None):
        return FnDef(module=mod.index, name=self.p.unique(name) if unique else name, params=params,
                     ret=ret, kind=kind, generics=generics or [])

    def register(self, mod, fn):
        mod.fns.append(fn)
        self.p.fns[(mod.index, fn.name)] = fn

    def make_generic_fn(self, mod, g):
        i = mod.index
        bounds = [t for t in self.traits_visible(mod) if self.records(mod, t.key)]
        if bounds and self.chance(0.67):
            t = self.p.traits[self.choice(bounds).key]
            self.note_use(mod, t.module)
            fn = self.new_fn(mod, f"{self.choice(VERBS)}_by_{t.name.lower()}_{i:03d}",
                             [("first", ("param", "T")), ("second", ("param", "T")), ("bias", "i32")], "i32",
                             "generic", generics=[("T", [t.key])])
            fn.bound = t.key
            body = [("let", "left", "i32", ("mcall", ("var", "first"), t.methods[0], [("var", "bias")])),
                    ("let", "right", "i32", ("mcall", ("var", "second"), self.choice(t.methods),
                                             [mask(("bin", "+", ("var", "bias"), ("int", g + 1)))]))]
            if self.chance(0.5):
                body.append(("if", ("cmp", ">", ("var", "left"), ("var", "right")),
                             [("return", mask(("bin", "-", ("var", "left"), ("var", "right"))))], []))
            body.append(("return", mask(("bin", "+", ("bin", "*", ("var", "left"), ("int", 3)), ("var", "right")))))
            fn.body = body
            fn.cost = 8
        else:
            fn = self.new_fn(mod, f"pick_{self.choice(NOUNS)}_{i:03d}",
                             [("flag", "bool"), ("first", ("param", "T")), ("second", ("param", "T"))],
                             ("param", "T"), "pick", generics=[("T", [])])
            fn.body = [("if", ("var", "flag"), [("return", ("var", "first"))], []), ("return", ("var", "second"))]
            fn.cost = 2
        self.register(mod, fn)

    def make_type_items(self, mod, td):
        i = mod.index
        if td.is_enum and not td.generic:
            fn = self.new_fn(mod, f"{self.choice(VERBS)}_state_{i:03d}", [("state", stype(td)), ("bias", "i32")],
                             "i32", "enum_reader")
            arms = [(v, "amount" if t else None,
                     mask(("bin", "+", ("var", "amount"), ("var", "bias"))) if t
                     else mask(("bin", "*", ("var", "bias"), ("int", self.rng.randint(2, 5)))))
                    for v, t in td.variants]
            fn.body = [("let", "value", "i32", ("match", ("var", "state"), td.key, arms)), ("return", ("var", "value"))]
            fn.cost = 3
            td.reader = fn
            self.register(mod, fn)
            return
        if td.is_enum:
            t = self.p.traits[td.bound]
            fn = self.new_fn(mod, f"{self.choice(VERBS)}_slot_{i:03d}",
                             [("slot", stype(td, ("param", "T"))), ("fallback", "i32")], "i32", "slot_reader",
                             generics=[("T", [t.key])])
            fn.bound = t.key
            fn.body = [("return", ("match", ("var", "slot"), td.key, [
                (td.variants[0][0], None, ("var", "fallback")),
                (td.variants[1][0], "held", ("mcall", ("var", "held"), t.methods[0], [("var", "fallback")])),
            ]))]
            fn.cost = 6
            td.reader = fn
            self.register(mod, fn)
            return
        self_t = stype(td, ("param", "T") if td.generic else None)
        for tk in td.traits:
            t = self.p.traits[tk]
            fns = []
            for mi, mname in enumerate(t.methods):
                fn = self.new_fn(mod, mname, [("self", self_t), ("k", "i32")], "i32", "trait_method", unique=False)
                if td.generic:
                    inner = ("mcall", ("field", ("var", "self"), "item"), mname, [("var", "k")])
                    acc = ("bin", "+", inner, ("bin", "*", ("field", ("var", "self"), "weight"), ("int", 3 + mi)))
                    fn.cost = 6
                else:
                    acc = ("var", "k")
                    for fname, ftype in td.fields:
                        if ftype == "i32":
                            term = ("field", ("var", "self"), fname)
                            if self.chance(0.5):
                                term = ("bin", "*", term, ("int", self.rng.randint(2, 7)))
                            acc = ("bin", self.choice(["+", "+", "^"]), acc, term)
                    fn.cost = 2
                fn.body = [("return", mask(acc))]
                fns.append(fn)
            td.trait_methods[tk] = fns
        if td.generic:
            fn = self.new_fn(mod, "weight_of", [("self", self_t)], "i32", "method", unique=False)
            fn.body = [("return", mask(("bin", "+", ("field", ("var", "self"), "weight"), ("int", 1))))]
            fn.cost = 2
            fn.owner = td
            td.methods.append(fn)
            return
        if self.chance(self.a.inherent_impl_rate):
            for name in self.rng.sample(VERBS, self.rng.randint(2, 7)):
                params = [("self", self_t), ("amount", "i32")] + ([("scale", "i32")] if self.chance(0.4) else [])
                fn = self.new_fn(mod, name, params, "i32", "method", unique=False)
                fn.owner = td
                td.methods.append(fn)
            for fn in td.methods:
                # Bodies after all signatures; a method may call the methods declared before it.
                fn.body, fn.cost = self.make_body(mod, fn, self.choice([2, 2, 3, 3, 4, 5, 6, 8, 11, 16]),
                                                  self.a.fn_budget // 3)

    def make_free_fn(self, mod, f):
        i = mod.index
        nparams = self.choice([1, 2, 2, 3, 3, 3, 4, 4, 5])
        params = [(name, "i32") for name in self.rng.sample(LOCALS, nparams)]
        recs = self.records(mod)
        if recs and self.chance(0.3):
            td = self.choice(recs)
            params[-1] = (f"{self.choice(NOUNS)}_in", stype(td))
            self.note_use(mod, td.module)
        enums = self.types_visible(mod, lambda td: td.is_enum and not td.generic)
        if enums and self.chance(0.1):
            td = self.choice(enums)
            params.append(("state_in", stype(td)))
            self.note_use(mod, td.module)
        fn = self.new_fn(mod, f"{self.choice(VERBS)}_{self.choice(NOUNS)}_{i:03d}", params, "i32", "free")
        if params[0][1] == "i32" and self.chance(self.a.recursion_rate):
            self.make_recursive(mod, fn)
        else:
            fn.body, fn.cost = self.make_body(mod, fn, self.target_fn_sloc(), self.a.fn_budget)
        self.register(mod, fn)

    def make_recursive(self, mod, fn):
        # fn(n, ...) recurses (n & 7) levels deep.
        n = fn.params[0][0]
        acc = ("int", 1)
        for name, t in fn.params[1:]:
            if t == "i32":
                acc = mask(("bin", "+", acc, ("var", name)))
        args = [mask(("bin", "-", ("var", "depth_0"), ("int", 1)))] + [("var", p) for p, _ in fn.params[1:]]
        fn.body = [
            ("let", "depth_0", "i32", ("bin", "&", ("var", n), ("int", 7))),
            ("if", ("cmp", "<=", ("var", "depth_0"), ("int", 0)), [("return", acc)], []),
            ("let", "below_0", "i32", ("call", (mod.index, fn.name), args)),
            ("return", mask(("bin", "+", ("bin", "*", ("var", "below_0"), ("int", 3)), ("var", "depth_0")))),
        ]
        fn.cost = 40

    def make_body(self, mod, fn, target_sloc, budget):
        ctx = BodyContext(self, mod, fn, budget)
        stmts, sloc = [], 0
        while sloc < target_sloc - 3:
            s, lines = ctx.statement(target_sloc - 3 - sloc)
            stmts.append(s)
            sloc += lines
        saved = ctx.begin()
        ret = ctx.rhs()
        stmts += ctx.end(saved)[0]
        stmts.append(("return", ret))
        return flatten(stmts), max(1, ctx.cost)

    def make_entry(self, mod):
        """run_<module>(seed): calls every free fn, enum reader and generic fn of the module once."""
        fn = self.new_fn(mod, f"run_{mod.name}", [("seed", "i32")], "i32", "entry")
        ctx = BodyContext(self, mod, fn, budget=10 ** 9)
        stmts = [("let", "total", "i32", ("var", "seed"))]
        ctx.int_locals.append("total")

        def add(make):
            saved = ctx.begin()
            e = make()
            out, _ = ctx.end(saved)
            if e is None:
                return
            stmts.extend(out)
            update = ("assign", "total", mask(("bin", "+", ("var", "total"), e)))
            if self.chance(self.a.entry_guard_rate):
                # A guarded step, as drivers check state between phases.
                limit = self.rng.randint(512, 3584)
                update = ("if", ("cmp", self.choice(["<", ">", "!="]), ("var", "total"), ("int", limit)), [update], [])
            stmts.append(update)

        makers = {"free": ctx.call, "enum_reader": ctx.call, "generic": ctx.generic_call,
                  "slot_reader": ctx.slot_call, "pick": ctx.pick_call}
        for f in list(mod.fns):
            if f.kind in makers:
                add(lambda f=f: makers[f.kind](f))
        stmts.append(("return", mask(("var", "total"))))
        fn.body = flatten(stmts)
        fn.cost = ctx.cost
        mod.entry = fn
        self.register(mod, fn)


class BodyContext:
    """Generates the statements of one body: locals in scope, loop nesting and dynamic cost."""

    def __init__(self, gen, mod, fn, budget):
        self.g = gen
        self.rng = gen.rng
        self.mod = mod
        self.fn = fn
        self.budget = budget
        self.cost = 0
        self.multiplier = 1
        self.int_locals = [n for n, t in fn.params if t == "i32"]
        self.values = [(n, t) for n, t in fn.params if isinstance(t, tuple) and t[0] == "struct"]
        self.frozen = set(n for n, _ in fn.params)  # params and loop counters are never assigned
        self.counter = 0
        self.pre = []
        self.pre_lines = 0

    def chance(self, p):
        return self.rng.random() < p

    def fresh(self, base):
        self.counter += 1
        return f"{base}_{self.counter}"

    def room(self):
        return max(0, (self.budget - self.cost) // self.multiplier)

    def charge(self, c):
        self.cost += c * self.multiplier

    # Pre-statements: an expression that needs a struct or enum value binds it with a typed let
    # just before the statement being generated.
    def begin(self):
        saved = (self.pre, self.pre_lines)
        self.pre, self.pre_lines = [], 0
        return saved

    def end(self, saved):
        out, lines = self.pre, self.pre_lines
        self.pre, self.pre_lines = saved
        return out, lines

    def bind(self, base, t, value, lines=1):
        name = self.fresh(base)
        self.pre.append(("let", name, t, value))
        self.pre_lines += lines
        self.values.append((name, t))
        return ("var", name)

    # -- values
    def atom(self):
        r = self.rng.random()
        if self.int_locals and r < 0.6:
            return ("var", self.g.choice(self.int_locals))
        if r < 0.8:
            mods = [self.mod] + [self.g.p.modules[v] for v in self.mod.visible[:2]]
            cm = self.g.choice(mods)
            if cm.consts:
                name, value = self.g.choice(cm.consts)
                self.g.note_use(self.mod, cm.index)
                return ("const", cm.index, name, value)
        return ("int", self.rng.randint(1, 97))

    def value_of(self, t):
        """A variable holding a value of struct/enum type t, reusing a local or binding a new one."""
        same = [n for n, vt in self.values if vt == t]
        if same and self.chance(0.9):
            return ("var", self.g.choice(same))
        td = self.g.p.types[t[1]]
        self.g.note_use(self.mod, td.module)
        if td.is_enum and td.generic:
            if self.chance(0.7):
                v = ("variant", td.key, td.variants[1][0], self.value_of(t[2][0]))
            else:
                v = ("variant", td.key, td.variants[0][0], None)
            return self.bind("slot", t, v)
        if td.is_enum:
            vname, pt = self.g.choice(td.variants)
            return self.bind("state", t, ("variant", td.key, vname, self.atom() if pt else None))
        fields = []
        for fname, ft in td.fields:
            if ft == "i32":
                fields.append((fname, self.atom()))
            elif ft == ("param", "T"):
                fields.append((fname, self.value_of(t[2][0])))
            else:
                fields.append((fname, self.value_of(ft)))
        lines = 1 if len(fields) <= 2 else 2 + (len(fields) + 1) // 2
        base = "holder" if td.generic else self.g.choice(NOUNS)
        return self.bind(base, t, ("struct", td.key, fields), lines)

    def instance_type(self, trait, item):
        """A type implementing the trait: a record, or a generic holder of one.

        Each generic item mostly reuses the few types it was already instantiated with, as real
        code does (a generic fn has a handful of instantiations, not one per call site)."""
        pool = self.g.p.instance_pool.setdefault(item, [])
        if pool and (len(pool) >= self.g.a.instances_per_item or self.chance(0.7)):
            t = self.g.choice(pool)
            self.g.note_use(self.mod, self.g.p.types[t[1]].module)
            if t[2]:
                self.g.note_use(self.mod, self.g.p.types[t[2][0][1]].module)
            return t
        recs = self.g.records(self.mod, trait)
        if not recs:
            return None
        holders = self.g.types_visible(self.mod, lambda td: td.generic and not td.is_enum and td.bound == trait)
        if holders and self.chance(0.35):
            t = stype(self.g.choice(holders), stype(self.g.choice(recs)))
        else:
            t = stype(self.g.choice(recs))
        pool.append(t)
        return t

    # -- calls
    def arg(self, t):
        if t == "i32":
            return self.atom() if self.chance(0.85) else mask(("bin", self.g.choice(OPS), self.atom(), self.atom()))
        if t == "bool":
            return ("cmp", "<", self.atom(), self.atom())
        return self.value_of(t)

    def call(self, f):
        self.g.note_use(self.mod, f.module)
        self.charge(f.cost + 1)
        return ("call", (f.module, f.name), [self.arg(t) for _, t in f.params])

    def note_instance(self, item, t):
        self.g.p.instances.add((item, repr(t)))
        if t[2]:
            self.g.p.instances.add((t[1], repr(t[2][0])))

    def generic_call(self, f):
        t = self.instance_type(f.bound, (f.module, f.name))
        if t is None:
            return None
        self.note_instance((f.module, f.name), t)
        self.g.note_use(self.mod, f.module)
        self.charge(f.cost + 1)
        first = self.value_of(t)
        second = first if self.chance(0.5) else self.value_of(t)
        return ("call", (f.module, f.name), [first, second, self.atom()])

    def slot_call(self, f):
        td = self.g.p.types[f.params[0][1][1]]
        t = self.instance_type(td.bound, (f.module, f.name))
        if t is None:
            return None
        self.note_instance((f.module, f.name), t)
        self.note_instance(td.key, t)
        self.g.note_use(self.mod, f.module)
        self.charge(f.cost + 1)
        return ("call", (f.module, f.name), [self.value_of(stype(td, t)), self.atom()])

    def pick_call(self, f):
        pool = self.g.p.instance_pool.setdefault((f.module, f.name), [])
        if pool and (len(pool) >= self.g.a.instances_per_item or self.chance(0.7)):
            td = self.g.p.types[self.g.choice(pool)[1]]
        else:
            recs = self.g.records(self.mod)
            if not recs:
                return None
            td = self.g.choice(recs)
            pool.append(stype(td))
        t = stype(td)
        self.note_instance((f.module, f.name), t)
        self.g.note_use(self.mod, f.module)
        self.charge(f.cost + 1)
        first = self.value_of(t)
        second = first if self.chance(0.5) else self.value_of(t)
        args = [("cmp", "<", self.atom(), self.atom()), first, second]
        chosen = self.bind("chosen", t, ("call", (f.module, f.name), args))
        return ("field", chosen, self.g.choice([n for n, ft in td.fields if ft == "i32"]))

    def method_choices(self, td, room):
        own = self.fn.owner is td
        meths = []
        for m in td.methods:
            if m.cost + 1 > room:
                continue
            if own and td.methods.index(m) >= td.methods.index(self.fn):
                continue  # only methods declared earlier: no mutual recursion
            meths.append(m)
        for tk, fs in td.trait_methods.items():
            meths += [(tk, f) for f in fs]
        return meths

    def operand(self):
        """One term of an int expression; every term is in [0, 4095]."""
        r = self.rng.random()
        if r < self.g.a.atom_rate:
            return self.atom()
        room = self.room()
        if r < 0.66:
            cands = [f for idx in self.g.seen_modules(self.mod) for f in self.g.p.modules[idx].fns
                     if f.kind in ("free", "enum_reader") and f is not self.fn and f.cost + 1 <= room]
            if cands:
                return self.call(self.g.choice(cands))
        if r < 0.80:
            # A method of a record: inherent, or a trait method called directly.
            # Mostly on values already at hand (self, parameters, locals), as in real code.
            recs = [td for td in self.g.records(self.mod) if td.methods or td.trait_methods]
            held = {t[1] for _, t in self.values}
            if self.fn.owner is not None:
                held.add(self.fn.owner.key)
            near = [td for td in recs if td.key in held]
            if near and self.chance(0.85):
                recs = near
            elif not self.chance(self.g.a.construct_rate):
                recs = []
            if recs:
                td = self.g.choice(recs)
                meths = self.method_choices(td, room)
                if meths:
                    meth = self.g.choice(meths)
                    if isinstance(meth, tuple):
                        self.g.note_use(self.mod, self.g.p.traits[meth[0]].module)
                        meth = meth[1]
                    self.charge(meth.cost + 1)
                    if self.fn.owner is td and self.chance(0.5):
                        recv = ("var", "self")
                    else:
                        recv = self.value_of(stype(td))
                    return ("mcall", recv, meth.name, [self.arg(t) for _, t in meth.params[1:]])
        if r < 0.88:
            gens = [f for idx in self.g.seen_modules(self.mod) for f in self.g.p.modules[idx].fns
                    if f.kind in ("generic", "slot_reader", "pick") and f.cost + 1 <= room]
            if gens:
                f = self.g.choice(gens)
                e = {"generic": self.generic_call, "slot_reader": self.slot_call, "pick": self.pick_call}[f.kind](f)
                if e is not None:
                    return e
        if self.values and r < 0.96:
            name, t = self.g.choice(self.values)
            td = self.g.p.types[t[1]]
            ints = [n for n, ft in td.fields if ft == "i32" and not td.is_enum]
            if ints:
                return ("field", ("var", name), self.g.choice(ints))
        return self.atom()

    def rhs(self):
        n = self.g.choice([1, 1, 1, 2, 2, 2, 2, 3, 3])
        terms = []
        scaled = False
        for _ in range(n):
            term = self.operand()
            if self.chance(0.15):
                term = ("bin", "*", term, ("int", self.rng.randint(2, 7)))
                scaled = True
            terms.append(term)
        e = terms[0]
        for term in terms[1:]:
            e = ("bin", self.g.choice(OPS), e, term)
        return mask(e) if n > 1 or scaled else e

    def condition(self):
        return ("cmp", self.g.choice(["<", ">", "<=", ">=", "==", "!="]), self.operand(), self.atom())

    # -- statements: (stmt, sloc)
    def statement(self, room):
        saved = self.begin()
        s, lines = self._statement(room)
        pre, pre_lines = self.end(saved)
        return ("seq", pre + [s]), lines + pre_lines

    def _statement(self, room):
        r = self.rng.random()
        if room >= 3 and self.multiplier <= 6 and r < self.g.a.loop_rate:
            return self.loop(room)
        if room >= 1 and r < self.g.a.loop_rate + self.g.a.if_rate * self.g.a.early_return_share:
            # Early exit, the most common if in verified_compiler: `if (c) { return e; }`.
            cond = self.condition()
            return ("if", cond, [("return", self.rhs())], []), 3
        if room >= 2 and r < self.g.a.loop_rate + self.g.a.if_rate:
            return self.if_stmt(room)
        r = self.rng.random()
        targets = [v for v in self.int_locals if v not in self.frozen]
        if targets and r < 0.3:
            return ("assign", self.g.choice(targets), self.rhs()), 1
        if r < 0.3 + self.g.a.match_rate and room >= 4:
            enums = self.g.types_visible(self.mod, lambda td: td.is_enum and not td.generic)
            if enums:
                td = self.g.choice(enums)
                scrut = self.value_of(stype(td))
                arms = []
                for vn, vt in td.variants:
                    binder = self.fresh("inner") if vt else None
                    arm = mask(("bin", self.g.choice(OPS), ("var", binder) if vt else self.atom(), self.atom()))
                    arms.append((vn, binder, arm))
                name = self.fresh("matched")
                self.int_locals.append(name)
                self.charge(2)
                return ("let", name, "i32", ("match", scrut, td.key, arms)), 2 + len(arms)
        name = self.fresh(self.g.choice(LOCALS))
        stmt = ("let", name, "i32", self.rhs())
        self.int_locals.append(name)
        return stmt, 1

    def scoped(self, room):
        saved = (list(self.int_locals), list(self.values))
        body, lines = [], 0
        while lines < room:
            s, n = self.statement(room - lines)
            body.append(s)
            lines += n
        self.int_locals, self.values = saved
        return body, lines

    def loop(self, room):
        trips = self.rng.randint(2, 5)
        counter = self.fresh("index")
        pre = []
        targets = [v for v in self.int_locals if v not in self.frozen]
        if targets:
            acc = self.g.choice(targets)
        else:
            acc = self.fresh("accum")
            pre.append(("let", acc, "i32", ("int", 1)))
            self.int_locals.append(acc)
        use_for = self.chance(0.2)
        self.frozen.add(counter)
        self.int_locals.append(counter)
        self.multiplier *= trips
        body, lines = self.scoped(max(1, min(room - 4, self.rng.randint(1, 7))))
        self.multiplier //= trips
        self.int_locals.remove(counter)
        body.append(("assign", acc, mask(("bin", "+", ("var", acc), ("bin", "*", ("var", counter), self.atom())))))
        if use_for:
            return ("seq", pre + [("for", counter, ("int", 0), ("int", trips), body)]), len(pre) + lines + 3
        body.append(("assign", counter, ("bin", "+", ("var", counter), ("int", 1))))
        stmts = pre + [("let", counter, "i32", ("int", 0)),
                       ("while", ("cmp", "<", ("var", counter), ("int", trips)), body)]
        return ("seq", stmts), len(pre) + lines + 5

    def if_stmt(self, room):
        cond = self.condition()
        then, lines = self.scoped(max(1, min(room - 2, self.g.choice([1, 1, 1, 2, 2, 3, 4]))))
        other, olines = [], 0
        if self.chance(0.3) and room - lines >= 3:
            other, olines = self.scoped(max(1, min(room - lines - 3, self.g.choice([1, 1, 2, 3]))))
        return ("if", cond, then, other), 2 + lines + (olines + 1 if other else 0)


def flatten(stmts):
    out = []
    for s in stmts:
        k = s[0]
        if k == "seq":
            out += flatten(s[1])
        elif k == "if":
            out.append(("if", s[1], flatten(s[2]), flatten(s[3])))
        elif k == "while":
            out.append(("while", s[1], flatten(s[2])))
        elif k == "for":
            out.append(("for", s[1], s[2], s[3], flatten(s[4])))
        else:
            out.append(s)
    return out


def assigned(stmts, acc):
    for s in stmts:
        if s[0] == "assign":
            acc.add(s[1])
        elif s[0] == "if":
            assigned(s[2], acc)
            assigned(s[3], acc)
        elif s[0] == "while":
            assigned(s[2], acc)
        elif s[0] == "for":
            assigned(s[4], acc)
    return acc


# ---------------------------------------------------------------------------------------------
# Printing


class Printer:
    rust = False

    def __init__(self, program):
        self.p = program
        self.mutable = set()

    def qual(self, idx, here, name):
        return name if idx == here else f"{self.path(idx)}::{name}"

    def type_name(self, t, here):
        if t in ("i32", "bool"):
            return t
        if t[0] == "param":
            return t[1]
        td = self.p.types[t[1]]
        name = self.qual(td.module, here, td.name)
        if td.generic:
            arg = t[2][0] if t[2] else ("param", "T")
            return f"{name}<{self.type_name(arg, here)}>"
        return name

    def trait_name(self, key, here):
        t = self.p.traits[key]
        return self.qual(t.module, here, t.name)

    def operand(self, e, here):
        s = self.expr(e, here)
        return f"({s})" if e[0] in ("bin", "cmp") else s

    def args(self, args, here):
        # Lanius reads `f(path < x, y, z)` as generic arguments of `path`, so a
        # comparison passed as an argument is parenthesized; Rust needs no parens.
        return ", ".join(self.expr(a, here) if self.rust or a[0] != "cmp" else f"({self.expr(a, here)})"
                         for a in args)

    def expr(self, e, here, ind="", top=False):
        k = e[0]
        if k == "int":
            return str(e[1])
        if k == "var":
            return e[1]
        if k == "const":
            return self.qual(e[1], here, e[2])
        if k == "mask":
            inner = e[1]
            s = self.expr(inner, here) if inner[0] == "bin" else self.operand(inner, here)
            return f"({s}) & {MASK}" if top else f"(({s}) & {MASK})"
        if k in ("bin", "cmp"):
            return f"{self.operand(e[2], here)} {e[1]} {self.operand(e[3], here)}"
        if k == "call":
            fn = self.p.fns[e[1]]
            return f"{self.qual(fn.module, here, fn.name)}({self.args(e[2], here)})"
        if k == "mcall":
            return f"{self.expr(e[1], here)}.{e[2]}({self.args(e[3], here)})"
        if k == "field":
            return f"{self.expr(e[1], here)}.{e[2]}"
        if k == "struct":
            td = self.p.types[e[1]]
            name = self.qual(td.module, here, td.name)
            parts = [f"{n}: {self.expr(v, here)}" for n, v in e[2]]
            if len(parts) <= 2:
                return f"{name} {{ {', '.join(parts)} }}"
            rows = [", ".join(parts[i:i + 2]) + "," for i in range(0, len(parts), 2)]
            return f"{name} {{\n" + "".join(f"{ind}    {row}\n" for row in rows) + f"{ind}}}"
        if k == "variant":
            return self.variant(e, here)
        if k == "match":
            td = self.p.types[e[2]]
            arms = [f"{self.pattern(td, v, b, here)} {self.arrow} {self.expr(a, here)}," for v, b, a in e[3]]
            return (self.match_head(self.expr(e[1], here)) + " {\n"
                    + "".join(f"{ind}    {a}\n" for a in arms) + f"{ind}}}")
        raise ValueError(k)

    def stmts(self, stmts, here, ind):
        out = []
        for s in stmts:
            k = s[0]
            if k == "let":
                mut = "mut " if self.rust and s[1] in self.mutable else ""
                out.append(f"{ind}let {mut}{s[1]}: {self.type_name(s[2], here)} = {self.expr(s[3], here, ind, True)};")
            elif k == "assign":
                out.append(f"{ind}{s[1]} = {self.expr(s[2], here, ind, True)};")
            elif k == "return":
                out.append(f"{ind}return {self.expr(s[1], here, ind, True)};")
            elif k == "if":
                out.append(f"{ind}if {self.cond(s[1], here)} {{")
                out += self.stmts(s[2], here, ind + "    ")
                if s[3]:
                    out.append(f"{ind}}} else {{")
                    out += self.stmts(s[3], here, ind + "    ")
                out.append(f"{ind}}}")
            elif k == "while":
                out.append(f"{ind}while {self.cond(s[1], here)} {{")
                out += self.stmts(s[2], here, ind + "    ")
                out.append(f"{ind}}}")
            elif k == "for":
                out.append(f"{ind}for {s[1]} in {self.expr(s[2], here)}{self.range_op}{self.expr(s[3], here)} {{")
                out += self.stmts(s[4], here, ind + "    ")
                out.append(f"{ind}}}")
            else:
                raise ValueError(k)
        return out

    def fn(self, fn, here, ind="", vis="pub "):
        self.mutable = assigned(fn.body, set())
        gens = where = ""
        if fn.generics:
            gens = "<" + ", ".join(g for g, _ in fn.generics) + ">"
            where = self.where_clause(fn, here)
        params = ["self" if name == "self" else f"{name}: {self.type_name(t, here)}" for name, t in fn.params]
        head = f"{ind}{vis}fn {fn.name}{gens}({', '.join(params)}) -> {self.type_name(fn.ret, here)}{where} {{"
        return [head] + self.stmts(fn.body, here, ind + "    ") + [f"{ind}}}"]

    def type_items(self, td, here):
        gens = "<T>" if td.generic else ""
        out = list(self.type_attrs())
        if td.is_enum:
            out.append(f"pub enum {td.name}{gens} {{")
            for vname, pt in td.variants:
                out.append(f"    {vname}" + (f"({self.type_name(pt, here)})" if pt else "") + ",")
        else:
            out.append(f"pub struct {td.name}{gens} {{")
            for fname, ft in td.fields:
                out.append(f"    {self.field_vis}{fname}: {self.type_name(ft, here)},")
        out += ["}", ""]
        target = td.name + gens
        for tk, fns in td.trait_methods.items():
            out.append(self.trait_impl_head(td, tk, target, here))
            for k, fn in enumerate(fns):
                if k:
                    out.append("")
                out += self.fn(fn, here, "    ", self.trait_method_vis)
            out += ["}", ""]
        if td.methods:
            out.append(self.inherent_impl_head(td, target))
            for k, fn in enumerate(td.methods):
                if k:
                    out.append("")
                out += self.fn(fn, here, "    ")
            out += ["}", ""]
        return out

    def items(self, mod):
        here = mod.index
        out = [f"pub const {name}: i32 = {value};" for name, value in mod.consts]
        out.append("")
        for t in mod.traits:
            out.append(f"pub trait {t.name} {{")
            out += [f"    {self.trait_method_vis}fn {mname}(self, k: i32) -> i32;" for mname in t.methods]
            out += ["}", ""]
        for td in mod.types:
            out += self.type_items(td, here)
        for fn in mod.fns:
            out += self.fn(fn, here)
            out.append("")
        return out


class LaniusPrinter(Printer):
    arrow = "->"
    range_op = " .. "
    field_vis = ""
    trait_method_vis = "pub "

    def path(self, idx):
        return f"gen::{self.p.modules[idx].name}"

    def variant(self, e, here):
        td = self.p.types[e[1]]
        name = self.qual(td.module, here, e[2])
        return f"{name}({self.expr(e[3], here)})" if e[3] is not None else name

    def pattern(self, td, variant, binder, here):
        return self.qual(td.module, here, variant) + (f"({binder})" if binder else "")

    def match_head(self, scrut):
        return f"match ({scrut})"

    def cond(self, e, here):
        return f"({self.expr(e, here)})"

    def where_clause(self, fn, here):
        bounds = [f"{g}: " + " + ".join(self.trait_name(t, here) for t in ts) for g, ts in fn.generics if ts]
        return " where " + ", ".join(bounds) if bounds else ""

    def type_attrs(self):
        return []

    def trait_impl_head(self, td, tk, target, here):
        tname = self.trait_name(tk, here)
        if td.generic:
            return f"pub impl<T> {tname} for {target} where T: {self.trait_name(td.bound, here)} {{"
        return f"pub impl {tname} for {target} {{"

    def inherent_impl_head(self, td, target):
        return f"pub impl<T> {target} {{" if td.generic else f"pub impl {target} {{"

    def module(self, mod):
        out = [f"module gen::{mod.name};", ""]
        out += [f"import gen::{self.p.modules[idx].name};" for idx in sorted(mod.imports)]
        if mod.imports:
            out.append("")
        out += self.items(mod)
        return "\n".join(out).rstrip() + "\n"

    def main(self):
        out = ["module app::main;", ""]
        out += [f"import gen::{mod.name};" for mod in self.p.modules]
        out += ["", "fn main() -> i32 {", "    let total: i32 = 0;", "    let part: i32 = 0;"]
        for mod, seed in self.p.main_seeds:
            out += [f"    part = gen::{mod.name}::{mod.entry.name}({seed});", "    print(part);",
                    f"    total = (total + part) & {MASK};"]
        out += ["    print(total);", "    return 0;", "}", ""]
        return "\n".join(out)


class RustPrinter(Printer):
    rust = True
    arrow = "=>"
    range_op = ".."
    field_vis = "pub "
    trait_method_vis = ""
    ALLOW = "#![allow(unused, dead_code, non_snake_case, non_camel_case_types, unused_parens)]"

    def path(self, idx):
        return f"crate::gen::{self.p.modules[idx].name}"

    def variant(self, e, here):
        td = self.p.types[e[1]]
        name = f"{self.qual(td.module, here, td.name)}::{e[2]}"
        return f"{name}({self.expr(e[3], here)})" if e[3] is not None else name

    def pattern(self, td, variant, binder, here):
        return f"{self.qual(td.module, here, td.name)}::{variant}" + (f"({binder})" if binder else "")

    def match_head(self, scrut):
        return f"match {scrut}"

    def cond(self, e, here):
        return self.expr(e, here)

    def where_clause(self, fn, here):
        bounds = [f"{g}: Copy" + "".join(" + " + self.trait_name(t, here) for t in ts) for g, ts in fn.generics]
        return " where " + ", ".join(bounds)

    def type_attrs(self):
        return ["#[derive(Clone, Copy)]"]

    def trait_impl_head(self, td, tk, target, here):
        tname = self.trait_name(tk, here)
        if td.generic:
            return f"impl<T: Copy + {self.trait_name(td.bound, here)}> {tname} for {target} {{"
        return f"impl {tname} for {target} {{"

    def inherent_impl_head(self, td, target):
        return f"impl<T: Copy> {target} {{" if td.generic else f"impl {target} {{"

    def module(self, mod):
        out = [self.ALLOW, ""]
        # Trait methods are called by name, so their traits must be in scope (a Lanius import
        # does this). The generator never assigns parameters, so they never need `mut`.
        uses = [t for t in self.p.traits.values() if t.module in mod.visible]
        out += [f"use {self.path(t.module)}::{t.name};" for t in uses]
        if uses:
            out.append("")
        out += self.items(mod)
        return "\n".join(out).rstrip() + "\n"

    def crate_root(self):
        out = [self.ALLOW, "", "mod gen;", "", "fn main() {", "    let mut total: i32 = 0;", "    let mut part: i32 = 0;"]
        for mod, seed in self.p.main_seeds:
            out += [f"    part = crate::gen::{mod.name}::{mod.entry.name}({seed});", '    println!("{}", part);',
                    f"    total = (total + part) & {MASK};"]
        out += ['    println!("{}", total);', "}", ""]
        return "\n".join(out)

    def gen_mod(self):
        return "".join(f"pub mod {mod.name};\n" for mod in self.p.modules)


# ---------------------------------------------------------------------------------------------


def evaluate(program):
    ev = Evaluator(program)
    total, lines = 0, []
    for mod, seed in program.main_seeds:
        part = ev.call(mod.entry, [seed])
        lines.append(part)
        total = (total + part) & MASK
    lines.append(total)
    return lines, ev.steps


def sloc_of(text):
    return sum(1 for line in text.split("\n") if line.strip() and not line.strip().startswith("//"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--preset", choices=sorted(PRESETS, key=PRESETS.get))
    ap.add_argument("--modules", type=int)
    ap.add_argument("--seed", type=int, default=20)
    ap.add_argument("--out", required=True)
    ap.add_argument("--rust-out")
    ap.add_argument("--loop-rate", type=float, default=0.21, help="share of statements that start a loop")
    ap.add_argument("--if-rate", type=float, default=0.72, help="share of statements that are an if")
    ap.add_argument("--recursion-rate", type=float, default=0.035)
    ap.add_argument("--early-return-share", type=float, default=0.8, help="share of ifs that return early")
    ap.add_argument("--entry-guard-rate", type=float, default=0.6, help="share of entry steps under an if")
    ap.add_argument("--construct-rate", type=float, default=0.3,
                    help="chance a method call builds a new receiver instead of skipping")
    ap.add_argument("--match-rate", type=float, default=0.04, help="share of simple statements that are a match")
    ap.add_argument("--atom-rate", type=float, default=0.22, help="share of expression terms that are a plain value")
    ap.add_argument("--instances-per-item", type=int, default=2, help="most type arguments per generic item")
    ap.add_argument("--free-fns-min", type=int, default=3)
    ap.add_argument("--free-fns-max", type=int, default=6)
    ap.add_argument("--generic-fn-rate", type=float, default=0.5, help="chance for each of 3 generic fn slots per module")
    ap.add_argument("--generic-type-rate", type=float, default=0.25, help="chance of a generic user type per module")
    ap.add_argument("--no-generic-enums", dest="generic_enums", action="store_false")
    ap.add_argument("--trait-impl-rate", type=float, default=0.75)
    ap.add_argument("--inherent-impl-rate", type=float, default=0.32)
    ap.add_argument("--modules-per-trait", type=float, default=14)
    ap.add_argument("--random-imports", type=int, default=2, help="random earlier modules each module may use")
    ap.add_argument("--fn-budget", type=int, default=300, help="dynamic cost budget per function")
    a = ap.parse_args()
    if not a.modules and not a.preset:
        ap.error("give --preset or --modules")
    def generate(n):
        program = Program(n)
        Generator(program, a, random.Random(a.seed)).build()
        lp = LaniusPrinter(program)
        sources = {f"lanius/src/gen/{mod.name}.lani": lp.module(mod) for mod in program.modules}
        sources["lanius/main.lani"] = lp.main()
        return program, sources

    if a.modules:
        n = a.modules
        program, sources = generate(n)
    else:
        target = PRESETS[a.preset]
        tried = {}
        n = max(2, round(target / SLOC_PER_MODULE_GUESS))
        for _ in range(5):
            if n in tried:
                break
            program, sources = generate(n)
            got = sum(sloc_of(t) for t in sources.values())
            tried[n] = (abs(got - target), program, sources)
            if abs(got - target) <= 0.03 * target:
                break
            n = max(2, round(n * target / got))
        n = min(tried, key=lambda k: tried[k][0])
        _, program, sources = tried[n]
    lines, steps = evaluate(program)
    expected = "".join(f"{v}\n" for v in lines)

    out = Path(a.out)
    (out / "lanius" / "src" / "gen").mkdir(parents=True, exist_ok=True)
    for rel, text in sources.items():
        (out / rel).write_text(text)
    total_bytes = sum(len(t.encode()) for t in sources.values())
    sloc = sum(sloc_of(t) for t in sources.values())
    manifest = {
        "schema": "lanius.generic-workload.v1",
        "generator": "tools/generate_project_workload.py",
        "layout": "project",
        "entry": "lanius/main.lani",
        "source_root": "lanius/src",
        "seed": a.seed,
        "modules": n,
        "expected_stdout": expected,
        "expected_exit_code": 0,
        "options": {k: v for k, v in sorted(vars(a).items()) if k not in ("out", "rust_out")},
        "statistics": {"files": len(sources), "bytes": total_bytes, "nonblank_code_lines": sloc,
                       "evaluation_steps": steps, "generic_instances": len(program.instances),
                       "generic_items": len({i for i, _ in program.instances})},
        "sources": {rel: {"bytes": len(t.encode()), "sha256": hashlib.sha256(t.encode()).hexdigest()}
                    for rel, t in sorted(sources.items())},
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if a.rust_out:
        rp = RustPrinter(program)
        r = Path(a.rust_out)
        (r / "src" / "gen").mkdir(parents=True, exist_ok=True)
        (r / "Cargo.toml").write_text('[package]\nname = "lanius_twin"\nversion = "0.1.0"\nedition = "2021"\n\n'
                                      '[dependencies]\n\n[workspace]\n')
        (r / "src" / "main.rs").write_text(rp.crate_root())
        (r / "src" / "gen.rs").write_text(rp.gen_mod())
        for mod in program.modules:
            (r / "src" / "gen" / f"{mod.name}.rs").write_text(rp.module(mod))
        (r / "expected_stdout.txt").write_text(expected)
    print(f"{n} modules, {len(sources)} files, {total_bytes} bytes, {sloc} SLOC, {steps} evaluation steps, "
          f"{len(program.instances)} generic instances")


if __name__ == "__main__":
    main()
