#!/usr/bin/env python3
"""TypeScript rendering of the corpus-calibrated typical project.

Every non-entry module is one ES module under ``src/`` that imports each
dependency as ``import * as <name> from "./<name>.js"``; ``src/main.ts``
imports the other roots and its own dependencies. The tsconfig uses
``module``/``moduleResolution`` ``nodenext`` and a ``package.json`` with
``"type": "module"`` sits next to it, so the files compile as ES modules and
node runs ``out/main.js`` as ESM. Compiler options otherwise follow the
single-file stress lane: target ES2022, strict, skipLibCheck, noEmitOnError,
and no ``lib`` override. @types/node is not installed; ``src/node.d.ts``
declares the few node APIs the runtime probe imports.

Integer semantics. Every value is an i32 masked to 12 bits, and no product or
sum leaves the safe-integer range, so ``+``, ``-``, ``*`` and ``& 4095`` on
numbers give the same results as i32 arithmetic. ``%`` already truncates
toward zero like C and Rust. The two divisions use ``Math.trunc``
(``(seed / 7)`` in ``enum_tuple_patterns``) or are followed by ``^= 0``
(``value /= 2`` in ``operator_forms``). The bitwise operators coerce to i32,
which makes ``trunc(x) % m`` and ``trunc(x % m)`` agree. ``<<``, ``>>`` and
``^`` already work on i32.

Construct substitutions:
- Rust enums with payloads (Adjustment, CoordinateEvent, PatternListEvent,
  PublicChoice) become discriminated unions on a ``kind`` field. Tuple
  payloads are tuple-typed ``payload`` fields destructured in the ``case``
  arm, including the empty ``[]`` payload. ``match`` becomes ``switch``.
- Structs with methods (ServiceState, BorrowedValue, StatementRecord,
  PublicRecord) become classes with readonly parameter properties. Plain
  structs (Envelope, TrailingRecord, GenericPair, EmptyRecord) become
  interfaces built from object literals.
- Traits and trait bounds (``contracts``, ``bound_list_forms``) become generic
  interfaces implemented by object literals and passed as explicit policy
  arguments (dictionary passing, as in the C and Zig twins). Multiple bounds
  become an intersection of those interfaces.
- The const generic ``<const N: usize>`` becomes a TypeScript ``const`` type
  parameter over a readonly tuple, so the call site infers the literal
  length-4 tuple type.
- Borrowed views (``&self``, ``&[i32]``) become a class method and a
  ``readonly number[]`` parameter.
- ``extern "C" fn getpid`` becomes a module-local ``declare const process``
  read as ``process.pid``; the unbound ``extern fn unbound_probe`` becomes a
  ``declare function`` that is never called. ``public_items`` drops its
  ``extern`` item, as the Rust twin does.
- Primitive types: u8 is ``1 & 0xff``, u32 is ``2 >>> 0``, usize is a plain
  number, i64 is the BigInt ``4n``, f32 is ``Math.fround``, char and str are
  strings, and the null pointer is ``null``. ``literal_data`` stores its f32
  ratio with ``Math.fround`` too.
- Ranges (``1..=3``, ``..3``, ``..=2``, ``2..``, ``..``) become C-style
  ``for`` loops; the open-ended ones are ``for (;;)``-style loops with
  ``break``.
- The fixed array iteration in ``iterable_forms`` is ``for...of``.
- Type aliases (SummaryScore, GenericIdentity, PublicScore) are ``type``
  aliases; public items are ``export``ed. Trailing commas are kept wherever
  TypeScript accepts them: parameters, arguments, array, tuple and object
  literals, destructuring patterns and type parameter lists. TypeScript
  rejects them in type argument lists (TS1009), so those have none.
- The planner's nested-scope shadowing declares ``preview`` again in an inner
  block, because ``const total = total`` is a temporal-dead-zone error.
- ``let deferred: number;`` is the uninitialized typed local.
- The runtime probe allocates a ``Uint8Array``, reads ``argv`` and ``cwd``
  from ``node:process``, ``Date.now()`` for time, ``getRandomValues`` from
  ``node:crypto`` for randomness, and opens and closes ``lanius/main.lani``
  with ``openSync``/``closeSync`` from ``node:fs``. Output is ``console.log``
  followed by ``exit(0)``.
"""

