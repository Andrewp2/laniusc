#!/usr/bin/env python3
"""Corpus-calibrated, semantically matched multi-file project model."""

from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path

from typical_project_constructs import (
    archetype_for_module,
    evaluate_archetype,
    evaluate_rare_patterns,
    lanius_constructs_in_source,
    load_construct_profile,
    rare_score_call,
    render_archetype,
    render_rare_patterns,
    render_runtime_probe,
    workload_call,
)


LANGUAGES = ("c", "cpp", "rust", "zig", "lanius")
VALUE_MASK = 4095
AREAS = (
    "accounts",
    "billing",
    "catalog",
    "checkout",
    "delivery",
    "inventory",
    "metrics",
    "orders",
    "pricing",
    "routing",
    "scheduling",
    "sessions",
    "storage",
    "telemetry",
    "validation",
)
ROLES = ("policy", "processor", "service", "planner", "tracker", "summary")
RULE_NAMES = (
    "normalize_amount",
    "apply_discount",
    "compute_fee",
    "classify_priority",
    "validate_window",
    "estimate_capacity",
    "adjust_limit",
    "score_delivery",
    "reconcile_total",
    "calculate_reserve",
    "update_forecast",
    "bound_retry",
)


@dataclass(frozen=True)
class RuleStep:
    kind: str
    a: int
    b: int


@dataclass(frozen=True)
class Rule:
    name: str
    steps: tuple[RuleStep, ...]


@dataclass(frozen=True)
class Module:
    index: int
    name: str
    archetype: str
    children: tuple[int, ...]
    support_dependencies: tuple[int, ...]
    base_rate: int
    child_salts: tuple[int, ...]
    support_salts: tuple[int, ...]
    rules: tuple[Rule, ...]


@dataclass(frozen=True)
class TypicalProject:
    seed: int
    modules: tuple[Module, ...]
    roots: tuple[int, ...]
    profile: dict[str, object]

    @property
    def entry_index(self) -> int:
        return self.roots[-1]

    def evaluate(self, seed: int = 7) -> int:
        def base_rate(module_index: int, value: int) -> int:
            module = self.modules[module_index]
            return (value + module.base_rate + module.index * 3) & VALUE_MASK

        def visit(module_index: int, value: int) -> int:
            module = self.modules[module_index]
            result = base_rate(module_index, value)
            result = (
                result + evaluate_archetype(module.archetype, value, module.index)
            ) & VALUE_MASK
            result = (result + evaluate_rare_patterns(value, module.index)) & VALUE_MASK
            for rule in module.rules:
                result = evaluate_rule(rule, result, value)
            for child, salt in zip(module.children, module.child_salts):
                result = (
                    result + visit(child, (value + salt) & VALUE_MASK)
                ) & VALUE_MASK
            for dependency, salt in zip(
                module.support_dependencies, module.support_salts
            ):
                result = (
                    result + base_rate(dependency, (value + salt) & VALUE_MASK)
                ) & VALUE_MASK
            return result

        total = 0
        for root in self.roots:
            total = (total + visit(root, seed)) & VALUE_MASK
        return total

    def structure(self) -> dict[str, object]:
        rendered = render_project("lanius", self)
        module_sources = [
            source for path, source in rendered.items() if path.endswith(".lani")
        ]
        file_lines = sorted(source.count("\n") + 1 for source in module_sources)
        import_counts = sorted(
            sum(line.startswith("import ") for line in source.splitlines())
            for source in module_sources
        )
        construct_profile = load_construct_profile()
        construct_counts: dict[str, int] = {}
        archetype_counts: dict[str, int] = {}
        for module in self.modules:
            archetype_counts[module.archetype] = (
                archetype_counts.get(module.archetype, 0) + 1
            )
        for source in module_sources:
            for construct in lanius_constructs_in_source(source):
                construct_counts[construct] = construct_counts.get(construct, 0) + 1
        required_constructs = set(construct_profile["required_project_constructs"])
        rare_constructs = set(construct_profile["rare_frontend_constructs"])
        runtime_facilities = set(construct_profile["runtime_facilities"])
        covered_constructs = set(construct_counts)
        return {
            "source_file_count": len(self.modules),
            "module_file_count": len(self.modules),
            "dependency_edge_count": sum(
                len(module.children) + len(module.support_dependencies)
                for module in self.modules
            ),
            "entry_root_count": len(self.roots),
            "entry_import_count": len(
                (set(self.roots) - {self.entry_index})
                | set(dependency_indices(self.modules[self.entry_index]))
            ),
            "maximum_dependency_fanout": max(
                (
                    len(module.children) + len(module.support_dependencies)
                    for module in self.modules
                ),
                default=0,
            ),
            "dependency_depth": dependency_depth(self),
            "all_modules_reachable": reachable_modules(self)
            == set(range(len(self.modules))),
            "module_line_summary": summarize(file_lines),
            "module_import_summary": summarize(import_counts),
            "function_count": sum(source.count("fn ") for source in module_sources),
            "archetype_counts": dict(sorted(archetype_counts.items())),
            "construct_counts": dict(sorted(construct_counts.items())),
            "required_constructs_covered": required_constructs <= covered_constructs,
            "missing_required_constructs": sorted(
                required_constructs - covered_constructs
            ),
            "rare_frontend_constructs_covered": rare_constructs <= covered_constructs,
            "missing_rare_frontend_constructs": sorted(
                rare_constructs - covered_constructs
            ),
            "runtime_facilities_covered": runtime_facilities <= covered_constructs,
            "missing_runtime_facilities": sorted(
                runtime_facilities - covered_constructs
            ),
            "contains_padding": any(
                "/*pp" in source or "//pp" in source for source in module_sources
            ),
        }


