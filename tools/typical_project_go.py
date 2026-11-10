#!/usr/bin/env python3
"""Go rendering of the corpus-calibrated multi-file typical project.

The project is one Go module (`go.mod`, module `typical`). Every non-entry
typical module is its own package in its own directory and imports exactly
its children and support dependencies; the entry module is package `main` at
the module root and imports the other roots and its own dependencies. The
public `base_rate` and `evaluate` become the exported `BaseRate` and
`Evaluate`; every other function name is the camelCase form of its Rust name.
Each package's file is `module.go`: a file named after a module such as
`catalog_service_386` would end in a GOARCH suffix and be excluded by Go's
file-name build constraints.

Construct substitutions, each keeping the computed value:

- Enums with payloads (policy `Adjustment`, `CoordinateEvent`,
  `PatternListEvent`, `PublicChoice`) are sealed interfaces with one struct
  per variant, matched by a type switch. A switch over every variant ends in
  `panic`, because Go does not check exhaustiveness. `Moved(i32, i32)` is a
  two-field struct built with a positional literal.
- Matching on a bool uses `case true` and `default`, since Go treats only a
  switch with a `default` as a terminating statement.
- Traits with generic parameters (`ScorePolicy<T>`, `BoundScorePolicy<T>`,
  `StableBoundPolicy<T>`, `PairBoundPolicy<Left, Right>`, `PublicPolicy<T>`)
  are generic interfaces. Go cannot add methods to `int32` or `bool`, so the
  implementations sit on the defined types `scoredI32`, `boundI32` and
  `boundBool`, and a receiver-less trait function becomes a method that
  ignores its receiver. Trait bounds and `where` clauses become type-parameter
  constraints; several bounds on one parameter become an inline constraint
  interface that embeds each of them.
- The const generic `first_const_generic<const N: usize>` takes a `[4]int32`
  fixed array, since Go has no const generics.
- `&self` is a pointer receiver; `&[i32]` is a slice of a local array.
- `extern "C" fn getpid` is a package variable bound to `syscall.Getpid`, the
  standard library's direct system call, rather than a cgo call. The unbound
  extern `unbound_probe` is a nil function variable that is never called.
- `type GenericIdentity<Value> = Value` cannot be written in Go (an alias's
  type parameter cannot be its whole right-hand side), so the generic alias is
  `genericScorePair[Right] = genericPair[int32, Right]`.
- Ranges: `a..b` from zero is `range n` over an integer, every other range is
  a three-clause `for`, and the open ranges `2..` and `0..` are `for` loops
  with no condition that `break`.
- Rust's uninitialized `let deferred: i32;` is a zero-valued `var` that the
  result adds, since Go rejects unused locals. Unused metadata and primitive
  locals are consumed by blank assignments for the same reason.
- Primitive types: `u8` is `uint8`, `u32` is `uint32`, `usize` is `uintptr`,
  `i64` is `int64`, `f32` is `float32`, `char` is `rune`, `&str` is `string`
  and `*const u8` is a nil `*byte`.
- Rust's doubled grouping `((inferred))` is a single `(inferred)`, the form
  gofmt keeps.
- Trailing commas in parameter, argument, array and struct-literal lists use
  multi-line lists, where Go requires them.
- The runtime probe allocates with `make`, reads `os.Args`, `os.Getwd` and
  `time.Now`, draws four bytes from `crypto/rand` (the system entropy source,
  like the C probe's `getrandom`), and opens `lanius/main.lani`. The program
  prints with `fmt.Println` and exits through `os.Exit`.
"""

from __future__ import annotations

from typical_project_constructs import RARE_SCORE_FUNCTIONS, rare_patterns_for_module
from typical_project_model import (
    VALUE_MASK,
    Module,
    Rule,
    TypicalProject,
    dependency_indices,
)


GO_MODULE = "typical"
GO_VERSION = "1.27"
M = VALUE_MASK