from __future__ import annotations

import json

from typical_project_constructs import RARE_SCORE_FUNCTIONS, rare_patterns_for_module
from typical_project_model import (
    VALUE_MASK,
    Module,
    Rule,
    TypicalProject,
    dependency_indices,
)


M = VALUE_MASK

TSCONFIG = {
    "compilerOptions": {
        "target": "ES2022",
        "module": "nodenext",
        "moduleResolution": "nodenext",
        "strict": True,
        "skipLibCheck": True,
        "noEmitOnError": True,
        "rootDir": "src",
        "outDir": "out",
    },
    "include": ["src"],
}

PACKAGE_JSON = {"private": True, "type": "module"}

NODE_DECLARATIONS = """declare module "node:fs" {
    export function openSync(path: string, flags: string): number;
    export function closeSync(fd: number): void;
}

declare module "node:process" {
    export const argv: readonly string[];
    export function cwd(): string;
    export function exit(code?: number): never;
}

declare module "node:crypto" {
    export function getRandomValues<T extends Uint32Array>(array: T): T;
}
"""

RUNTIME_PROBE = """function runtime_probe(): number {
    const memory: Uint8Array = new Uint8Array(32);
    memory[0] = 1;
    if (argv.length < 1) { return 1; }
    if (cwd().length <= 0) { return 2; }
    if (Date.now() <= 0) { return 3; }
    const random_values: Uint32Array = getRandomValues(new Uint32Array(1));
    if (random_values.length !== 1) { return 4; }
    let source: number;
    try {
        source = openSync("lanius/main.lani", "r");
    } catch {
        return 5;
    }
    closeSync(source);
    if (memory[0] !== 1) { return 6; }
    return 0;
}

"""


def render_ts_project(project: TypicalProject) -> dict[str, str]:
    files = {
        "tsconfig.json": json.dumps(TSCONFIG, indent=2) + "\n",
        "package.json": json.dumps(PACKAGE_JSON, indent=2) + "\n",
        "src/node.d.ts": NODE_DECLARATIONS,
    }
    for module in project.modules:
        if module.index == project.entry_index:
            continue
        files[f"src/{module.name}.ts"] = (
            _imports(project, dependency_indices(module))
            + "\n"
            + _module_body(project, module, exported=True)
        )
    entry = project.modules[project.entry_index]
    imported = sorted(
        (set(project.roots) - {project.entry_index}) | set(dependency_indices(entry))
    )
    calls = []
    for index in project.roots:
        call = (
            "evaluate(7)"
            if index == project.entry_index
            else f"{project.modules[index].name}.evaluate(7)"
        )
        calls.append(f"    total = (total + {call}) & {M};")
    files["src/main.ts"] = (
        'import { getRandomValues } from "node:crypto";\n'
        'import { closeSync, openSync } from "node:fs";\n'
        'import { argv, cwd, exit } from "node:process";\n'
        + _imports(project, imported)
        + "\n"
        + _module_body(project, entry, exported=False)
        + "\n"
        + RUNTIME_PROBE
        + "function main(): void {\n"
        "    const runtime_status: number = runtime_probe();\n"
        "    if (runtime_status !== 0) { exit(runtime_status); }\n"
        "    let total: number = 0;\n"
        + "\n".join(calls)
        + "\n    console.log(total);\n    exit(0);\n}\n\nmain();\n"
    )
    return files


def _imports(project: TypicalProject, indices) -> str:
    return "".join(
        f'import * as {project.modules[index].name} from "./{project.modules[index].name}.js";\n'
        for index in indices
    )


