#!/usr/bin/env python3
"""Shared semantic model and emitters for comparative compiler workloads."""

from __future__ import annotations

import random
from collections import Counter
from dataclasses import dataclass


LANGUAGES = ("rust", "c", "cpp", "zig", "lanius")
VALUE_MASK = 4095


@dataclass(frozen=True)
class Operation:
    kind: str
    a: int
    b: int


@dataclass(frozen=True)
class Leaf:
    name: str
    index: int
    family: int
    initial_factor: int
    initial_bias: int
    operations: tuple[Operation, ...]
    family_a: int
    family_b: int
    family_c: int


@dataclass(frozen=True)
class Reducer:
    name: str
    left: str
    right: str
    left_salt: int
    right_salt: int
    bias: int
    threshold: int
    then_salt: int
    else_salt: int


@dataclass(frozen=True)
class Workload:
    seed: int
    leaves: tuple[Leaf, ...]
    reducers: tuple[Reducer, ...]
    root: str
    max_call_depth: int

    @property
    def function_count(self) -> int:
        return len(self.leaves) + len(self.reducers)

    def structure(self) -> dict[str, object]:
        families = Counter(leaf.family for leaf in self.leaves)
        operations = Counter(
            operation.kind
            for leaf in self.leaves
            for operation in leaf.operations
        )
        return {
            "leaf_function_count": len(self.leaves),
            "reduction_function_count": len(self.reducers),
            "reachable_function_count": self.function_count,
            "all_functions_reachable": True,
            "call_edge_count": len(self.reducers) * 2,
            "max_call_depth": self.max_call_depth,
            "leaf_family_counts": {
                family_name(index): families[index] for index in range(5)
            },
            "operation_counts": {
                kind: operations[kind]
                for kind in ["add", "mul", "xor", "shift", "branch"]
            },
        }


def build_workload(seed: int, leaf_count: int) -> Workload:
    if leaf_count <= 0:
        raise ValueError("leaf_count must be positive")
    leaves = tuple(build_leaf(seed, index) for index in range(leaf_count))
    reducers: list[Reducer] = []
    current = [leaf.name for leaf in leaves]
    level = 0
    while len(current) > 1:
        following: list[str] = []
        for pair_index in range(0, len(current), 2):
            if pair_index + 1 == len(current):
                following.append(current[pair_index])
                continue
            reducer_index = pair_index // 2
            rng = random.Random((seed << 32) ^ (level << 20) ^ reducer_index ^ 0xA17E)
            reducer = Reducer(
                name=f"reduce_{level:02d}_{reducer_index:07d}",
                left=current[pair_index],
                right=current[pair_index + 1],
                left_salt=rng.randrange(1, 97),
                right_salt=rng.randrange(1, 97),
                bias=rng.randrange(1, 1024),
                threshold=rng.randrange(512, 3584),
                then_salt=rng.randrange(1, 1024),
                else_salt=rng.randrange(1, 1024),
            )
            reducers.append(reducer)
            following.append(reducer.name)
        current = following
        level += 1
    return Workload(seed, leaves, tuple(reducers), current[0], level + 1)


def build_leaf(seed: int, index: int) -> Leaf:
    rng = random.Random((seed << 32) ^ index ^ 0x5EED5EED)
    operations = []
    kinds = ("add", "mul", "xor", "shift", "branch")
    for _ in range(6 + rng.randrange(7)):
        kind = rng.choice(kinds)
        if kind == "mul":
            a = rng.choice((3, 5, 7, 9, 11, 13))
        elif kind == "shift":
            a = rng.randrange(1, 4)
        elif kind == "branch":
            a = 1 << rng.randrange(0, 5)
        else:
            a = rng.randrange(1, 2048)
        operations.append(Operation(kind, a, rng.randrange(1, 2048)))
    return Leaf(
        name=f"leaf_{index:07d}",
        index=index,
        family=(index + seed) % 5,
        initial_factor=rng.choice((3, 5, 7, 9, 11, 13, 17)),
        initial_bias=rng.randrange(1, 2048),
        operations=tuple(operations),
        family_a=rng.randrange(1, 1024),
        family_b=rng.randrange(1, 1024),
        family_c=rng.randrange(1, 1024),
    )


