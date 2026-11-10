#!/usr/bin/env python3
"""V (vlang) rendering of the corpus-calibrated typical project.

The layout is one V project: `v.mod` at the language root, one module per
non-entry typical module in its own directory (`<name>/<name>.v`, imported as
`import <name>`, which V resolves relative to the directory holding `v.mod`),
and `main.v` (module `main`) holding the entry module's code, the runtime probe
and `main`. Every module imports exactly its children and support
dependencies; `main.v` imports the other roots plus the entry's dependencies.
Integers are V's 32-bit `int`, masked with `& 4095` like every other twin.

V has no exact form for several constructs, so these sites use the nearest
idiomatic V form and keep the computed value:

- Payload enums (`Adjustment`, `CoordinateEvent`, `PatternListEvent`,
  `PublicChoice`) are sum types over small structs, and `match` arms
  smart-cast the matched value instead of binding payload patterns.
- Traits with type parameters (`ScorePolicy`, the `bound_list_forms`
  policies) are interfaces implemented by methods on `int`/`bool` alias
  types; V generics have no `where` bounds, so each bound is checked at
  instantiation by calling the interface method inside the generic function.
- Const generics become a fixed-size `[4]int` parameter.
- V generic parameters must be single letters, so `GenericPair[Left, Right]`
  and `preserve_bound_pair[Left, Right]` are written `[L, R]`.
- Borrowed views use a `&BorrowedValue` receiver and a slice of a fixed
  array (`values[..]`).
- `extern "C"` declarations are V C-interop declarations (`fn C.getpid() int`
  with `#include <unistd.h>`); the unbound extern is declared and never called.
- Generic type aliases do not exist; `GenericIdentity<i32>` is the plain alias
  `type GenericScore = int`.
- V has no inclusive or open-ended `for` ranges: `a ..= b` is `a .. b + 1`,
  `.. n` is `0 .. n`, and the open ranges are C-style `for` loops with an
  empty condition and a `break`.
- `ServiceState::new` is the conventional V constructor function
  `new_service_state`; V 0.5.2 misresolves a static `ServiceState.new` to the
  `main` module's same-named struct and rejects the call as private.
- V forbids shadowing, so the planner's nested scope binds a fresh name.
- V has no uninitialized locals; `deferred` is zero-initialized and discarded.
- Constants are lower snake case (`summary_offset`, `public_zero`), as V
  requires.
- V reports unused locals (an error under `-prod`), so metadata and primitive
  locals are discarded with `_ = name`.
- Zero-length fixed arrays are rejected by V, so `empty_aggregates` uses an
  empty dynamic array `[]int{}`.
- The runtime probe allocates a 32-byte `[]u8`, reads `os.args`,
  `os.getwd()`, `time.now()`, four bytes from `crypto.rand`, and opens
  `lanius/main.lani` with `os.open`.
"""

from __future__ import annotations

from typical_project_constructs import RARE_SCORE_FUNCTIONS, rare_patterns_for_module
from typical_project_model import (
    Module,
    Rule,
    TypicalProject,
    VALUE_MASK,
    dependency_indices,
)


V_MODULE_NAME = "typical"
M = VALUE_MASK


def render_v_project(project: TypicalProject) -> dict[str, str]:
    files = {"v.mod": V_MOD}
    for module in project.modules:
        if module.index == project.entry_index:
            continue
        imports = "".join(
            f"import {project.modules[index].name}\n"
            for index in dependency_indices(module)
        )
        files[f"{module.name}/{module.name}.v"] = (
            f"module {module.name}\n\n"
            + (imports + "\n" if imports else "")
            + render_module_body(project, module)
        )
    entry = project.modules[project.entry_index]
    imported_indices = sorted(
        (set(project.roots) - {project.entry_index}) | set(dependency_indices(entry))
    )
    imports = "import crypto.rand\nimport os\nimport time\n" + "".join(
        f"import {project.modules[index].name}\n" for index in imported_indices
    )
    calls = []
    for index in project.roots:
        call = (
            "evaluate(7)"
            if index == project.entry_index
            else f"{project.modules[index].name}.evaluate(7)"
        )
        calls.append(f"\ttotal = (total + {call}) & {M}")
    files["main.v"] = (
        "module main\n\n"
        + imports
        + "\n"
        + RUNTIME_PROBE
        + render_module_body(project, entry)
        + "\nfn main() {\n\truntime_status := runtime_probe()\n"
        "\tif runtime_status != 0 {\n\t\texit(runtime_status)\n\t}\n"
        "\tmut total := 0\n"
        + "\n".join(calls)
        + "\n\tprintln(total)\n\texit(0)\n}\n"
    )
    return files