def load_profile() -> dict[str, object]:
    path = Path(__file__).with_name("typical_project_profile.json")
    return json.loads(path.read_text())


def build_project(seed: int, source_file_count: int) -> TypicalProject:
    if source_file_count < 1:
        raise ValueError("source_file_count must be positive")
    profile = load_profile()
    module_count = source_file_count
    rng = random.Random((seed << 32) ^ module_count ^ 0x54595049)
    children, roots, depth_by_index = project_tree(module_count, rng)
    modules = []
    for index in range(module_count):
        area = AREAS[(index * 7) % len(AREAS)]
        role = ROLES[index % len(ROLES)]
        name = f"{area}_{role}_{index}"
        target_lines = sample_band(
            rng,
            profile["generation"]["file_line_bands"],
        )
        rules = build_rules(
            rng,
            target_lines,
            profile["generation"]["function_step_bands"],
        )
        support_candidates = [
            candidate
            for candidate in range(module_count)
            if depth_by_index[candidate] > depth_by_index[index]
            and candidate not in children[index]
        ]
        desired_support = support_dependency_count(rng)
        rng.shuffle(support_candidates)
        support = tuple(sorted(support_candidates[:desired_support]))
        modules.append(
            Module(
                index=index,
                name=name,
                archetype=archetype_for_module(index),
                children=children[index],
                support_dependencies=support,
                base_rate=rng.randrange(3, 257),
                child_salts=tuple(rng.randrange(1, 257) for _ in children[index]),
                support_salts=tuple(rng.randrange(1, 257) for _ in support),
                rules=rules,
            )
        )
    project = TypicalProject(seed, tuple(modules), roots, profile)
    structure = project.structure()
    if not structure["all_modules_reachable"]:
        raise AssertionError("typical project contains unreachable modules")
    return project


def project_tree(
    module_count: int, rng: random.Random
) -> tuple[list[tuple[int, ...]], tuple[int, ...], list[int]]:
    children: list[list[int]] = [[] for _ in range(module_count)]
    depth = [0] * module_count
    root_count = min(5, module_count)
    current = list(range(module_count - 1, module_count - root_count - 1, -1))
    assigned = set(current)
    layer_depth = 0
    while len(assigned) < module_count:
        next_layer = []
        for parent in current:
            capacity = rng.randrange(2, 5)
            for candidate in range(module_count - 1, -1, -1):
                if candidate in assigned:
                    continue
                children[parent].append(candidate)
                assigned.add(candidate)
                next_layer.append(candidate)
                depth[candidate] = layer_depth + 1
                if len(children[parent]) == capacity:
                    break
            if len(assigned) == module_count:
                break
        if not next_layer:
            break
        current = next_layer
        layer_depth += 1
    roots = tuple(range(module_count - root_count, module_count))
    return [tuple(sorted(values)) for values in children], roots, depth