def evaluate(workload: Workload, x: int = 7) -> int:
    leaves = {leaf.name: leaf for leaf in workload.leaves}
    reducers = {reducer.name: reducer for reducer in workload.reducers}

    def visit(name: str, argument: int) -> int:
        if name in leaves:
            return evaluate_leaf(leaves[name], argument)
        reducer = reducers[name]
        left = visit(reducer.left, (argument + reducer.left_salt) & VALUE_MASK)
        right = visit(reducer.right, (argument + reducer.right_salt) & VALUE_MASK)
        mixed = (left + right + reducer.bias) & VALUE_MASK
        if mixed < reducer.threshold:
            return (mixed + argument + reducer.then_salt) & VALUE_MASK
        return (mixed * 3 + reducer.else_salt) & VALUE_MASK

    return visit(workload.root, x)


def evaluate_leaf(leaf: Leaf, x: int) -> int:
    value = (x * leaf.initial_factor + leaf.initial_bias) & VALUE_MASK
    for operation in leaf.operations:
        if operation.kind == "add":
            value = (value + operation.a + x) & VALUE_MASK
        elif operation.kind == "mul":
            value = (value * operation.a + operation.b) & VALUE_MASK
        elif operation.kind == "xor":
            value = (value ^ operation.a ^ x) & VALUE_MASK
        elif operation.kind == "shift":
            value = ((value << operation.a) ^ (value >> 1) ^ operation.b) & VALUE_MASK
        elif operation.kind == "branch":
            value = (
                value + (operation.a if value & operation.a else operation.b)
            ) & VALUE_MASK
        else:
            raise ValueError(f"unknown operation {operation.kind}")
    if leaf.family == 0:
        iterations = 3 + leaf.family_a % 5
        for iteration in range(iterations):
            value = (value * 3 + iteration + leaf.family_b) & VALUE_MASK
            if value & 1 == 0:
                value = (value + leaf.family_c) & VALUE_MASK
    elif leaf.family == 1:
        values = (
            value,
            (x + leaf.family_a) & VALUE_MASK,
            (value + leaf.family_b) & VALUE_MASK,
            (x * 3 + leaf.family_c) & VALUE_MASK,
        )
        value = 0
        for index, element in enumerate(values):
            value = (value + element * (index + 1)) & VALUE_MASK
    elif leaf.family == 2:
        left = (value + leaf.family_a) & VALUE_MASK
        right = (x * 5 + leaf.family_b) & VALUE_MASK
        value = (left * 3 + right * 7 + leaf.family_c) & VALUE_MASK
    elif leaf.family == 3:
        if value < 1024 + leaf.family_a % 2048:
            value = (value + leaf.family_b + x) & VALUE_MASK
            if value & 2:
                value = (value ^ leaf.family_c) & VALUE_MASK
        else:
            value = (value * 3 + leaf.family_c) & VALUE_MASK
    elif leaf.family == 4:
        value = ((value << 2) ^ (value >> 3) ^ leaf.family_a) & VALUE_MASK
        value = (value * 5 + leaf.family_b + x) & VALUE_MASK
    return value


def render(language: str, workload: Workload, target_bytes: int | None = None) -> str:
    if language not in LANGUAGES:
        raise ValueError(f"unsupported language {language}")
    prefix = header(language)
    functions = "".join(render_leaf(language, leaf) for leaf in workload.leaves)
    functions += "".join(render_reducer(language, reducer) for reducer in workload.reducers)
    suffix = main_function(language, workload.root)
    source = prefix + functions + suffix
    if target_bytes is None:
        return source
    remaining = target_bytes - len(source.encode())
    if remaining < 0:
        raise ValueError("workload exceeds target source size")
    if remaining:
        source = prefix + functions + padding_comment(language, remaining) + suffix
    if len(source.encode()) != target_bytes:
        raise AssertionError("source padding did not reach exact target size")
    return source