V_MOD = f"""Module {{
	name: '{V_MODULE_NAME}'
	description: 'Corpus-calibrated typical multi-module project'
	version: '0.1.0'
	license: 'MIT'
	dependencies: []
}}
"""


RUNTIME_PROBE = """fn runtime_probe() int {
	mut memory := []u8{len: 32}
	memory[0] = 1
	if os.args.len < 1 {
		return 1
	}
	if os.getwd().len == 0 {
		return 2
	}
	if time.now().unix() <= 0 {
		return 3
	}
	random_bytes := rand.bytes(4) or { return 4 }
	if random_bytes.len != 4 {
		return 5
	}
	mut source := os.open('lanius/main.lani') or { return 6 }
	source.close()
	if memory[0] != 1 {
		return 7
	}
	return 0
}

"""


def render_module_body(project: TypicalProject, module: Module) -> str:
    body = render_archetype(module.archetype, module.index)
    body += render_rare_patterns(module.index)
    body += "".join(render_rule(rule) for rule in module.rules)
    lines = [
        f"pub fn base_rate(value int) int {{\n\treturn (value + {module.base_rate} + {module.index * 3}) & {M}\n}}",
        "",
        "pub fn evaluate(seed int) int {",
        "\tmut total := base_rate(seed)",
        f"\ttotal = (total + workload_score(seed)) & {M}",
    ]
    if rare_patterns_for_module(module.index):
        lines.append(f"\ttotal = (total + rare_construct_score(seed)) & {M}")
    for rule in module.rules:
        lines.append(f"\ttotal = {rule.name}(total, seed)")
    for child, salt in zip(module.children, module.child_salts):
        name = project.modules[child].name
        lines.append(f"\ttotal = (total + {name}.evaluate((seed + {salt}) & {M})) & {M}")
    for dependency, salt in zip(module.support_dependencies, module.support_salts):
        name = project.modules[dependency].name
        lines.append(
            f"\ttotal = (total + {name}.base_rate((seed + {salt}) & {M})) & {M}"
        )
    lines.extend(("\treturn total", "}", ""))
    return body + "\n".join(lines)


def render_rule(rule: Rule) -> str:
    lines = [f"fn {rule.name}(value int, context int) int {{", "\tmut result := value"]
    for step in rule.steps:
        if step.kind == "offset":
            lines.append(f"\tresult = (result + {step.a} + context) & {M}")
        elif step.kind == "scale":
            lines.append(f"\tresult = (result * {step.a % 7 + 2} + {step.b}) & {M}")
        elif step.kind == "threshold":
            lines.extend(
                (
                    f"\tif result > {512 + step.b % 3072} {{",
                    f"\t\tresult = (result - {step.a}) & {M}",
                    "\t} else {",
                    f"\t\tresult = (result + {step.a}) & {M}",
                    "\t}",
                )
            )
        elif step.kind == "clamp":
            maximum = 1024 + step.b % 3072
            lines.extend(
                (f"\tif result > {maximum} {{", f"\t\tresult = {maximum}", "\t}")
            )
        else:
            raise ValueError(step.kind)
    lines.extend(("\treturn result", "}", ""))
    return "\n".join(lines) + "\n"