def support_dependency_count(rng: random.Random) -> int:
    selection = rng.randrange(10_000)
    if selection < 5000:
        return 0
    if selection < 8200:
        return 1
    if selection < 9600:
        return 2
    return rng.randrange(3, 6)


def sample_band(rng: random.Random, bands: list[dict[str, int]]) -> int:
    selection = rng.randrange(1, 10_001)
    for band in bands:
        if selection <= band["cumulative_basis_points"]:
            return rng.randrange(band["minimum"], band["maximum"] + 1)
    raise AssertionError("profile bands do not cover 10,000 basis points")


def build_rules(
    rng: random.Random,
    target_lines: int,
    function_step_bands: list[dict[str, int]],
) -> tuple[Rule, ...]:
    rules = []
    estimated_lines = 18
    while estimated_lines < target_lines:
        step_count = sample_band(rng, function_step_bands)
        steps = []
        for step_index in range(step_count):
            kind = (
                "offset"
                if step_index == 0
                else rng.choices(
                    ("offset", "scale", "threshold", "clamp"),
                    weights=(38, 22, 28, 12),
                )[0]
            )
            steps.append(RuleStep(kind, rng.randrange(1, 257), rng.randrange(1, 2048)))
        base_name = RULE_NAMES[len(rules) % len(RULE_NAMES)]
        repetition = len(rules) // len(RULE_NAMES)
        name = base_name if repetition == 0 else f"{base_name}_{repetition + 1}"
        rules.append(Rule(name, tuple(steps)))
        estimated_lines += 5 + step_count * 3
    return tuple(rules)


def evaluate_rule(rule: Rule, value: int, context: int) -> int:
    result = value
    for step in rule.steps:
        if step.kind == "offset":
            result = (result + step.a + context) & VALUE_MASK
        elif step.kind == "scale":
            result = (result * (step.a % 7 + 2) + step.b) & VALUE_MASK
        elif step.kind == "threshold":
            threshold = 512 + step.b % 3072
            if result > threshold:
                result = (result - step.a) & VALUE_MASK
            else:
                result = (result + step.a) & VALUE_MASK
        elif step.kind == "clamp":
            maximum = 1024 + step.b % 3072
            if result > maximum:
                result = maximum
        else:
            raise ValueError(step.kind)
    return result


def dependency_depth(project: TypicalProject) -> int:
    memo: dict[int, int] = {}

    def visit(index: int) -> int:
        if index in memo:
            return memo[index]
        result = 1 + max(
            (visit(child) for child in project.modules[index].children), default=0
        )
        memo[index] = result
        return result

    return max((visit(root) for root in project.roots), default=0)


def reachable_modules(project: TypicalProject) -> set[int]:
    reached = set()
    pending = list(project.roots)
    while pending:
        index = pending.pop()
        if index in reached:
            continue
        reached.add(index)
        module = project.modules[index]
        pending.extend(module.children)
        pending.extend(module.support_dependencies)
    return reached


def summarize(values: list[int]) -> dict[str, int]:
    if not values:
        return {"minimum": 0, "p50": 0, "p90": 0, "p99": 0, "maximum": 0}
    values = sorted(values)

    def at(fraction: float) -> int:
        return values[round((len(values) - 1) * fraction)]

    return {
        "minimum": values[0],
        "p50": at(0.50),
        "p90": at(0.90),
        "p99": at(0.99),
        "maximum": values[-1],
    }


