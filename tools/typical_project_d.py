#!/usr/bin/env python3
"""D rendering of the corpus-calibrated typical project (dmd and LDC).

Each non-entry module is ``typical/<name>.d`` declaring ``module
typical.<name>;`` and importing exactly its children and support
dependencies; ``main.d`` imports the other roots and the entry module's own
dependencies. Helpers are ``private`` and only ``base_rate`` and ``evaluate``
are public, so a module's own declarations always win over imported ones.
Values are ``int`` with the same ``& 4095`` masking as the other renderings.

Substitutions where D has no direct equivalent of the Rust/Lanius form:

- Payload enums (``Adjustment``, ``CoordinateEvent``, ``PatternListEvent``,
  ``PublicChoice``) and ``match`` over them: a struct holding an ``enum``
  tag plus payload fields, dispatched with ``final switch``. ``std.sumtype``
  is a library type, and the C++ rendering likewise uses a tagged struct
  rather than ``std::variant``.
- Integer ``match``: ``switch`` with ``default``. Boolean ``match``: ``?:``.
- ``impl`` blocks and ``Self { ... }``: struct member functions and
  ``static`` factories returning a struct literal; ``&self`` and ``self``
  receivers are ``const`` member functions (D passes ``this`` by reference).
- Traits, trait impls and ``where`` bounds (contracts, bound_list_forms):
  overloaded free functions plus template constraints; the contracts trait
  is an eponymous ``enum bool isScorePolicy(T)`` predicate, and multiple
  bounds are ``&&``-joined ``is(typeof(...))`` predicates.
- Public trait declaration: ``public interface PublicPolicy(T)``.
- ``pub const``: ``public enum int`` manifest constant; ``const`` items are
  ``enum`` manifest constants; ``type`` aliases are ``alias``.
- Const generics: a template value parameter ``(size_t N)`` deduced from an
  ``int[N]`` argument.
- ``&[i32]`` borrowed slices: ``const(int)[]`` slices taken with
  ``values[]``.
- ``extern "C"``: ``extern (C)``. ``extern`` without an ABI: a bodyless
  prototype with D linkage. ``pub extern "lanius_std" fn argc()``:
  ``public extern (C) int getpid()``, probed the same way.
- Inclusive and half-open ranges: ``foreach`` over ``a .. b`` only has an
  exclusive upper bound, so ``a ..= b`` is ``a .. b + 1``, ``.. b`` is
  ``0 .. b``, and open ranges ``a ..`` are ``a .. int.max`` with ``break``.
- Shadowing a local in a nested scope is a D error, so the planner's nested
  block binds ``const preview = total`` (as the Zig rendering does).
- ``let deferred: i32;`` (uninitialised local): ``int deferred = void;``.
- Primitive types: ``u8``/``u32``/``usize``/``i64``/``f32``/``str``/``ptr``
  are ``ubyte``/``uint``/``size_t``/``long``/``float``/``string``/``void*``.
- Runtime probe: druntime's C and POSIX bindings (``malloc``/``free`` with
  ``scope (exit)``, ``getcwd``, ``clock_gettime``, ``fopen``/``fclose``) and
  arguments from ``main(string[] args)``. druntime has no ``getrandom``
  binding, so ``main.d`` declares it ``extern (C)``. Output uses
  ``core.stdc.stdio.printf`` as in the single-file D benchmark, and ``main``
  returns 0 instead of calling ``exit(0)``.
"""

from __future__ import annotations

from typical_project_constructs import (
    RARE_SCORE_FUNCTIONS,
    rare_patterns_for_module,
)
from typical_project_model import (
    VALUE_MASK,
    Module,
    Rule,
    TypicalProject,
    dependency_indices,
)


MODULE_PACKAGE = "typical"


def _fill(template: str, **values: object) -> str:
    for key, value in values.items():
        template = template.replace(f"@{key}@", str(value))
    return template.replace("@MASK@", str(VALUE_MASK))