def render_go_project(project: TypicalProject) -> dict[str, str]:
    files = {"go.mod": f"module {GO_MODULE}\n\ngo {GO_VERSION}\n"}
    for module in project.modules:
        if module.index == project.entry_index:
            continue
        imports = [
            f"{GO_MODULE}/{project.modules[index].name}"
            for index in dependency_indices(module)
        ]
        files[f"{module.name}/module.go"] = _tabs(
            f"package {module.name}\n\n"
            + _import_block(_module_std_imports(module) + imports)
            + _render_module_api(project, module)
        )
    entry = project.modules[project.entry_index]
    imported = sorted(
        (set(project.roots) - {project.entry_index}) | set(dependency_indices(entry))
    )
    imports = ["crypto/rand", "fmt", "os", "time", *_module_std_imports(entry)]
    imports += [f"{GO_MODULE}/{project.modules[index].name}" for index in imported]
    calls = []
    for index in project.roots:
        call = (
            "Evaluate(7)"
            if index == project.entry_index
            else f"{project.modules[index].name}.Evaluate(7)"
        )
        calls.append(f"    total = (total + {call}) & {M}")
    files["main.go"] = _tabs(
        "package main\n\n"
        + _import_block(imports)
        + _render_module_api(project, entry)
        + "\n"
        + RUNTIME_PROBE
        + "\nfunc main() {\n"
        "    runtimeStatus := runtimeProbe()\n"
        "    if runtimeStatus != 0 {\n"
        "        os.Exit(int(runtimeStatus))\n"
        "    }\n"
        "    var total int32\n"
        + "\n".join(calls)
        + "\n    fmt.Println(total)\n    os.Exit(0)\n}\n"
    )
    return files


def go_name(snake: str) -> str:
    head, *rest = snake.split("_")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


def _tabs(source: str) -> str:
    """Templates indent with four spaces; Go source indents with tabs."""
    lines = []
    for line in source.split("\n"):
        stripped = line.lstrip(" ")
        depth = (len(line) - len(stripped)) // 4
        lines.append("\t" * depth + stripped)
    return "\n".join(lines)


def _import_block(paths: list[str]) -> str:
    unique = sorted(set(paths))
    if not unique:
        return ""
    return "import (\n" + "".join(f'    "{path}"\n' for path in unique) + ")\n\n"


def _module_std_imports(module: Module) -> list[str]:
    return ["syscall"] if "foreign_api" in rare_patterns_for_module(module.index) else []


def _render_module_api(project: TypicalProject, module: Module) -> str:
    source = _render_archetype(module.archetype, module.index)
    source += _render_rare_patterns(module.index)
    source += "".join(_render_rule(rule) for rule in module.rules)
    lines = [
        f"func BaseRate(value int32) int32 {{ return (value + {module.base_rate} + {module.index * 3}) & {M} }}",
        "",
        "func Evaluate(seed int32) int32 {",
        "    total := BaseRate(seed)",
        f"    total = (total + workloadScore(seed)) & {M}",
    ]
    if rare_patterns_for_module(module.index):
        lines.append(f"    total = (total + rareConstructScore(seed)) & {M}")
    for rule in module.rules:
        lines.append(f"    total = {go_name(rule.name)}(total, seed)")
    for child, salt in zip(module.children, module.child_salts):
        name = project.modules[child].name
        lines.append(f"    total = (total + {name}.Evaluate((seed+{salt})&{M})) & {M}")
    for dependency, salt in zip(module.support_dependencies, module.support_salts):
        name = project.modules[dependency].name
        lines.append(f"    total = (total + {name}.BaseRate((seed+{salt})&{M})) & {M}")
    lines.extend(("    return total", "}", ""))
    return source + "\n".join(lines)