def render_project(language: str, project: TypicalProject) -> dict[str, str]:
    if language not in LANGUAGES:
        raise ValueError(language)
    if language == "c":
        return render_c_project(project, cpp=False)
    if language == "cpp":
        return render_c_project(project, cpp=True)
    if language == "rust":
        return render_rust_project(project)
    if language == "zig":
        return render_zig_project(project)
    return render_lanius_project(project)


def dependency_indices(module: Module) -> tuple[int, ...]:
    return tuple(sorted(set(module.children + module.support_dependencies)))


def render_rule_body(rule: Rule, language: str, prefix: str = "") -> str:
    lines = [function_start(language, prefix + rule.name)]
    lines.append(mutable_declaration(language, "result", "value"))
    for step in rule.steps:
        if step.kind == "offset":
            lines.append(f"    result = (result + {step.a} + context) & {VALUE_MASK};")
        elif step.kind == "scale":
            lines.append(
                f"    result = (result * {step.a % 7 + 2} + {step.b}) & {VALUE_MASK};"
            )
        elif step.kind == "threshold":
            threshold = 512 + step.b % 3072
            lines.extend(
                [
                    condition_start(language, f"result > {threshold}"),
                    f"        result = (result - {step.a}) & {VALUE_MASK};",
                    "    } else {",
                    f"        result = (result + {step.a}) & {VALUE_MASK};",
                    "    }",
                ]
            )
        else:
            maximum = 1024 + step.b % 3072
            lines.extend(
                [
                    condition_start(language, f"result > {maximum}"),
                    f"        result = {maximum};",
                    "    }",
                ]
            )
    lines.extend(("    return result;", "}", ""))
    return "\n".join(lines) + "\n"


def condition_start(language: str, expression: str) -> str:
    if language != "rust":
        return f"    if ({expression}) {{"
    return f"    if {expression} {{"


def function_start(language: str, name: str) -> str:
    if language == "rust":
        return f"fn {name}(value: i32, context: i32) -> i32 {{"
    if language == "zig":
        return f"fn {name}(value: i32, context: i32) i32 {{"
    if language == "lanius":
        return f"fn {name}(value: i32, context: i32) -> i32 {{"
    return f"static int32_t {name}(int32_t value, int32_t context) {{"


def mutable_declaration(language: str, name: str, expression: str) -> str:
    if language == "rust":
        return f"    let mut {name}: i32 = {expression};"
    if language == "zig":
        return f"    var {name}: i32 = {expression};"
    if language == "lanius":
        return f"    let {name}: i32 = {expression};"
    return f"    int32_t {name} = {expression};"


def render_lanius_project(project: TypicalProject) -> dict[str, str]:
    files = {}
    for module in project.modules:
        if module.index == project.entry_index:
            continue
        imports = "".join(
            f"import typical::{project.modules[index].name};\n"
            for index in dependency_indices(module)
        )
        rules = render_archetype("lanius", module.archetype, module.name, module.index)
        rules += render_rare_patterns("lanius", module.name, module.index)
        rules += "".join(render_rule_body(rule, "lanius") for rule in module.rules)
        files[f"src/typical/{module.name}.lani"] = (
            f"module typical::{module.name};\n\n{imports}\n"
            + rules
            + render_lanius_module_api(project, module)
        )
    entry = project.modules[project.entry_index]
    imported_indices = sorted(
        (set(project.roots) - {project.entry_index}) | set(dependency_indices(entry))
    )
    imports = "".join(
        f"import typical::{project.modules[index].name};\n"
        for index in imported_indices
    )
    own_rules = render_archetype("lanius", entry.archetype, entry.name, entry.index)
    own_rules += render_rare_patterns("lanius", entry.name, entry.index)
    own_rules += "".join(render_rule_body(rule, "lanius") for rule in entry.rules)
    calls = []
    for index in project.roots:
        call = (
            "evaluate(7)"
            if index == project.entry_index
            else f"typical::{project.modules[index].name}::evaluate(7)"
        )
        calls.append(f"    total = (total + {call}) & {VALUE_MASK};")
    files["main.lani"] = (
        "module app::main;\n\nimport alloc::allocator;\nimport std::env;\nimport std::fs;\nimport std::io;\nimport std::process;\nimport std::random;\nimport std::time;\n"
        + imports
        + "\n"
        + own_rules
        + render_runtime_probe("lanius")
        + render_lanius_module_api(project, entry)
        + "fn main() -> i32 {\n    let runtime_status: i32 = runtime_probe();\n    if (runtime_status != 0) { return runtime_status; }\n    let total: i32 = 0;\n"
        + "\n".join(calls)
        + "\n    std::io::print_i32(total);\n    std::process::exit(0);\n    return 0;\n}\n"
    )
    return files