def header(language: str) -> str:
    return {
        "rust": "#![allow(dead_code, unused_parens)]\n\nstruct Pair { left: i32, right: i32 }\n\n",
        "c": "#include <stdio.h>\n\ntypedef struct { int left; int right; } Pair;\n\n",
        "cpp": "#include <cstdio>\n\nstruct Pair { int left; int right; };\n\n",
        "zig": "const c = @cImport({ @cInclude(\"stdio.h\"); });\n\nconst Pair = struct { left: i32, right: i32 };\n\n",
        "lanius": "module bench::scaling;\n\nimport std::io;\n\nstruct Pair {\n    left: i32,\n    right: i32,\n}\n\n",
    }[language]


def render_leaf(language: str, leaf: Leaf) -> str:
    lines = [function_start(language, leaf.name), declare(language, "value", f"(x * {leaf.initial_factor} + {leaf.initial_bias}) & {VALUE_MASK}")]
    for operation in leaf.operations:
        lines.extend(render_operation(language, operation))
    lines.extend(render_family(language, leaf))
    lines.extend(["    return value;", "}", ""])
    return "\n".join(lines) + "\n"


def render_operation(language: str, operation: Operation) -> list[str]:
    if operation.kind == "add":
        return [f"    value = (value + {operation.a} + x) & {VALUE_MASK};"]
    if operation.kind == "mul":
        return [f"    value = (value * {operation.a} + {operation.b}) & {VALUE_MASK};"]
    if operation.kind == "xor":
        return [f"    value = (value ^ {operation.a} ^ x) & {VALUE_MASK};"]
    if operation.kind == "shift":
        return [f"    value = ((value << {operation.a}) ^ (value >> 1) ^ {operation.b}) & {VALUE_MASK};"]
    return [
        f"    if ((value & {operation.a}) != 0) {{",
        f"        value = (value + {operation.a}) & {VALUE_MASK};",
        "    } else {",
        f"        value = (value + {operation.b}) & {VALUE_MASK};",
        "    }",
    ]


def render_family(language: str, leaf: Leaf) -> list[str]:
    if leaf.family == 0:
        lines = [declare(language, "i", "0")]
        lines.append(f"    while (i < {3 + leaf.family_a % 5}) {{")
        lines.append(f"        value = (value * 3 + {index_expr(language, 'i')} + {leaf.family_b}) & {VALUE_MASK};")
        lines.extend([
            "        if ((value & 1) == 0) {",
            f"            value = (value + {leaf.family_c}) & {VALUE_MASK};",
            "        }",
            increment(language, "i"),
            "    }",
        ])
        return lines
    if leaf.family == 1:
        expressions = [
            "value",
            f"(x + {leaf.family_a}) & {VALUE_MASK}",
            f"(value + {leaf.family_b}) & {VALUE_MASK}",
            f"(x * 3 + {leaf.family_c}) & {VALUE_MASK}",
        ]
        lines = [array_declare(language, expressions), "    value = 0;", index_declare(language)]
        lines.extend([
            "    while (i < 4) {",
            f"        value = (value + values[i] * ({index_expr(language, 'i')} + 1)) & {VALUE_MASK};",
            increment(language, "i"),
            "    }",
        ])
        return lines
    if leaf.family == 2:
        return [
            pair_declare(language, f"(value + {leaf.family_a}) & {VALUE_MASK}", f"(x * 5 + {leaf.family_b}) & {VALUE_MASK}"),
            f"    value = (pair.left * 3 + pair.right * 7 + {leaf.family_c}) & {VALUE_MASK};",
        ]
    if leaf.family == 3:
        return [
            f"    if (value < {1024 + leaf.family_a % 2048}) {{",
            f"        value = (value + {leaf.family_b} + x) & {VALUE_MASK};",
            "        if ((value & 2) != 0) {",
            f"            value = (value ^ {leaf.family_c}) & {VALUE_MASK};",
            "        }",
            "    } else {",
            f"        value = (value * 3 + {leaf.family_c}) & {VALUE_MASK};",
            "    }",
        ]
    return [
        f"    value = ((value << 2) ^ (value >> 3) ^ {leaf.family_a}) & {VALUE_MASK};",
        f"    value = (value * 5 + {leaf.family_b} + x) & {VALUE_MASK};",
    ]