def _render_rule(rule: Rule) -> str:
    lines = [
        f"func {go_name(rule.name)}(value int32, context int32) int32 {{",
        "    result := value",
    ]
    for step in rule.steps:
        if step.kind == "offset":
            lines.append(f"    result = (result + {step.a} + context) & {M}")
        elif step.kind == "scale":
            lines.append(f"    result = (result*{step.a % 7 + 2} + {step.b}) & {M}")
        elif step.kind == "threshold":
            lines.extend(
                (
                    f"    if result > {512 + step.b % 3072} {{",
                    f"        result = (result - {step.a}) & {M}",
                    "    } else {",
                    f"        result = (result + {step.a}) & {M}",
                    "    }",
                )
            )
        elif step.kind == "clamp":
            maximum = 1024 + step.b % 3072
            lines.extend(
                (
                    f"    if result > {maximum} {{",
                    f"        result = {maximum}",
                    "    }",
                )
            )
        else:
            raise ValueError(step.kind)
    lines.extend(("    return result", "}", ""))
    return "\n".join(lines) + "\n"


def _render_archetype(archetype: str, index: int) -> str:
    if archetype == "policy":
        return f"""type adjustment interface{{ isAdjustment() }}

type addAdjustment struct{{ amount int32 }}

type holdAdjustment struct{{}}

func (addAdjustment) isAdjustment() {{}}

func (holdAdjustment) isAdjustment() {{}}

func chooseAdjustment(seed int32) adjustment {{
    if seed&1 == 0 {{
        return addAdjustment{{amount: seed%7 + 1}}
    }}
    return holdAdjustment{{}}
}}

func workloadScore(seed int32) int32 {{
    switch chosen := chooseAdjustment(seed).(type) {{
    case addAdjustment:
        return (seed + chosen.amount) & {M}
    case holdAdjustment:
        return (seed - 1) & {M}
    }}
    panic("unreachable adjustment")
}}

"""
    if archetype == "processor":
        return f"""func workloadScore(seed int32) int32 {{
    values := [6]int32{{seed, {index & 31}, 3, 7, 11, 13}}
    cursor := 0
    var total int32
    for cursor < len(values) {{
        if cursor == 1 {{
            cursor++
            continue
        }}
        if cursor == 5 {{
            break
        }}
        total = (total + values[cursor]) & {M}
        cursor++
    }}
    return total
}}

"""
    if archetype == "service":
        return f"""type serviceState struct {{
    left  int32
    right int32
}}

func newServiceState(seed int32) serviceState {{
    return serviceState{{left: (seed + {index}) & {M}, right: (seed*2 + 3) & {M}}}
}}

func (state serviceState) adjusted(amount int32) serviceState {{
    return serviceState{{left: state.left + amount, right: state.right - amount}}
}}

func (state serviceState) score() int32 {{ return (state.left*3 + state.right) & {M} }}

func workloadScore(seed int32) int32 {{
    return newServiceState(seed).adjusted({index % 7 + 1}).score()
}}

"""
    if archetype == "planner":
        return f"""func firstEligible(seed int32) int32 {{
    for candidate := range int32(6) {{
        if (seed+candidate)%4 == 0 {{
            return candidate
        }}
    }}
    return 6
}}

func workloadScore(seed int32) int32 {{
    var total int32
    var limit int32 = {3 + index % 4}
    for outer := range limit {{
        for inner := range int32(3) {{
            if inner == 1 && outer%2 == 0 {{
                continue
            }}
            total = (total + seed + outer*3 + inner) & {M}
        }}
    }}
    {{
        total := total
        if total < 0 {{
            return 0
        }}
    }}
    return (total + firstEligible(seed)) & {M}
}}

"""
    if archetype == "tracker":
        return f"""func decay(value int32, remaining int32) int32 {{
    if remaining <= 0 {{
        return value
    }}
    mixed := ((value << 1) ^ (value >> 1) ^ {index}) & {M}
    return decay(mixed, remaining-1)
}}

func workloadScore(seed int32) int32 {{
    var delta int32 = -{index % 5 + 1}
    enabled := !false
    if enabled {{
        return (decay(seed, 3) - delta) & {M}
    }}
    return 0
}}

"""
    if archetype == "summary":
        return f"""type summaryScore = int32

const summaryOffset summaryScore = {index}

type envelope[T any] struct {{
    value T
}}

func unwrap[T any](wrapped envelope[T]) T {{ return wrapped.value }}

func workloadScore(seed int32) int32 {{
    wrapped := envelope[int32]{{value: seed + summaryOffset}}
    return unwrap(wrapped) & {M}
}}

"""
    raise ValueError(archetype)