def render_lanius_module_api(project: TypicalProject, module: Module) -> str:
    lines = [
        "pub fn base_rate(value: i32) -> i32 {",
        f"    return (value + {module.base_rate} + {module.index * 3}) & {VALUE_MASK};",
        "}",
        "",
        "pub fn evaluate(seed: i32) -> i32 {",
        "    let total: i32 = base_rate(seed);",
        f"    total = (total + {workload_call('lanius', module.name, 'seed')}) & {VALUE_MASK};",
    ]
    rare_call = rare_score_call("lanius", module.name, module.index, "seed")
    if rare_call is not None:
        lines.append(f"    total = (total + {rare_call}) & {VALUE_MASK};")
    for rule in module.rules:
        lines.append(f"    total = {rule.name}(total, seed);")
    lines.extend(module_dependency_calls(project, module, "lanius"))
    lines.extend(("    return total;", "}", ""))
    return "\n".join(lines) + "\n"


def module_dependency_calls(
    project: TypicalProject, module: Module, language: str
) -> list[str]:
    lines = []
    for child, salt in zip(module.children, module.child_salts):
        name = project.modules[child].name
        call = qualified_call(
            language, name, "evaluate", f"(seed + {salt}) & {VALUE_MASK}"
        )
        lines.append(f"    total = (total + {call}) & {VALUE_MASK};")
    for dependency, salt in zip(module.support_dependencies, module.support_salts):
        name = project.modules[dependency].name
        call = qualified_call(
            language, name, "base_rate", f"(seed + {salt}) & {VALUE_MASK}"
        )
        lines.append(f"    total = (total + {call}) & {VALUE_MASK};")
    return lines


def qualified_call(language: str, module: str, function: str, argument: str) -> str:
    if language == "lanius":
        return f"typical::{module}::{function}({argument})"
    if language == "cpp":
        return f"typical::{module}::{function}({argument})"
    if language == "rust":
        return f"{module}::{function}({argument})"
    if language == "zig":
        return f"{module}.{function}({argument})"
    return f"{module}_{function}({argument})"


def render_rust_project(project: TypicalProject) -> dict[str, str]:
    files = {}
    for module in project.modules:
        if module.index == project.entry_index:
            continue
        uses = "".join(
            f"use crate::{project.modules[index].name};\n"
            for index in dependency_indices(module)
        )
        files[f"src/{module.name}.rs"] = (
            uses + "\n" + render_rust_module_api(project, module)
        )
    entry = project.modules[project.entry_index]
    declarations = "".join(
        f"mod {module.name};\n"
        for module in project.modules
        if module.index != project.entry_index
    )
    calls = []
    for index in project.roots:
        call = (
            "evaluate(7)"
            if index == project.entry_index
            else f"{project.modules[index].name}::evaluate(7)"
        )
        calls.append(f"    total = (total + {call}) & {VALUE_MASK};")
    files["src/main.rs"] = (
        declarations
        + "\n"
        + render_runtime_probe("rust")
        + render_rust_module_api(project, entry)
        + "\nfn main() {\n    let runtime_status = runtime_probe();\n    if runtime_status != 0 { std::process::exit(runtime_status); }\n    let mut total: i32 = 0;\n"
        + "\n".join(calls)
        + '\n    println!("{}", total);\n    std::process::exit(0);\n}\n'
    )
    files["Cargo.toml"] = """[package]
name = "typical_project"
version = "0.1.0"
edition = "2024"

[workspace]

[profile.dev]
debug = 0
incremental = false

[profile.release]
debug = 0
strip = "debuginfo"
incremental = false
"""
    return files