def render_archetype(archetype: str, index: int) -> str:
    if archetype == "policy":
        return f"""struct Add {{
	amount int
}}

struct Hold {{}}

type Adjustment = Add | Hold

fn choose_adjustment(seed int) Adjustment {{
	if (seed & 1) == 0 {{
		return Add{{
			amount: seed % 7 + 1
		}}
	}}
	return Hold{{}}
}}

fn workload_score(seed int) int {{
	adjustment := choose_adjustment(seed)
	return match adjustment {{
		Add {{ (seed + adjustment.amount) & {M} }}
		Hold {{ (seed - 1) & {M} }}
	}}
}}

"""
    if archetype == "processor":
        return f"""fn workload_score(seed int) int {{
	values := [seed, {index & 31}, 3, 7, 11, 13]!
	mut cursor := 0
	mut total := 0
	for cursor < values.len {{
		if cursor == 1 {{
			cursor += 1
			continue
		}}
		if cursor == 5 {{
			break
		}}
		total = (total + values[cursor]) & {M}
		cursor += 1
	}}
	return total
}}

"""
    if archetype == "service":
        return f"""struct ServiceState {{
	left  int
	right int
}}

fn new_service_state(seed int) ServiceState {{
	return ServiceState{{
		left:  (seed + {index}) & {M}
		right: (seed * 2 + 3) & {M}
	}}
}}

fn (state ServiceState) adjusted(amount int) ServiceState {{
	return ServiceState{{
		left:  state.left + amount
		right: state.right - amount
	}}
}}

fn (state ServiceState) score() int {{
	return (state.left * 3 + state.right) & {M}
}}

fn workload_score(seed int) int {{
	return new_service_state(seed).adjusted({index % 7 + 1}).score()
}}

"""
    if archetype == "planner":
        return f"""fn first_eligible(seed int) int {{
	for candidate in 0 .. 6 {{
		if (seed + candidate) % 4 == 0 {{
			return candidate
		}}
	}}
	return 6
}}

fn workload_score(seed int) int {{
	mut total := 0
	limit := {3 + index % 4}
	for outer in 0 .. limit {{
		for inner in 0 .. 3 {{
			if inner == 1 && outer % 2 == 0 {{
				continue
			}}
			total = (total + seed + outer * 3 + inner) & {M}
		}}
	}}
	{{
		preview := total
		if preview < 0 {{
			return 0
		}}
	}}
	return (total + first_eligible(seed)) & {M}
}}

"""
    if archetype == "tracker":
        return f"""fn decay(value int, remaining int) int {{
	if remaining <= 0 {{
		return value
	}}
	mixed := ((value << 1) ^ (value >> 1) ^ {index}) & {M}
	return decay(mixed, remaining - 1)
}}

fn workload_score(seed int) int {{
	delta := -{index % 5 + 1}
	enabled := !false
	if enabled {{
		return (decay(seed, 3) - delta) & {M}
	}}
	return 0
}}

"""
    if archetype == "summary":
        return f"""type SummaryScore = int

const summary_offset = SummaryScore({index})

struct Envelope[T] {{
	value T
}}

fn unwrap[T](envelope Envelope[T]) T {{
	return envelope.value
}}

fn workload_score(seed int) int {{
	envelope := Envelope[int]{{
		value: seed + int(summary_offset)
	}}
	return unwrap(envelope) & {M}
}}

"""
    raise ValueError(archetype)


def render_rare_patterns(index: int) -> str:
    patterns = rare_patterns_for_module(index)
    if not patterns:
        return ""
    definitions = "".join(render_rare_pattern(pattern, index) for pattern in patterns)
    return definitions + render_rare_score(patterns, index)


def render_rare_score(patterns: tuple[str, ...], index: int) -> str:
    statements: list[str] = []
    for pattern in patterns:
        if pattern in RARE_SCORE_FUNCTIONS:
            function, arguments = RARE_SCORE_FUNCTIONS[pattern]
            statements.append(f"\ttotal = (total + {function}({arguments})) & {M}")
        elif pattern == "contracts":
            statements.append(
                f"\ttotal = (total + int(preserve_scored(ScoredInt(seed)))) & {M}"
            )
        elif pattern == "const_generic":
            statements.append(
                f"\ttotal = (total + first_const_generic(seed, [seed, {index}, 3, 7]!)) & {M}"
            )
        elif pattern == "borrowed_views":
            statements.extend(
                (
                    "\tborrowed := BorrowedValue{",
                    "\t\tvalue: seed",
                    "\t}",
                    f"\ttotal = (total + borrowed.borrowed_marker()) & {M}",
                    f"\tslice_values := [seed, {index}, 3, 7]!",
                    f"\ttotal = (total + first_slice(slice_values[..])) & {M}",
                )
            )
        elif pattern == "foreign_api":
            statements.extend(
                (
                    "\tobserved_process := C.getpid()",
                    "\tif observed_process < 0 {",
                    "\t\treturn 1",
                    "\t}",
                )
            )
        else:
            raise ValueError(pattern)
    mutable = any(line.startswith("\ttotal = ") for line in statements)
    return (
        "fn rare_construct_score(seed int) int {\n"
        + ("\tmut total := 0\n" if mutable else "\ttotal := 0\n")
        + "\n".join(statements)
        + "\n\treturn total\n}\n\n"
    )