def _render_rare_patterns(index: int) -> str:
    patterns = rare_patterns_for_module(index)
    if not patterns:
        return ""
    definitions = "".join(_render_rare_pattern(pattern, index) for pattern in patterns)
    statements: list[str] = []
    for pattern in patterns:
        if pattern in RARE_SCORE_FUNCTIONS:
            function, arguments = RARE_SCORE_FUNCTIONS[pattern]
            statements.append(
                f"    total = (total + {go_name(function)}({arguments})) & {M}"
            )
        elif pattern == "contracts":
            statements.append(
                f"    total = (total + int32(preserveScored(scoredI32(seed)))) & {M}"
            )
        elif pattern == "const_generic":
            statements.append(
                f"    total = (total + firstConstGeneric(seed, [4]int32{{seed, {index}, 3, 7}})) & {M}"
            )
        elif pattern == "borrowed_views":
            statements.extend(
                (
                    "    borrowed := borrowedValue{value: seed}",
                    f"    total = (total + borrowed.borrowedMarker()) & {M}",
                    f"    sliceValues := [4]int32{{seed, {index}, 3, 7}}",
                    f"    total = (total + firstSlice(sliceValues[:])) & {M}",
                )
            )
        elif pattern == "foreign_api":
            statements.extend(
                (
                    "    observedProcess := int32(getpid())",
                    "    if observedProcess < 0 {",
                    "        return 1",
                    "    }",
                )
            )
        else:
            raise ValueError(pattern)
    return (
        definitions
        + "func rareConstructScore(seed int32) int32 {\n"
        "    var total int32\n"
        + "\n".join(statements)
        + "\n    return total\n}\n\n"
    )


def _render_rare_pattern(pattern: str, index: int) -> str:
    if pattern == "contracts":
        return f"""type scorePolicy[T any] interface {{
    scorePolicy(value T) int32
}}

type scoredI32 int32

func (scoredI32) scorePolicy(value scoredI32) int32 {{ return int32(value) & {M} }}

func preserveScored[T scorePolicy[T]](value T) T {{ return value }}

"""
    if pattern == "const_generic":
        return """func firstConstGeneric(first int32, values [4]int32) int32 { return first }

"""
    if pattern == "borrowed_views":
        return """type borrowedValue struct {
    value int32
}

func (borrowed *borrowedValue) borrowedMarker() int32 { return borrowed.value }

func firstSlice(values []int32) int32 { return values[0] }

"""
    if pattern == "foreign_api":
        return """var getpid = syscall.Getpid

"""
    if pattern == "literal_data":
        return f"""func literalMetadata() int32 {{
    var label string = "module-{index}"
    var delimiter rune = ':'
    var ratio float32 = 1.25
    _, _, _ = label, delimiter, ratio
    return 0
}}

"""
    if pattern == "language_forms":
        return """var unboundProbe func() int32

func zeroValue() int32 { return 0 }

func recordPositive(value int32) {
    if value > 0 {
        return
    }
}

func languageForms(seed int32) int32 {
    inferred := seed
    grouped := (inferred)
    recordPositive(grouped)
    return grouped + zeroValue()
}

"""
    if pattern == "operator_forms":
        return f"""func operatorForms(seed int32) int32 {{
    value := seed
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
        return """func primitiveForms() int32 {
    var tiny uint8 = 1
    var unsigned uint32 = 2
    var count uintptr = 3
    var wide int64 = 4
    var decimal float32 = 1.5
    var truth bool = true
    var letter rune = 'x'
    var text string = "types"
    var address *byte = nil
    _, _, _, _, _ = tiny, unsigned, count, wide, decimal
    _, _, _, _ = truth, letter, text, address
    return 0
}