def _module_body(project: TypicalProject, module: Module, exported: bool) -> str:
    export = "export " if exported else ""
    body = render_ts_archetype(module.archetype, module.index)
    body += render_ts_rare_patterns(module.index)
    body += "".join(_render_rule(rule) for rule in module.rules)
    lines = [
        f"{export}function base_rate(value: number): number {{ return (value + {module.base_rate} + {module.index * 3}) & {M}; }}",
        "",
        f"{export}function evaluate(seed: number): number {{",
        "    let total: number = base_rate(seed);",
        f"    total = (total + workload_score(seed)) & {M};",
    ]
    if rare_patterns_for_module(module.index):
        lines.append(f"    total = (total + rare_construct_score(seed)) & {M};")
    for rule in module.rules:
        lines.append(f"    total = {rule.name}(total, seed);")
    for child, salt in zip(module.children, module.child_salts):
        name = project.modules[child].name
        lines.append(
            f"    total = (total + {name}.evaluate((seed + {salt}) & {M})) & {M};"
        )
    for dependency, salt in zip(module.support_dependencies, module.support_salts):
        name = project.modules[dependency].name
        lines.append(
            f"    total = (total + {name}.base_rate((seed + {salt}) & {M})) & {M};"
        )
    lines.extend(("    return total;", "}", ""))
    return body + "\n".join(lines)


def _render_rule(rule: Rule) -> str:
    lines = [
        f"function {rule.name}(value: number, context: number): number {{",
        "    let result: number = value;",
    ]
    for step in rule.steps:
        if step.kind == "offset":
            lines.append(f"    result = (result + {step.a} + context) & {M};")
        elif step.kind == "scale":
            lines.append(f"    result = (result * {step.a % 7 + 2} + {step.b}) & {M};")
        elif step.kind == "threshold":
            lines.extend(
                (
                    f"    if (result > {512 + step.b % 3072}) {{",
                    f"        result = (result - {step.a}) & {M};",
                    "    } else {",
                    f"        result = (result + {step.a}) & {M};",
                    "    }",
                )
            )
        elif step.kind == "clamp":
            maximum = 1024 + step.b % 3072
            lines.extend(
                (
                    f"    if (result > {maximum}) {{",
                    f"        result = {maximum};",
                    "    }",
                )
            )
        else:
            raise ValueError(step.kind)
    lines.extend(("    return result;", "}", ""))
    return "\n".join(lines) + "\n"


def render_ts_archetype(archetype: str, index: int) -> str:
    if archetype == "policy":
        return f"""type Adjustment =
    | {{ readonly kind: "add"; readonly amount: number }}
    | {{ readonly kind: "hold" }};

function choose_adjustment(seed: number): Adjustment {{
    if ((seed & 1) === 0) {{
        return {{ kind: "add", amount: (seed % 7) + 1 }};
    }}
    return {{ kind: "hold" }};
}}

function workload_score(seed: number): number {{
    const adjustment: Adjustment = choose_adjustment(seed);
    switch (adjustment.kind) {{
        case "add":
            return (seed + adjustment.amount) & {M};
        case "hold":
            return (seed - 1) & {M};
    }}
}}

"""
    if archetype == "processor":
        return f"""function workload_score(seed: number): number {{
    const values: readonly number[] = [seed, {index & 31}, 3, 7, 11, 13];
    let cursor: number = 0;
    let total: number = 0;
    while (cursor < values.length) {{
        if (cursor === 1) {{
            cursor += 1;
            continue;
        }}
        if (cursor === 5) {{
            break;
        }}
        total = (total + values[cursor]) & {M};
        cursor += 1;
    }}
    return total;
}}

"""
    if archetype == "service":
        return f"""class ServiceState {{
    constructor(readonly left: number, readonly right: number) {{}}

    static create(seed: number): ServiceState {{
        return new ServiceState((seed + {index}) & {M}, (seed * 2 + 3) & {M});
    }}

    adjusted(amount: number): ServiceState {{
        return new ServiceState(this.left + amount, this.right - amount);
    }}

    score(): number {{
        return (this.left * 3 + this.right) & {M};
    }}
}}

function workload_score(seed: number): number {{
    return ServiceState.create(seed).adjusted({index % 7 + 1}).score();
}}

"""
    if archetype == "planner":
        return f"""function first_eligible(seed: number): number {{
    for (let candidate = 0; candidate < 6; candidate++) {{
        if ((seed + candidate) % 4 === 0) {{
            return candidate;
        }}
    }}
    return 6;
}}

function workload_score(seed: number): number {{
    let total: number = 0;
    const limit: number = {3 + index % 4};
    for (let outer = 0; outer < limit; outer++) {{
        for (let inner = 0; inner < 3; inner++) {{
            if (inner === 1 && outer % 2 === 0) {{
                continue;
            }}
            total = (total + seed + outer * 3 + inner) & {M};
        }}
    }}
    const preview: number = total;
    {{
        const preview: number = 0;
        if (preview < 0) {{ return 0; }}
    }}
    return (total + first_eligible(seed)) & {M};
}}

"""
    if archetype == "tracker":
        return f"""function decay(value: number, remaining: number): number {{
    if (remaining <= 0) {{
        return value;
    }}
    const mixed: number = ((value << 1) ^ (value >> 1) ^ {index}) & {M};
    return decay(mixed, remaining - 1);
}}

function workload_score(seed: number): number {{
    const delta: number = -{index % 5 + 1};
    const enabled: boolean = !false;
    if (enabled) {{
        return (decay(seed, 3) - delta) & {M};
    }}
    return 0;
}}

"""
    if archetype == "summary":
        return f"""type SummaryScore = number;

const SUMMARY_OFFSET: SummaryScore = {index};

interface Envelope<T> {{
    readonly value: T;
}}

function unwrap<T>(envelope: Envelope<T>): T {{
    return envelope.value;
}}

function workload_score(seed: number): number {{
    const envelope: Envelope<number> = {{ value: seed + SUMMARY_OFFSET }};
    return unwrap(envelope) & {M};
}}

"""
    raise ValueError(archetype)