def render_d_project(project: TypicalProject) -> dict[str, str]:
    files: dict[str, str] = {}
    for module in project.modules:
        if module.index == project.entry_index:
            continue
        imports = "".join(
            f"import {MODULE_PACKAGE}.{project.modules[index].name};\n"
            for index in dependency_indices(module)
        )
        files[f"{MODULE_PACKAGE}/{module.name}.d"] = (
            f"module {MODULE_PACKAGE}.{module.name};\n\n"
            + (imports + "\n" if imports else "")
            + render_d_module_api(project, module)
        )
    entry = project.modules[project.entry_index]
    imported_indices = sorted(
        (set(project.roots) - {project.entry_index}) | set(dependency_indices(entry))
    )
    imports = "".join(
        f"import {MODULE_PACKAGE}.{project.modules[index].name};\n"
        for index in imported_indices
    )
    calls = []
    for index in project.roots:
        call = (
            "evaluate(7)"
            if index == project.entry_index
            else f"{MODULE_PACKAGE}.{project.modules[index].name}.evaluate(7)"
        )
        calls.append(f"    total = (total + {call}) & {VALUE_MASK};")
    files["main.d"] = (
        "module main;\n\n"
        "import core.stdc.stdio : FILE, fclose, fopen, printf;\n"
        "import core.stdc.stdlib : free, malloc;\n"
        "import core.sys.posix.time : CLOCK_REALTIME, clock_gettime, timespec;\n"
        "import core.sys.posix.unistd : getcwd;\n"
        + imports
        + "\n"
        + render_d_module_api(project, entry)
        + "\n"
        + RUNTIME_PROBE
        + "int main(string[] args) {\n"
        "    const int runtime_status = runtime_probe(args);\n"
        "    if (runtime_status != 0) return runtime_status;\n"
        "    int total = 0;\n"
        + "\n".join(calls)
        + '\n    printf("%d\\n", total);\n    return 0;\n}\n'
    )
    return files


def render_d_module_api(project: TypicalProject, module: Module) -> str:
    body = render_d_archetype(module.archetype, module.index)
    body += render_d_rare_patterns(module.index)
    body += "".join(render_d_rule(rule) for rule in module.rules)
    lines = [
        f"int base_rate(int value) {{ return (value + {module.base_rate} + {module.index * 3}) & {VALUE_MASK}; }}",
        "",
        "int evaluate(int seed) {",
        "    int total = base_rate(seed);",
        f"    total = (total + workload_score(seed)) & {VALUE_MASK};",
    ]
    if rare_patterns_for_module(module.index):
        lines.append(f"    total = (total + rare_construct_score(seed)) & {VALUE_MASK};")
    for rule in module.rules:
        lines.append(f"    total = {rule.name}(total, seed);")
    for child, salt in zip(module.children, module.child_salts):
        name = project.modules[child].name
        lines.append(
            f"    total = (total + {MODULE_PACKAGE}.{name}.evaluate((seed + {salt}) & {VALUE_MASK})) & {VALUE_MASK};"
        )
    for dependency, salt in zip(module.support_dependencies, module.support_salts):
        name = project.modules[dependency].name
        lines.append(
            f"    total = (total + {MODULE_PACKAGE}.{name}.base_rate((seed + {salt}) & {VALUE_MASK})) & {VALUE_MASK};"
        )
    lines.extend(("    return total;", "}", ""))
    return body + "\n".join(lines)