"""
    if pattern == "range_forms":
        return f"""func rangeForms(seed int32) int32 {{
    total := seed
    for value := int32(1); value <= 3; value++ {{
        total = (total + value) & {M}
    }}
    for value := range int32(3) {{
        total = (total + value) & {M}
    }}
    for value := int32(0); value <= 2; value++ {{
        total = (total + value) & {M}
    }}
    for value := int32(2); ; value++ {{
        total = (total + value) & {M}
        if value == 4 {{
            break
        }}
    }}
    for value := int32(0); ; value++ {{
        total = (total + value) & {M}
        if value == 2 {{
            break
        }}
    }}
    return (total - 24) & {M}
}}

"""
    if pattern == "match_forms":
        return """func integerPatternScore(value int32) int32 {
    switch value {
    case 0:
        return 5
    case 1:
        return 7
    default:
        return 9
    }
}

func booleanPatternScore(value bool) int32 {
    switch value {
    case true:
        return 3
    default:
        return 4
    }
}

func matchForms(seed int32) int32 {
    return integerPatternScore(seed%3) + booleanPatternScore(seed&1 == 0)
}

"""
    if pattern == "enum_tuple_patterns":
        return """type coordinateEvent interface{ isCoordinateEvent() }

type movedEvent struct{ x, y int32 }

type idleEvent struct{}

func (movedEvent) isCoordinateEvent() {}

func (idleEvent) isCoordinateEvent() {}

func coordinateEventScore(event coordinateEvent) int32 {
    switch event := event.(type) {
    case movedEvent:
        return event.x*3 + event.y
    case idleEvent:
        return 1
    }
    panic("unreachable coordinate event")
}

func enumTuplePatterns(seed int32) int32 {
    return coordinateEventScore(movedEvent{seed % 7, (seed / 7) % 7}) + coordinateEventScore(idleEvent{})
}

"""
    if pattern == "iterable_forms":
        return f"""func iterableForms(seed int32) int32 {{
    values := [4]int32{{seed, 2, 3, 4}}
    var total int32
    for _, value := range values {{
        total = (total + value) & {M}
    }}
    return (total - 9) & {M}
}}

"""
    if pattern == "trailing_lists":
        return """type trailingRecord struct {
    left  int32
    right int32
}

func trailingSum(
    left int32,
    right int32,
) int32 {
    values := [2]int32{
        left,
        right,
    }
    record := trailingRecord{
        left:  values[0],
        right: values[1],
    }
    return record.left + record.right
}

func trailingLists(seed int32) int32 {
    return trailingSum(
        seed,
        0,
    )
}

"""
    if pattern == "generic_arity":
        return """type genericPair[Left, Right any] struct {
    left  Left
    right Right
}

type genericScorePair[Right any] = genericPair[int32, Right]

func genericPairLeft(value genericScorePair[bool]) int32 {
    var left int32 = value.left
    return left
}

func genericArity(seed int32) int32 {
    return genericPairLeft(genericPair[int32, bool]{left: seed, right: true})
}

"""
    if pattern == "pattern_list_forms":
        return """type patternListEvent interface{ isPatternListEvent() }

type patternListEmpty struct{}

type patternListValue struct{ inner int32 }

func (patternListEmpty) isPatternListEvent() {}

func (patternListValue) isPatternListEvent() {}

func patternListScore(value patternListEvent) int32 {
    switch value := value.(type) {
    case patternListEmpty:
        return 0
    case patternListValue:
        return value.inner
    }
    panic("unreachable pattern list event")
}