def render_rust_module_api(project: TypicalProject, module: Module) -> str:
    rules = render_archetype("rust", module.archetype, module.name, module.index)
    rules += render_rare_patterns("rust", module.name, module.index)
    rules += "".join(render_rule_body(rule, "rust") for rule in module.rules)
    lines = [
        f"pub fn base_rate(value: i32) -> i32 {{ (value + {module.base_rate} + {module.index * 3}) & {VALUE_MASK} }}",
        "",
        "pub fn evaluate(seed: i32) -> i32 {",
        "    let mut total: i32 = base_rate(seed);",
        f"    total = (total + {workload_call('rust', module.name, 'seed')}) & {VALUE_MASK};",
    ]
    rare_call = rare_score_call("rust", module.name, module.index, "seed")
    if rare_call is not None:
        lines.append(f"    total = (total + {rare_call}) & {VALUE_MASK};")
    for rule in module.rules:
        lines.append(f"    total = {rule.name}(total, seed);")
    lines.extend(module_dependency_calls(project, module, "rust"))
    lines.extend(("    total", "}", ""))
    return rules + "\n".join(lines)


def render_zig_project(project: TypicalProject) -> dict[str, str]:
    files = {}
    for module in project.modules:
        if module.index == project.entry_index:
            continue
        imports = "".join(
            f'const {project.modules[index].name} = @import("{project.modules[index].name}.zig");\n'
            for index in dependency_indices(module)
        )
        files[f"{module.name}.zig"] = (
            imports + "\n" + render_zig_module_api(project, module)
        )
    entry = project.modules[project.entry_index]
    imported_indices = sorted(
        (set(project.roots) - {project.entry_index}) | set(dependency_indices(entry))
    )
    imports = '''const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("time.h");
    @cInclude("sys/random.h");
});
''' + "".join(
        f'const {project.modules[index].name} = @import("{project.modules[index].name}.zig");\n'
        for index in imported_indices
    )
    calls = []
    for index in project.roots:
        call = (
            "evaluate(7)"
            if index == project.entry_index
            else f"{project.modules[index].name}.evaluate(7)"
        )
        calls.append(f"    total = (total + {call}) & {VALUE_MASK};")
    files["main.zig"] = (
        imports
        + "\n"
        + render_zig_module_api(project, entry)
        + "\n"
        + render_runtime_probe("zig")
        + "\npub fn main(init: std.process.Init) void {\n    const runtime_status = runtime_probe(init.minimal.args.vector.len);\n    if (runtime_status != 0) std.process.exit(@intCast(runtime_status));\n    var total: i32 = 0;\n"
        + "\n".join(calls)
        + '\n    _ = c.printf("%d\\n", total);\n    _ = c.fflush(null);\n    std.process.exit(0);\n}\n'
    )
    return files


def render_zig_module_api(project: TypicalProject, module: Module) -> str:
    rules = render_archetype("zig", module.archetype, module.name, module.index)
    rules += render_rare_patterns("zig", module.name, module.index)
    rules += "".join(render_rule_body(rule, "zig") for rule in module.rules)
    lines = [
        f"pub fn base_rate(value: i32) i32 {{ return (value + {module.base_rate} + {module.index * 3}) & {VALUE_MASK}; }}",
        "",
        "pub fn evaluate(seed: i32) i32 {",
        "    var total: i32 = base_rate(seed);",
        f"    total = (total + {workload_call('zig', module.name, 'seed')}) & {VALUE_MASK};",
    ]
    rare_call = rare_score_call("zig", module.name, module.index, "seed")
    if rare_call is not None:
        lines.append(f"    total = (total + {rare_call}) & {VALUE_MASK};")
    for rule in module.rules:
        lines.append(f"    total = {rule.name}(total, seed);")
    lines.extend(module_dependency_calls(project, module, "zig"))
    lines.extend(("    return total;", "}", ""))
    return rules + "\n".join(lines)