def render_reducer(language: str, reducer: Reducer) -> str:
    lines = [
        function_start(language, reducer.name),
        declare_readonly(language, "left", f"{reducer.left}((x + {reducer.left_salt}) & {VALUE_MASK})"),
        declare_readonly(language, "right", f"{reducer.right}((x + {reducer.right_salt}) & {VALUE_MASK})"),
        declare_readonly(language, "mixed", f"(left + right + {reducer.bias}) & {VALUE_MASK}"),
        f"    if (mixed < {reducer.threshold}) {{",
        f"        return (mixed + x + {reducer.then_salt}) & {VALUE_MASK};",
        "    }",
        f"    return (mixed * 3 + {reducer.else_salt}) & {VALUE_MASK};",
        "}",
        "",
    ]
    return "\n".join(lines) + "\n"


def function_start(language: str, name: str) -> str:
    if language == "rust":
        return f"fn {name}(x: i32) -> i32 {{"
    if language in ("c", "cpp"):
        return f"static int {name}(int x) {{"
    if language == "zig":
        return f"fn {name}(x: i32) i32 {{"
    return f"fn {name}(x: i32) -> i32 {{"


def declare(language: str, name: str, expression: str) -> str:
    if language == "rust":
        return f"    let mut {name}: i32 = {expression};"
    if language in ("c", "cpp"):
        return f"    int {name} = {expression};"
    if language == "zig":
        return f"    var {name}: i32 = {expression};"
    return f"    let {name}: i32 = {expression};"


def declare_readonly(language: str, name: str, expression: str) -> str:
    if language == "rust":
        return f"    let {name}: i32 = {expression};"
    if language in ("c", "cpp"):
        return f"    int {name} = {expression};"
    if language == "zig":
        return f"    const {name}: i32 = {expression};"
    return f"    let {name}: i32 = {expression};"


def array_declare(language: str, expressions: list[str]) -> str:
    values = ", ".join(expressions)
    if language == "rust":
        return f"    let values: [i32; 4] = [{values}];"
    if language in ("c", "cpp"):
        return f"    int values[4] = {{{values}}};"
    if language == "zig":
        return f"    const values = [_]i32{{{values}}};"
    return f"    let values: [i32; 4] = [{values}];"


def index_declare(language: str) -> str:
    if language in ("rust", "zig"):
        return "    var i: usize = 0;" if language == "zig" else "    let mut i: usize = 0;"
    if language in ("c", "cpp"):
        return "    int i = 0;"
    return "    let i: i32 = 0;"


def index_expr(language: str, name: str) -> str:
    if language == "rust":
        return f"{name} as i32"
    if language == "zig":
        return f"@as(i32, @intCast({name}))"
    return name


def increment(language: str, name: str) -> str:
    return f"        {name} += 1;"


def pair_declare(language: str, left: str, right: str) -> str:
    if language == "rust":
        return f"    let pair = Pair {{ left: {left}, right: {right} }};"
    if language in ("c", "cpp"):
        return f"    Pair pair = {{{left}, {right}}};"
    if language == "zig":
        return f"    const pair = Pair{{ .left = {left}, .right = {right} }};"
    return f"    let pair: Pair = Pair {{ left: {left}, right: {right} }};"


def main_function(language: str, root: str) -> str:
    return {
        "rust": f'fn main() {{ println!("{{}}", {root}(7)); }}\n',
        "c": f'int main(void) {{ printf("%d\\n", {root}(7)); return 0; }}\n',
        "cpp": f'int main() {{ std::printf("%d\\n", {root}(7)); return 0; }}\n',
        "zig": f'pub fn main() void {{ _ = c.printf("%d\\n", {root}(7)); }}\n',
        "lanius": f"""fn main() -> i32 {{
    std::io::print_i32({root}(7));
    return 0;
}}
""",
    }[language]


def padding_comment(language: str, byte_count: int) -> str:
    if byte_count <= 2:
        return "\n" * byte_count
    return "//" + "p" * (byte_count - 3) + "\n"


def family_name(index: int) -> str:
    return ("loop", "array", "struct", "nested_branch", "bitwise")[index]