def render_ts_rare_patterns(index: int) -> str:
    patterns = rare_patterns_for_module(index)
    if not patterns:
        return ""
    definitions = "".join(_render_rare_pattern(pattern, index) for pattern in patterns)
    statements: list[str] = []
    for pattern in patterns:
        if pattern in RARE_SCORE_FUNCTIONS:
            function, arguments = RARE_SCORE_FUNCTIONS[pattern]
            statements.append(f"    total = (total + {function}({arguments})) & {M};")
        elif pattern == "contracts":
            statements.append(
                f"    total = (total + preserve_scored(seed, i32_score_policy)) & {M};"
            )
        elif pattern == "const_generic":
            statements.append(
                f"    total = (total + first_const_generic(seed, [seed, {index}, 3, 7])) & {M};"
            )
        elif pattern == "borrowed_views":
            statements.extend(
                (
                    "    const borrowed: BorrowedValue = new BorrowedValue(seed);",
                    f"    total = (total + borrowed.borrowed_marker()) & {M};",
                    f"    total = (total + first_slice([seed, {index}, 3, 7])) & {M};",
                )
            )
        elif pattern == "foreign_api":
            statements.extend(
                (
                    "    const observed_process: number = process.pid;",
                    "    if (observed_process < 0) { return 1; }",
                )
            )
        else:
            raise ValueError(pattern)
    return (
        definitions
        + "function rare_construct_score(seed: number): number {\n"
        + "    let total: number = 0;\n"
        + "\n".join(statements)
        + "\n    return total;\n}\n\n"
    )