def render_d_rule(rule: Rule) -> str:
    lines = [
        f"private int {rule.name}(int value, int context) {{",
        "    int result = value;",
    ]
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
                (
                    f"    if (result > {threshold}) {{",
                    f"        result = (result - {step.a}) & {VALUE_MASK};",
                    "    } else {",
                    f"        result = (result + {step.a}) & {VALUE_MASK};",
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


ARCHETYPES = {
    "policy": """private enum AdjustmentKind { add, hold }

private struct Adjustment {
    AdjustmentKind kind;
    int amount;
}

private Adjustment choose_adjustment(int seed) {
    if ((seed & 1) == 0) return Adjustment(AdjustmentKind.add, seed % 7 + 1);
    return Adjustment(AdjustmentKind.hold, 0);
}

private int workload_score(int seed) {
    const Adjustment adjustment = choose_adjustment(seed);
    final switch (adjustment.kind) {
        case AdjustmentKind.add: return (seed + adjustment.amount) & @MASK@;
        case AdjustmentKind.hold: return (seed - 1) & @MASK@;
    }
}

""",
    "processor": """private int workload_score(int seed) {
    int[6] values = [seed, @LOW_INDEX@, 3, 7, 11, 13];
    size_t cursor = 0;
    int total = 0;
    while (cursor < values.length) {
        if (cursor == 1) {
            cursor += 1;
            continue;
        }
        if (cursor == 5) break;
        total = (total + values[cursor]) & @MASK@;
        cursor += 1;
    }
    return total;
}

""",
    "service": """private struct ServiceState {
    int left;
    int right;

    static ServiceState create(int seed) {
        return ServiceState((seed + @INDEX@) & @MASK@, (seed * 2 + 3) & @MASK@);
    }

    ServiceState adjusted(int amount) const {
        return ServiceState(left + amount, right - amount);
    }

    int score() const { return (left * 3 + right) & @MASK@; }
}

private int workload_score(int seed) {
    return ServiceState.create(seed).adjusted(@ADJUSTMENT@).score();
}

""",
    "planner": """private int first_eligible(int seed) {
    foreach (candidate; 0 .. 6) {
        if ((seed + candidate) % 4 == 0) return candidate;
    }
    return 6;
}

private int workload_score(int seed) {
    int total = 0;
    const int limit = @LIMIT@;
    foreach (outer; 0 .. limit) {
        foreach (inner; 0 .. 3) {
            if (inner == 1 && outer % 2 == 0) continue;
            total = (total + seed + outer * 3 + inner) & @MASK@;
        }
    }
    {
        const preview = total;
        if (preview < 0) return 0;
    }
    return (total + first_eligible(seed)) & @MASK@;
}

""",
    "tracker": """private int decay(int value, int remaining) {
    if (remaining <= 0) return value;
    const int mixed = ((value << 1) ^ (value >> 1) ^ @INDEX@) & @MASK@;
    return decay(mixed, remaining - 1);
}

private int workload_score(int seed) {
    const int delta = -@DELTA@;
    const bool enabled = !false;
    if (enabled) return (decay(seed, 3) - delta) & @MASK@;
    return 0;
}

""",
    "summary": """private alias SummaryScore = int;

private enum SummaryScore SUMMARY_OFFSET = @INDEX@;

private struct Envelope(T) {
    T value;
}

private T unwrap(T)(Envelope!T envelope) {
    return envelope.value;
}

private int workload_score(int seed) {
    Envelope!int envelope = Envelope!int(seed + SUMMARY_OFFSET);
    return unwrap(envelope) & @MASK@;
}

""",
}


def render_d_archetype(archetype: str, index: int) -> str:
    return _fill(
        ARCHETYPES[archetype],
        INDEX=index,
        LOW_INDEX=index & 31,
        ADJUSTMENT=index % 7 + 1,
        LIMIT=3 + index % 4,
        DELTA=index % 5 + 1,
    )


RARE_PATTERNS = {
    "contracts": """private int score_policy(int value) { return value & 4095; }

private enum bool isScorePolicy(T) = is(typeof(score_policy(T.init)) == int);

private T preserve_scored(T)(T value) if (isScorePolicy!T) {
    return value;
}

""",
    "const_generic": """private int first_const_generic(size_t N)(int first, int[N] values) {
    return first;
}

""",
    "borrowed_views": """private struct BorrowedValue {
    int value;

    int borrowed_marker() const { return value; }
}

private int first_slice(const(int)[] values) {
    return values.length == 0 ? 0 : values[0];
}

""",
    "foreign_api": """private extern (C) int getpid();

""",
    "literal_data": """private int literal_metadata() {
    string label = "module-@INDEX@";
    char delimiter = ':';
    float ratio = 1.25f;
    return 0;
}

""",
    "language_forms": """private int unbound_probe();

private int zero_value() { return 0; }

private void record_positive(int value) {
    if (value > 0) return;
}

private int language_forms(int seed) {
    auto inferred = +(seed);
    auto grouped = ((inferred));
    record_positive(grouped);
    return grouped + zero_value();
}

""",
    "operator_forms": """private int operator_forms(int seed) {
    int value = seed;
    value += 3;
    value -= 3;
    value *= 2;
    value /= 2;
    value %= @MODULUS@;
    value ^= 0;
    value <<= 1;
    value >>= 1;
    value &= @MASK@;
    value |= 0;
    return value;
}

""",
    "primitive_forms": """private int primitive_forms() {
    ubyte tiny = 1;
    uint unsigned_value = 2;
    size_t count = 3;
    long wide = 4;
    float decimal = 1.5f;
    bool truth = true;
    char letter = 'x';
    string text = "types";
    void* address = null;
    return 0;
}

""",
    "range_forms": """private int range_forms(int seed) {
    int total = seed;
    foreach (value; 1 .. 3 + 1) total = (total + value) & @MASK@;
    foreach (value; 0 .. 3) total = (total + value) & @MASK@;
    foreach (value; 0 .. 2 + 1) total = (total + value) & @MASK@;
    foreach (value; 2 .. int.max) {
        total = (total + value) & @MASK@;
        if (value == 4) break;
    }
    foreach (value; 0 .. int.max) {
        total = (total + value) & @MASK@;
        if (value == 2) break;
    }
    return (total - 24) & @MASK@;
}

""",
    "match_forms": """private int integer_pattern_score(int value) {
    switch (value) {
        case 0: return 5;
        case 1: return 7;
        default: return 9;
    }
}

private int boolean_pattern_score(bool value) { return value ? 3 : 4; }

private int match_forms(int seed) {
    return integer_pattern_score(seed % 3) + boolean_pattern_score((seed & 1) == 0);
}

""",
    "enum_tuple_patterns": """private struct CoordinateEvent {
    enum Kind { moved, idle }
    Kind kind;
    int x;
    int y;
}

private int coordinate_event_score(CoordinateEvent event) {
    final switch (event.kind) {
        case CoordinateEvent.Kind.moved: return event.x * 3 + event.y;
        case CoordinateEvent.Kind.idle: return 1;
    }
}

private int enum_tuple_patterns(int seed) {
    const moved = CoordinateEvent(CoordinateEvent.Kind.moved, seed % 7, (seed / 7) % 7);
    const idle = CoordinateEvent(CoordinateEvent.Kind.idle);
    return coordinate_event_score(moved) + coordinate_event_score(idle);
}

""",
    "iterable_forms": """private int iterable_forms(int seed) {
    int[4] values = [seed, 2, 3, 4];
    int total = 0;
    foreach (value; values) total = (total + value) & @MASK@;
    return (total - 9) & @MASK@;
}

""",
    "trailing_lists": """private struct TrailingRecord {
    int left;
    int right;
}

private int trailing_sum(int left, int right,) {
    int[2] values = [left, right,];
    TrailingRecord record = TrailingRecord(
        left: values[0],
        right: values[1],
    );
    return record.left + record.right;
}

private int trailing_lists(int seed) {
    return trailing_sum(seed, 0,);
}

""",
    "generic_arity": """private struct GenericPair(Left, Right,) {
    Left left;
    Right right;
}

private alias GenericIdentity(Value,) = Value;

private int generic_pair_left(GenericPair!(int, bool,) value) {
    GenericIdentity!(int,) left = value.left;
    return left;
}

private int generic_arity(int seed) {
    GenericPair!(int, bool,) pair = GenericPair!(int, bool,)(seed, true);
    return generic_pair_left(pair);
}

""",
    "pattern_list_forms": """private struct PatternListEvent {
    enum Kind { empty, value }
    Kind kind;
    int inner;
}

private int pattern_list_score(PatternListEvent value) {
    final switch (value.kind) {
        case PatternListEvent.Kind.empty: return 0;
        case PatternListEvent.Kind.value: return value.inner;
    }
}

private int pattern_list_forms(int seed) {
    const empty = PatternListEvent(PatternListEvent.Kind.empty);
    const value = PatternListEvent(PatternListEvent.Kind.value, seed,);
    return pattern_list_score(empty) + pattern_list_score(value);
}

""",
    "bound_list_forms": """private int bound_score_policy(int value) { return value; }

private int bound_score_policy(bool value) {
    if (value) return 1;
    return 0;
}

private int stable_bound_policy(int value) { return value; }

private int pair_bound_policy(int left, bool right) { return left; }

private Left preserve_bound_pair(Left, Right,)(Left left, Right right)
if (is(typeof(bound_score_policy(Left.init)) == int)
    && is(typeof(stable_bound_policy(Left.init)) == int)
    && is(typeof(pair_bound_policy(Left.init, Right.init)) == int)
    && is(typeof(bound_score_policy(Right.init)) == int))
{
    return left;
}

private int bound_list_forms(int seed) {
    return preserve_bound_pair(seed, true);
}

""",
    "statement_postfix_forms": """private struct StatementRecord {
    int value;

    public int statement_value() const { return value; }
}

private void observe_statement(int value) { return; }

private StatementRecord make_statement_record(int value) {
    return StatementRecord(value,);
}

private int statement_postfix_forms(int seed) {
    int deferred = void;
    observe_statement(0);
    StatementRecord record = StatementRecord(seed,);
    return record.statement_value() + make_statement_record(0).value;
}

""",
    "public_items": """public enum int PUBLIC_ZERO = 0;

public alias PublicScore = int;

public struct PublicRecord {
    PublicScore value;

    public int read() const { return value; }
}

public struct PublicChoice {
    enum Kind { selected, empty }
    Kind kind;
    int inner;
}

public interface PublicPolicy(T) {
    int public_policy(T value);
}

public extern (C) int getpid();

private int public_items(int seed) {
    PublicRecord record = PublicRecord(seed,);
    const choice = PublicChoice(PublicChoice.Kind.selected, 0);
    int adjustment;
    final switch (choice.kind) {
        case PublicChoice.Kind.selected: adjustment = choice.inner; break;
        case PublicChoice.Kind.empty: adjustment = 0; break;
    }
    const int observed = getpid();
    if (observed < 0) return 0;
    return record.read() + adjustment + PUBLIC_ZERO;
}

""",
    "empty_aggregates": """private struct EmptyRecord {}

private int empty_aggregates(int seed) {
    EmptyRecord empty_record = EmptyRecord();
    int[0] empty_values = [];
    return seed;
}

""",
}


def render_d_rare_patterns(index: int) -> str:
    patterns = rare_patterns_for_module(index)
    if not patterns:
        return ""
    definitions = "".join(
        _fill(RARE_PATTERNS[pattern], INDEX=index, MODULUS=VALUE_MASK + 1)
        for pattern in patterns
    )
    statements: list[str] = []
    for pattern in patterns:
        if pattern in RARE_SCORE_FUNCTIONS:
            function, arguments = RARE_SCORE_FUNCTIONS[pattern]
            statements.append(
                f"    total = (total + {function}({arguments})) & {VALUE_MASK};"
            )
        elif pattern == "contracts":
            statements.append(
                f"    total = (total + preserve_scored(seed)) & {VALUE_MASK};"
            )
        elif pattern == "const_generic":
            statements.extend(
                (
                    f"    int[4] const_values = [seed, {index}, 3, 7];",
                    f"    total = (total + first_const_generic(seed, const_values)) & {VALUE_MASK};",
                )
            )
        elif pattern == "borrowed_views":
            statements.extend(
                (
                    "    const borrowed = BorrowedValue(seed);",
                    f"    total = (total + borrowed.borrowed_marker()) & {VALUE_MASK};",
                    f"    int[4] slice_values = [seed, {index}, 3, 7];",
                    f"    total = (total + first_slice(slice_values[])) & {VALUE_MASK};",
                )
            )
        elif pattern == "foreign_api":
            statements.extend(
                (
                    "    const int observed_process = getpid();",
                    "    if (observed_process < 0) return 1;",
                )
            )
        else:
            raise ValueError(pattern)
    return (
        definitions
        + "private int rare_construct_score(int seed) {\n"
        "    int total = 0;\n"
        + "\n".join(statements)
        + "\n    return total;\n}\n\n"
    )


RUNTIME_PROBE = """private extern (C) ptrdiff_t getrandom(void* buffer, size_t length, uint flags);

private int runtime_probe(string[] args) {
    void* memory = malloc(32);
    if (memory is null) return 1;
    scope (exit) free(memory);
    char[4096] working_directory = void;
    if (args.length < 1 || getcwd(working_directory.ptr, working_directory.length) is null) return 2;
    timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now) != 0) return 3;
    uint random_value = 0;
    if (getrandom(&random_value, random_value.sizeof, 0) != random_value.sizeof) return 4;
    FILE* source = fopen("lanius/main.lani", "rb");
    if (source is null) return 5;
    if (fclose(source) != 0) return 6;
    return random_value != random_value ? 7 : 0;
}

"""