def render_c_project(project: TypicalProject, cpp: bool) -> dict[str, str]:
    extension = "cpp" if cpp else "c"
    files = {}
    for module in project.modules:
        if module.index == project.entry_index:
            continue
        header = render_c_header(module, cpp)
        includes = f'#include "{module.name}.h"\n' + "".join(
            f'#include "{project.modules[index].name}.h"\n'
            for index in dependency_indices(module)
        )
        files[f"include/{module.name}.h"] = header
        files[f"src/{module.name}.{extension}"] = (
            includes + "\n" + render_c_module_api(project, module, cpp)
        )
    entry = project.modules[project.entry_index]
    imported_indices = sorted(
        (set(project.roots) - {project.entry_index}) | set(dependency_indices(entry))
    )
    root_includes = ("#include <cstdint>\n" if cpp else "") + """#ifndef __cplusplus
#define _POSIX_C_SOURCE 200809L
#endif
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <sys/random.h>
""" + "".join(
        f'#include "{project.modules[index].name}.h"\n' for index in imported_indices
    )
    calls = []
    for index in project.roots:
        name = project.modules[index].name
        call = f"typical::{name}::evaluate(7)" if cpp else f"{name}_evaluate(7)"
        calls.append(f"    total = (total + {call}) & {VALUE_MASK};")
    files[f"src/main.{extension}"] = (
        root_includes
        + "\n"
        + render_c_module_api(project, entry, cpp)
        + "\n"
        + render_runtime_probe("cpp" if cpp else "c")
        + "\nint main(int argc, char** argv) {\n    (void)argv;\n    int32_t runtime_status = runtime_probe(argc);\n    if (runtime_status != 0) return runtime_status;\n    int32_t total = 0;\n"
        + "\n".join(calls)
        + '\n    printf("%d\\n", total);\n    exit(0);\n}\n'
    )
    return files


def render_c_module_api(project: TypicalProject, module: Module, cpp: bool) -> str:
    language = "cpp" if cpp else "c"
    rule_prefix = "" if cpp else f"{module.name}_"
    rules = "".join(
        render_rule_body(rule, language, rule_prefix) for rule in module.rules
    )
    constructs = render_archetype(language, module.archetype, module.name, module.index)
    constructs += render_rare_patterns(language, module.name, module.index)
    namespace_open = f"namespace typical::{module.name} {{\n" if cpp else ""
    namespace_close = "} // namespace\n" if cpp else ""
    prefix = "" if cpp else f"{module.name}_"
    lines = [
        f"int32_t {prefix}base_rate(int32_t value) {{ return (value + {module.base_rate} + {module.index * 3}) & {VALUE_MASK}; }}",
        "",
        f"int32_t {prefix}evaluate(int32_t seed) {{",
        f"    int32_t total = {prefix}base_rate(seed);",
        f"    total = (total + {workload_call(language, module.name, 'seed')}) & {VALUE_MASK};",
    ]
    rare_call = rare_score_call(language, module.name, module.index, "seed")
    if rare_call is not None:
        lines.append(f"    total = (total + {rare_call}) & {VALUE_MASK};")
    for rule in module.rules:
        lines.append(f"    total = {rule_prefix}{rule.name}(total, seed);")
    lines.extend(module_dependency_calls(project, module, language))
    lines.extend(("    return total;", "}", ""))
    return namespace_open + constructs + rules + "\n".join(lines) + namespace_close


def render_c_header(module: Module, cpp: bool) -> str:
    if cpp:
        return f"""#pragma once
#include <cstdint>
#include <cstddef>

namespace typical::{module.name} {{
std::int32_t base_rate(std::int32_t value);
std::int32_t evaluate(std::int32_t seed);
}} // namespace typical::{module.name}
"""
    guard = f"TYPICAL_{module.name.upper()}_H"
    return f"""#ifndef {guard}
#define {guard}
#include <stdint.h>
#include <stddef.h>

int32_t {module.name}_base_rate(int32_t value);
int32_t {module.name}_evaluate(int32_t seed);

#endif
"""