def render_rare_pattern(pattern: str, index: int) -> str:
    if pattern == "contracts":
        return """interface ScorePolicy {
	score_policy() int
}

type ScoredInt = int

fn (value ScoredInt) score_policy() int {
	return int(value) & 4095
}

fn preserve_scored[T](value T) T {
	policy := ScorePolicy(value)
	_ = policy.score_policy()
	return value
}

"""
    if pattern == "const_generic":
        return """fn first_const_generic(first int, values [4]int) int {
	_ = values
	return first
}

"""
    if pattern == "borrowed_views":
        return """struct BorrowedValue {
	value int
}

fn (borrowed &BorrowedValue) borrowed_marker() int {
	return borrowed.value
}

fn first_slice(values []int) int {
	return values[0]
}

"""
    if pattern == "foreign_api":
        return """#include <unistd.h>

fn C.getpid() int

"""
    if pattern == "literal_data":
        return f"""fn literal_metadata() int {{
	label := 'module-{index}'
	delimiter := `:`
	ratio := f32(1.25)
	_ = label
	_ = delimiter
	_ = ratio
	return 0
}}

"""
    if pattern == "language_forms":
        return """fn C.unbound_probe() int

fn zero_value() int {
	return 0
}

fn record_positive(value int) {
	if value > 0 {
		return
	}
}

fn language_forms(seed int) int {
	inferred := +seed
	grouped := ((inferred))
	record_positive(grouped)
	return grouped + zero_value()
}

"""
    if pattern == "operator_forms":
        return f"""fn operator_forms(seed int) int {{
	mut value := seed
	value += 3
	value -= 3
	value *= 2
	value /= 2
	value %= {M + 1}
	value ^= 0
	value <<= 1
	value >>= 1
	value &= {M}
	value |= 0
	return value
}}

"""
    if pattern == "primitive_forms":
        return """fn primitive_forms() int {
	tiny := u8(1)
	unsigned := u32(2)
	count := uint(3)
	wide := i64(4)
	decimal := f32(1.5)
	truth := true
	letter := `x`
	text := 'types'
	address := voidptr(unsafe { nil })
	_ = tiny
	_ = unsigned
	_ = count
	_ = wide
	_ = decimal
	_ = truth
	_ = letter
	_ = text
	_ = address
	return 0
}

"""
    if pattern == "range_forms":
        return f"""fn range_forms(seed int) int {{
	mut total := seed
	for value in 1 .. 3 + 1 {{
		total = (total + value) & {M}
	}}
	for value in 0 .. 3 {{
		total = (total + value) & {M}
	}}
	for value in 0 .. 2 + 1 {{
		total = (total + value) & {M}
	}}
	for value := 2; ; value++ {{
		total = (total + value) & {M}
		if value == 4 {{
			break
		}}
	}}
	for value := 0; ; value++ {{
		total = (total + value) & {M}
		if value == 2 {{
			break
		}}
	}}
	return (total - 24) & {M}
}}

"""
    if pattern == "match_forms":
        return """fn integer_pattern_score(value int) int {
	return match value {
		0 { 5 }
		1 { 7 }
		else { 9 }
	}
}

fn boolean_pattern_score(value bool) int {
	return match value {
		true { 3 }
		false { 4 }
	}
}

fn match_forms(seed int) int {
	return integer_pattern_score(seed % 3) + boolean_pattern_score((seed & 1) == 0)
}

"""
    if pattern == "enum_tuple_patterns":
        return """struct Moved {
	x int
	y int
}

struct Idle {}

type CoordinateEvent = Idle | Moved

fn coordinate_event_score(event CoordinateEvent) int {
	return match event {
		Moved { event.x * 3 + event.y }
		Idle { 1 }
	}
}

fn enum_tuple_patterns(seed int) int {
	moved := CoordinateEvent(Moved{
		x: seed % 7
		y: (seed / 7) % 7
	})
	idle := CoordinateEvent(Idle{})
	return coordinate_event_score(moved) + coordinate_event_score(idle)
}

"""
    if pattern == "iterable_forms":
        return f"""fn iterable_forms(seed int) int {{
	values := [seed, 2, 3, 4]!
	mut total := 0
	for value in values {{
		total = (total + value) & {M}
	}}
	return (total - 9) & {M}
}}

"""
    if pattern == "trailing_lists":
        return """struct TrailingRecord {
	left  int
	right int
}

fn trailing_sum(left int, right int,) int {
	values := [left, right,]!
	record := TrailingRecord{
		left:  values[0]
		right: values[1],
	}
	return record.left + record.right
}

fn trailing_lists(seed int) int {
	return trailing_sum(seed, 0,)
}

"""
    if pattern == "generic_arity":
        return """struct GenericPair[L, R] {
	left  L
	right R
}

type GenericScore = int

fn generic_pair_left(value GenericPair[int, bool]) int {
	left := GenericScore(value.left)
	return int(left)
}

fn generic_arity(seed int) int {
	pair := GenericPair[int, bool]{
		left:  seed
		right: true
	}
	return generic_pair_left(pair)
}

"""
    if pattern == "pattern_list_forms":
        return """struct EmptyEvent {}

struct ValueEvent {
	inner int
}

type PatternListEvent = EmptyEvent | ValueEvent

fn pattern_list_score(value PatternListEvent) int {
	return match value {
		EmptyEvent { 0 }
		ValueEvent { value.inner }
	}
}

fn pattern_list_forms(seed int) int {
	empty := PatternListEvent(EmptyEvent{})
	value := PatternListEvent(ValueEvent{
		inner: seed
	})
	return pattern_list_score(empty) + pattern_list_score(value)
}

"""
    if pattern == "bound_list_forms":
        return """interface BoundScorePolicy {
	bound_score_policy() int
}

interface StableBoundPolicy {
	stable_bound_policy() int
}

interface PairBoundPolicy {
	pair_bound_policy(right bool) int
}

type BoundInt = int

type BoundFlag = bool

fn (value BoundInt) bound_score_policy() int {
	return int(value)
}

fn (value BoundInt) stable_bound_policy() int {
	return int(value)
}

fn (value BoundInt) pair_bound_policy(right bool) int {
	_ = right
	return int(value)
}

fn (value BoundFlag) bound_score_policy() int {
	if bool(value) {
		return 1
	}
	return 0
}

fn preserve_bound_pair[L, R](left L, right R) L {
	bound := BoundScorePolicy(left)
	stable := StableBoundPolicy(left)
	pair := PairBoundPolicy(left)
	right_bound := BoundScorePolicy(right)
	_ = bound
	_ = stable
	_ = pair
	_ = right_bound
	return left
}

fn bound_list_forms(seed int) int {
	return int(preserve_bound_pair(BoundInt(seed), BoundFlag(true)))
}

"""
    if pattern == "statement_postfix_forms":
        return """struct StatementRecord {
	value int
}

pub fn (record StatementRecord) statement_value() int {
	return record.value
}

fn observe_statement(value int) {
	_ = value
}

fn make_statement_record(value int) StatementRecord {
	return StatementRecord{
		value: value
	}
}

fn statement_postfix_forms(seed int) int {
	deferred := 0
	_ = deferred
	observe_statement(0)
	record := StatementRecord{
		value: seed
	}
	return record.statement_value() + make_statement_record(0).value
}

"""
    if pattern == "public_items":
        return """pub const public_zero = 0

pub type PublicScore = int

pub struct PublicRecord {
pub:
	value PublicScore
}

pub struct Selected {
pub:
	inner int
}

pub struct Unselected {}

pub type PublicChoice = Selected | Unselected

pub interface PublicPolicy {
	public_policy() int
}

pub fn (record PublicRecord) read() int {
	return int(record.value)
}

fn public_items(seed int) int {
	record := PublicRecord{
		value: PublicScore(seed)
	}
	choice := PublicChoice(Selected{
		inner: 0
	})
	adjustment := match choice {
		Selected { choice.inner }
		Unselected { 0 }
	}
	return record.read() + adjustment + public_zero
}

"""
    if pattern == "empty_aggregates":
        return """struct EmptyRecord {}

fn empty_aggregates(seed int) int {
	empty_record := EmptyRecord{}
	empty_values := []int{}
	_ = empty_record
	_ = empty_values
	return seed
}

"""
    raise ValueError(pattern)