def _render_rare_pattern(pattern: str, index: int) -> str:
    if pattern == "contracts":
        return f"""interface ScorePolicy<T> {{
    score_policy(value: T): number;
}}

const i32_score_policy: ScorePolicy<number> = {{
    score_policy(value: number): number {{
        return value & {M};
    }},
}};

function preserve_scored<T>(value: T, _policy: ScorePolicy<T>): T {{
    return value;
}}

"""
    if pattern == "const_generic":
        return """function first_const_generic<const Values extends readonly number[]>(first: number, _values: Values): number {
    return first;
}

"""
    if pattern == "borrowed_views":
        return """class BorrowedValue {
    constructor(readonly value: number) {}

    borrowed_marker(): number {
        return this.value;
    }
}

function first_slice(values: readonly number[]): number {
    return values[0];
}

"""
    if pattern == "foreign_api":
        return """declare const process: { readonly pid: number };

"""
    if pattern == "literal_data":
        return f"""function literal_metadata(): number {{
    const label: string = "module-{index}";
    const delimiter: string = ':';
    const ratio: number = Math.fround(1.25);
    return 0;
}}

"""
    if pattern == "language_forms":
        return """declare function unbound_probe(): number;

function zero_value(): number {
    return 0;
}

function record_positive(value: number): void {
    if (value > 0) {
        return;
    }
}

function language_forms(seed: number): number {
    const inferred = +(seed);
    const grouped: number = ((inferred));
    record_positive(grouped);
    return grouped + zero_value();
}

"""
    if pattern == "operator_forms":
        return f"""function operator_forms(seed: number): number {{
    let value: number = seed;
    value += 3;
    value -= 3;
    value *= 2;
    value /= 2;
    value %= {M + 1};
    value ^= 0;
    value <<= 1;
    value >>= 1;
    value &= {M};
    value |= 0;
    return value;
}}

"""
    if pattern == "primitive_forms":
        return """function primitive_forms(): number {
    const tiny: number = 1 & 0xff;
    const unsigned: number = 2 >>> 0;
    const count: number = 3;
    const wide: bigint = 4n;
    const decimal: number = Math.fround(1.5);
    const truth: boolean = true;
    const letter: string = 'x';
    const text: string = "types";
    const address: object | null = null;
    return 0;
}

"""
    if pattern == "range_forms":
        return f"""function range_forms(seed: number): number {{
    let total: number = seed;
    for (let value = 1; value <= 3; value++) {{
        total = (total + value) & {M};
    }}
    for (let value = 0; value < 3; value++) {{
        total = (total + value) & {M};
    }}
    for (let value = 0; value <= 2; value++) {{
        total = (total + value) & {M};
    }}
    for (let value = 2; ; value++) {{
        total = (total + value) & {M};
        if (value === 4) {{ break; }}
    }}
    for (let value = 0; ; value++) {{
        total = (total + value) & {M};
        if (value === 2) {{ break; }}
    }}
    return (total - 24) & {M};
}}

"""
    if pattern == "match_forms":
        return """function integer_pattern_score(value: number): number {
    switch (value) {
        case 0:
            return 5;
        case 1:
            return 7;
        default:
            return 9;
    }
}

function boolean_pattern_score(value: boolean): number {
    switch (value) {
        case true:
            return 3;
        case false:
            return 4;
    }
}

function match_forms(seed: number): number {
    return integer_pattern_score(seed % 3) + boolean_pattern_score((seed & 1) === 0);
}

"""
    if pattern == "enum_tuple_patterns":
        return """type CoordinateEvent =
    | { readonly kind: "moved"; readonly payload: readonly [number, number] }
    | { readonly kind: "idle" };

function coordinate_event_score(event: CoordinateEvent): number {
    switch (event.kind) {
        case "moved": {
            const [x, y] = event.payload;
            return x * 3 + y;
        }
        case "idle":
            return 1;
    }
}

function enum_tuple_patterns(seed: number): number {
    const moved: CoordinateEvent = { kind: "moved", payload: [seed % 7, Math.trunc(seed / 7) % 7] };
    const idle: CoordinateEvent = { kind: "idle" };
    return coordinate_event_score(moved) + coordinate_event_score(idle);
}

"""
    if pattern == "iterable_forms":
        return f"""function iterable_forms(seed: number): number {{
    const values: readonly number[] = [seed, 2, 3, 4];
    let total: number = 0;
    for (const value of values) {{
        total = (total + value) & {M};
    }}
    return (total - 9) & {M};
}}

"""
    if pattern == "trailing_lists":
        return """interface TrailingRecord {
    readonly left: number;
    readonly right: number;
}

function trailing_sum(left: number, right: number,): number {
    const values: readonly number[] = [left, right,];
    const record: TrailingRecord = {
        left: values[0],
        right: values[1],
    };
    return record.left + record.right;
}

function trailing_lists(seed: number): number {
    return trailing_sum(seed, 0,);
}

"""
    if pattern == "generic_arity":
        return """interface GenericPair<Left, Right,> {
    readonly left: Left;
    readonly right: Right;
}

type GenericIdentity<Value,> = Value;

function generic_pair_left(value: GenericPair<number, boolean>): number {
    const left: GenericIdentity<number> = value.left;
    return left;
}

function generic_arity(seed: number): number {
    const pair: GenericPair<number, boolean> = {
        left: seed,
        right: true,
    };
    return generic_pair_left(pair);
}

"""
    if pattern == "pattern_list_forms":
        return """type PatternListEvent =
    | { readonly kind: "empty"; readonly payload: readonly [] }
    | { readonly kind: "value"; readonly payload: readonly [number,] };

function pattern_list_score(value: PatternListEvent): number {
    switch (value.kind) {
        case "empty": {
            const [] = value.payload;
            return 0;
        }
        case "value": {
            const [inner,] = value.payload;
            return inner;
        }
    }
}

function pattern_list_forms(seed: number): number {
    const empty: PatternListEvent = { kind: "empty", payload: [] };
    const value: PatternListEvent = { kind: "value", payload: [seed] };
    return pattern_list_score(empty) + pattern_list_score(value);
}

"""
    if pattern == "bound_list_forms":
        return """interface BoundScorePolicy<T> {
    bound_score_policy(value: T): number;
}

interface StableBoundPolicy<T> {
    stable_bound_policy(value: T): number;
}

interface PairBoundPolicy<Left, Right> {
    pair_bound_policy(left: Left, right: Right): number;
}

const i32_bound_policies: BoundScorePolicy<number> & StableBoundPolicy<number> & PairBoundPolicy<number, boolean> = {
    bound_score_policy(value: number): number { return value; },
    stable_bound_policy(value: number): number { return value; },
    pair_bound_policy(left: number, _right: boolean): number { return left; },
};

const bool_bound_policy: BoundScorePolicy<boolean> = {
    bound_score_policy(value: boolean): number {
        if (value) { return 1; }
        return 0;
    },
};

function preserve_bound_pair<Left, Right,>(
    left: Left,
    _right: Right,
    _left_policy: BoundScorePolicy<Left> & StableBoundPolicy<Left> & PairBoundPolicy<Left, Right>,
    _right_policy: BoundScorePolicy<Right>,
): Left {
    return left;
}

function bound_list_forms(seed: number): number {
    return preserve_bound_pair(seed, true, i32_bound_policies, bool_bound_policy);
}

"""
    if pattern == "statement_postfix_forms":
        return """class StatementRecord {
    constructor(readonly value: number) {}

    statement_value(): number {
        return this.value;
    }
}

function observe_statement(_value: number): void {
    return;
}

function make_statement_record(value: number): StatementRecord {
    return new StatementRecord(value);
}

function statement_postfix_forms(seed: number): number {
    let deferred: number;
    observe_statement(0);
    const record: StatementRecord = new StatementRecord(seed);
    return record.statement_value() + make_statement_record(0).value;
}

"""
    if pattern == "public_items":
        return """export const PUBLIC_ZERO: number = 0;

export type PublicScore = number;

export class PublicRecord {
    constructor(readonly value: PublicScore) {}

    read(): number {
        return this.value;
    }
}

export type PublicChoice =
    | { readonly kind: "selected"; readonly value: number }
    | { readonly kind: "empty" };

export interface PublicPolicy<T> {
    public_policy(value: T): number;
}

function public_adjustment(choice: PublicChoice): number {
    switch (choice.kind) {
        case "selected":
            return choice.value;
        case "empty":
            return 0;
    }
}

function public_items(seed: number): number {
    const record: PublicRecord = new PublicRecord(seed);
    const choice: PublicChoice = { kind: "selected", value: 0 };
    return record.read() + public_adjustment(choice) + PUBLIC_ZERO;
}

"""
    if pattern == "empty_aggregates":
        return """interface EmptyRecord {}

function empty_aggregates(seed: number): number {
    const empty_record: EmptyRecord = {};
    const empty_values: readonly [] = [];
    return seed;
}

"""
    raise ValueError(pattern)
