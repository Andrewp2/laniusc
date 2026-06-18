# Aggregates And Indexing

This chapter describes the current `unstable-alpha` aggregate surface:
structs, enums, arrays, slices, struct literals, enum constructors, field
access, indexing, and the current backend boundaries around aggregate lowering.

Use [Items and declarations](items-and-declarations.md) for declaration syntax,
[Types and values](types-and-values.md) for the broader type model,
[Patterns and matching](patterns-and-matching.md) for enum match patterns, and
[Expressions and control flow](expressions-and-control-flow.md) for the
expression-level behavior around calls, member access, assignment, and loops.

For exact support claims, use the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md), especially
the `parser-hir`, `semantics`, and `codegen` rows for struct fields, array
literals, enum payloads, match payloads, aggregate metadata, and x86
fail-closed boundaries.

## Aggregate Families

The current source language has these aggregate-like families:

| Family | Example | Main use |
| --- | --- | --- |
| Struct | `struct Pair { left: i32, right: i32 }` | nominal records with named fields |
| Enum | `enum Option<T> { Some(T), None }` | nominal variants with optional tuple payloads |
| Array | `[i32; 4]` | fixed-size element sequence |
| Slice | `[i32]` | unsized view-shaped type surface, currently bounded |

These forms are not interchangeable. A struct field, enum payload, array
element, and slice element all have different records and support boundaries.

## Structs

A struct declaration introduces a nominal type with named fields:

```lanius
struct Pair {
    left: i32,
    right: i32,
}

fn score(pair: Pair) -> i32 {
    return pair.left * 10 + pair.right;
}
```

Field names are checked against the selected struct declaration. Same-spelled
fields on unrelated structs do not become a structural type relation.

Duplicate fields in one struct are rejected by aggregate validation:

```lanius
struct Bad {
    value: i32,
    value: bool,
}
```

That rejection should point at the duplicate declaration, not let a later field
read select the first or last field by accident.

## Struct Literals

Struct literals construct values by field name:

```lanius
let pair: Pair = Pair { left: 7, right: 5 };
```

The literal is typed by the resolved struct identity and the surrounding
context. Parser HIR records retain struct literal fields, owner links, field
ordinals, value expressions, and source spans so type checking and codegen do
not infer field meaning from spelling alone.

Trailing commas are accepted in struct literals:

```lanius
let pair: Pair = Pair { left: 7, right: 5, };
```

## Field Access And Assignment

Member access reads a field from a resolved aggregate receiver:

```lanius
fn sum(pair: Pair) -> i32 {
    return pair.left + pair.right;
}
```

The current x86 slice has bounded evidence for selected struct literals,
member reads, aggregate copies, and field updates:

```lanius
fn bump(pair: Pair) -> Pair {
    let next: Pair = pair;
    next.left += 2;
    next.right = next.left - 1;
    return next;
}
```

Nested aggregate receivers and member reads from aggregate return temporaries
are narrower backend boundaries. Shapes such as `outer.inner.left` or
`make_pair().left` should fail closed until aggregate path rows and temporary
materialization feed native member lowering.

## Enums

An enum declaration introduces a nominal set of variants:

```lanius
enum Ordering {
    Less,
    Equal,
    Greater,
}
```

Variants can be unit variants or tuple-payload variants:

```lanius
enum Option<T> {
    Some(T),
    None,
}
```

Enum constructors are value names in expression contexts supported by the
current slice:

```lanius
let value: core::option::Option<i32> = core::option::Some(7);
let none: core::option::Option<i32> = core::option::None;
```

Generic enum constructors and match payload substitution have bounded
type-checker evidence. Backend support is narrower. In particular,
multi-payload enum constructors can type-check in frontend contexts but still
fail closed in x86 lowering until the target carries broader payload layout
rows.

## Matching Enums

`match` consumes enum values through pattern rows:

```lanius
fn to_i32(ordering: Ordering) -> i32 {
    return match (ordering) {
        Less -> -1,
        Equal -> 0,
        Greater -> 1,
    };
}
```

Tuple-payload patterns introduce arm-local bindings:

```lanius
fn unwrap_or(value: Option<i32>, fallback: i32) -> i32 {
    return match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
}
```

Use [Patterns and matching](patterns-and-matching.md) for pattern syntax,
binding scope, payload order, exhaustiveness boundaries, and target execution
notes. This chapter treats enum matching as part of aggregate use; the pattern
chapter owns the detailed match-arm rules.

## Arrays

An array type has an element type and a fixed length:

```lanius
let values: [i32; 5] = [3, 1, 4, 1, 5];
```

Array literals are element lists:

```lanius
fn filled4(value: i32) -> [i32; 4] {
    return [value, value, value, value];
}
```

The parser records array literal context so type checking can compare literal
length and element types against the expected array type. A length mismatch
should be reported at the source literal or contextual declaration.

## Array Indexing

Indexing is postfix syntax:

```lanius
fn sum4(values: [i32; 4]) -> i32 {
    return values[0] + values[1] + values[2] + values[3];
}
```

Dynamic indexing is supported in bounded x86 rows for local arrays:

```lanius
fn sum(values: [i32; 5]) -> i32 {
    let index: i32 = 0;
    let total: i32 = 0;
    while (index < 5) {
        total += values[index];
        index += 1;
    }
    return total;
}
```

The x86 backend also has bounded evidence for indexed assignments and selected
unsigned indexed compound division/modulo. Statically known out-of-bounds array
indexes fail closed before native indexed memory access:

```lanius
fn invalid(values: [i32; 4]) -> i32 {
    return values[4];
}
```

That diagnostic is a backend safety boundary, not a general compile-time
constant-evaluation rule for every target and expression shape.

## Arrays In Loops And Returns

Arrays can be passed to and returned from functions in bounded cases:

```lanius
fn copy4(values: [i32; 4]) -> [i32; 4] {
    return values;
}

fn reversed4(values: [i32; 4]) -> [i32; 4] {
    return [values[3], values[2], values[1], values[0]];
}
```

The x86 backend has bounded evidence for array `for` loops with `break` and
`continue`, but scalar `for` iterables remain a fail-closed backend boundary.
Use [Expressions and control flow](expressions-and-control-flow.md) for loop
semantics and target execution details.

## Slices

Slice types use `[T]`:

```lanius
type I32Slice = [i32];
```

The source-level stdlib has slice helper declarations such as:

```lanius
pub fn first_i32(values: [i32]) -> i32 {
    return values[0];
}
```

Slices do not have runtime metadata yet. Current helper APIs pass lengths
explicitly where needed, and x86 lowering for unsized slice parameter indexing
is a fail-closed boundary. A program can type-check a slice-shaped helper while
target execution still rejects the unsized index shape before native memory
planning loses the source span.

## Generic Aggregates

Structs and enums can be generic:

```lanius
struct Boxed<T> {
    value: T,
}

enum Option<T> {
    Some(T),
    None,
}
```

The current type checker has bounded evidence for nominal generic instances,
repeated generic slot consistency, selected generic enum constructors, selected
generic enum match payload substitutions, and methods on concrete generic
receivers.

Nested generic instances, unknown instance argument slots, generic enum backend
layout, and nested aggregate member lowering remain row-based support
questions. Use [Generics and bounds](generics-and-bounds.md) for generic
parameter and type-argument rules.

## Backend Boundary

Type checking an aggregate does not prove that every target can execute it.
Current x86 evidence includes selected:

- struct literals and field reads
- aggregate copies and field updates
- array literals, array returns, array reads, and indexed assignments
- static out-of-bounds array diagnostics
- unit and one-payload enum constructor/match shapes
- source-pack qualified enum constructors in stdlib-shaped helpers

Current fail-closed x86 boundaries include:

- multi-payload enum constructor lowering
- unsized slice parameter indexing
- member reads from aggregate return temporaries
- nested aggregate member receivers
- scalar `for` iterables

`wasm` currently accepts the target selector but fails closed at the backend
boundary.

## What Not To Infer

Do not infer these stronger claims from aggregate syntax:

- Structs are structurally typed because fields have matching names.
- Every parsed struct literal or enum constructor is executable on every target.
- Enum matches have broad exhaustiveness checking.
- Slice types carry runtime length metadata.
- Array indexing has broad compile-time bounds reasoning for every expression.
- Generic aggregate type checking implies backend layout support.
- Nested aggregate member access is generally lowered.

## Updating This Chapter

When aggregate behavior changes:

1. Update focused tests at the owner boundary: parser-HIR records, type checker
   aggregate validation, enum payload typing, member/index projection, or
   backend aggregate lowering.
2. Update `docs/language_slice_unstable_alpha.tsv` and regenerate the slice
   when a public support row changes.
3. Update this chapter for user-visible aggregate rules, examples, diagnostics,
   and backend boundaries.
4. Keep row strides, bind groups, and shader pass details in compiler internals
   or generated references unless they directly explain a user-visible
   diagnostic.
5. Run `tools/docs_check.py`.