func patternListForms(seed int32) int32 {
    return patternListScore(patternListEmpty{}) + patternListScore(patternListValue{seed})
}

"""
    if pattern == "bound_list_forms":
        return """type boundScorePolicy[T any] interface {
    boundScorePolicy(value T) int32
}

type stableBoundPolicy[T any] interface {
    stableBoundPolicy(value T) int32
}

type pairBoundPolicy[Left, Right any] interface {
    pairBoundPolicy(left Left, right Right) int32
}

type boundI32 int32

type boundBool bool

func (boundI32) boundScorePolicy(value boundI32) int32 { return int32(value) }

func (boundI32) stableBoundPolicy(value boundI32) int32 { return int32(value) }

func (boundBool) boundScorePolicy(value boundBool) int32 {
    if value {
        return 1
    }
    return 0
}

func (boundI32) pairBoundPolicy(left boundI32, _ boundBool) int32 { return int32(left) }

func preserveBoundPair[
    Left interface {
        boundScorePolicy[Left]
        stableBoundPolicy[Left]
        pairBoundPolicy[Left, Right]
    },
    Right boundScorePolicy[Right],
](left Left, _ Right) Left {
    return left
}

func boundListForms(seed int32) int32 {
    return int32(preserveBoundPair(boundI32(seed), boundBool(true)))
}

"""
    if pattern == "statement_postfix_forms":
        return """type statementRecord struct {
    value int32
}

func (record statementRecord) StatementValue() int32 { return record.value }

func observeStatement(value int32) {}

func makeStatementRecord(value int32) statementRecord { return statementRecord{value: value} }

func statementPostfixForms(seed int32) int32 {
    var deferred int32
    observeStatement(0)
    record := statementRecord{value: seed}
    return record.StatementValue() + makeStatementRecord(0).value + deferred
}

"""
    if pattern == "public_items":
        return """const PublicZero int32 = 0

type PublicScore = int32

type PublicRecord struct {
    Value PublicScore
}

type PublicChoice interface{ isPublicChoice() }

type PublicChoiceSelected struct{ Inner int32 }

type PublicChoiceEmpty struct{}

func (PublicChoiceSelected) isPublicChoice() {}

func (PublicChoiceEmpty) isPublicChoice() {}

type PublicPolicy[T any] interface {
    PublicPolicy(value T) int32
}

func (record PublicRecord) Read() int32 { return record.Value }

func publicItems(seed int32) int32 {
    record := PublicRecord{Value: seed}
    var choice PublicChoice = PublicChoiceSelected{Inner: 0}
    var adjustment int32
    switch chosen := choice.(type) {
    case PublicChoiceSelected:
        adjustment = chosen.Inner
    case PublicChoiceEmpty:
        adjustment = 0
    }
    return record.Read() + adjustment + PublicZero
}

"""
    if pattern == "empty_aggregates":
        return """type emptyRecord struct{}

func emptyAggregates(seed int32) int32 {
    emptyRecordValue := emptyRecord{}
    var emptyValues [0]int32 = [0]int32{}
    _, _ = emptyRecordValue, emptyValues
    return seed
}

"""
    raise ValueError(pattern)


RUNTIME_PROBE = """func runtimeProbe() int32 {
    memory := make([]byte, 32)
    memory[0] = 1
    if len(os.Args) < 1 {
        return 1
    }
    if _, err := os.Getwd(); err != nil {
        return 2
    }
    if time.Now().Unix() <= 0 {
        return 3
    }
    var randomBytes [4]byte
    if _, err := rand.Read(randomBytes[:]); err != nil {
        return 4
    }
    source, err := os.Open("lanius/main.lani")
    if err != nil {
        return 5
    }
    if err := source.Close(); err != nil {
        return 6
    }
    if memory[0] != 1 {
        return 7
    }
    return 0
}
"""
