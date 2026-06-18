# Patterns And Matching

This chapter describes the current `unstable-alpha` pattern and `match`
surface. It is the focused reference for forms that appear inside match arms,
while [Expressions and control flow](expressions-and-control-flow.md) explains
where `match` fits in expression behavior and backend execution.
Use [Name resolution](name-resolution.md) for how enum variants, qualified
constructor paths, and payload bindings resolve.
Use [Aggregates and indexing](aggregates-and-indexing.md) for enum
declarations, constructors, payloads, and aggregate backend boundaries.

For exact support claims, use the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md), especially
the parser-HIR, semantics, diagnostics, and codegen rows that mention match
records, payload records, enum constructors, or backend enum/match lowering.
The grammar source is [grammar/lanius.bnf](../../grammar/lanius.bnf).

## Match Expressions

`match` is a primary expression. The scrutinee is parenthesized, arms are
braced, and each arm maps one pattern to one expression with `->`:

```lanius
enum Choice {
    Yes,
    No,
}

fn score(value: Choice) -> i32 {
    return match (value) {
        Yes -> 1,
        No -> 0,
    };
}
```

The grammar accepts an empty arm list, but no useful expression value is
documented for an empty match. Current examples should give at least one arm
and should rely on generated slice evidence before claiming broad exhaustivity,
irrefutability, or defaulting behavior.

## Pattern Forms

The current grammar accepts these pattern families:

| Pattern family | Example | Notes |
| --- | --- | --- |
| Path pattern | `Some`, `core::result::Ok`, `inner` | Used for enum variants and payload bindings in supported contexts. |
| Tuple-payload pattern | `Some(inner)`, `Ok(value)` | Matches tuple-like enum variant payloads. |
| Integer literal pattern | `0`, `1` | Literal matching is parser-supported; semantic/backend support is row-based. |
| Boolean literal pattern | `true`, `false` | Useful for boolean matches in bounded type-checker/backend rows. |

Patterns are not a Rust-compatible pattern language. The current reference does
not document wildcard patterns, or-patterns, range patterns, guards, reference
patterns, slice patterns, struct patterns, rest patterns, mutable bindings, or
binding annotations.

## Path Patterns

A path pattern is a `::`-separated path. It can name an enum constructor or a
binding depending on the matched type and the current type-checker context:

```lanius
enum OptionI32 {
    Some(i32),
    None,
}

fn unwrap_or(value: OptionI32, fallback: i32) -> i32 {
    return match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
}
```

In the `Some(inner)` arm, `Some` names the tuple-payload variant and `inner` is
the payload binding used by the arm expression. In the `None` arm, `None` names
the unit variant and introduces no payload binding.

Qualified constructor paths are used by stdlib-shaped examples:

```lanius
fn ok_value(value: core::result::Result<i32, bool>) -> i32 {
    return match (value) {
        core::result::Ok(inner) -> inner,
        core::result::Err(error) -> 0,
    };
}
```

Whether an unqualified or qualified path resolves depends on module imports,
visibility, and the current resolver/type-checker rows. Ambiguous imported
names should be rejected rather than resolved by source order or import order.

## Tuple-Payload Patterns

Tuple-payload patterns attach a parenthesized payload pattern list to a path:

```lanius
enum ResultI32Bool {
    Ok(i32),
    Err(bool),
}

fn contains(value: ResultI32Bool, expected: i32) -> bool {
    return match (value) {
        Ok(inner) -> inner == expected,
        Err(error) -> false,
    };
}
```

Payload patterns are ordered. Parser HIR rows retain arm identity, payload
ordinal, file identity, and source-span linkage so later phases can diagnose
the payload that failed. The generated slice has explicit parser-HIR rows for
match payload records and contiguous payload ordinals.

The strongest semantic evidence today is selected enum payload substitution,
including bounded generic enum payload cases. That does not imply arbitrary
tuple arity, every nested payload type, or executable backend lowering for all
enum shapes.

## Literal Patterns

Integer, `true`, and `false` patterns are grammar forms:

```lanius
fn bool_score(value: bool) -> i32 {
    return match (value) {
        true -> 1,
        false -> 0,
    };
}
```

Literal pattern syntax and target execution are separate. The parser can record
a literal pattern while a later type-checker or backend row may reject the
specific matched type, arm expression, or lowering shape.

## Binding Scope

Payload bindings introduced by a pattern are scoped to the arm expression:

```lanius
fn unwrap_or(value: OptionI32, fallback: i32) -> i32 {
    return match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
}
```

`inner` is available in the expression for the `Some(inner)` arm only. It is not
a declaration in the surrounding function and is not available in sibling arms.
Bindings should carry source spans from the payload pattern so type errors in
the arm can point back to the relevant binding or payload.

The current language does not document binding modes such as `ref`, `mut`, or
`@` patterns.

## Arm Result Types

A `match` expression must produce a type the current type checker can validate
for the context that uses it:

```lanius
fn choose(flag: bool, left: i32, right: i32) -> i32 {
    return match (flag) {
        true -> left,
        false -> right,
    };
}
```

If one arm returns `i32` and another returns `bool`, the type checker should
reject the match through a source-spanned diagnostic. If the match type is valid
but the selected backend cannot lower the expression, the backend should fail
closed at the match, constructor, payload, or arm expression that explains the
unsupported shape.

## Exhaustiveness And Reachability

This reference does not claim broad exhaustiveness checking. Current support is
bounded around parser records, selected enum constructor and payload typing,
and selected backend enum/match lowering.

For user-facing code, write arms that cover every known variant or literal case
needed by the current type. Do not rely on an implicit default arm, wildcard
arm, source-order fallthrough, or compiler-synthesized value for missing cases.

## Backend Boundary

The x86 backend has bounded enum/match support through target-specific
enum/match records. That support is narrower than parser acceptance. In
particular:

- a parsed match can fail at type checking if variants, payloads, or arm result
  types do not line up
- a type-checked match can fail at backend lowering if the enum, payload, or
  aggregate shape is outside the target slice
- `wasm` currently accepts the target selector but fails closed at the backend
  boundary

Unsupported match behavior should be reported as a source-spanned diagnostic,
not as a raw backend status or silently generated fallback value.

## What Not To Infer

Do not infer these stronger claims from pattern syntax:

- `match` is exhaustive for every enum or literal type.
- `_`, `|`, guards, ranges, destructuring structs, or slice patterns exist.
- Tuple-payload patterns support arbitrary arity and nesting.
- A stdlib enum constructor is implicitly visible without imports or module
  qualification.
- Type-checked enum matches execute on every target.

## Updating This Chapter

When match or pattern behavior changes:

1. Update parser-HIR, type-checker, diagnostic, or backend evidence for the
   changed boundary.
2. Update `docs/language_slice_unstable_alpha.tsv` and regenerate the slice if
   a public support row changes.
3. Keep this chapter focused on user-facing pattern rules; compiler pass names
   and volatile buffer layouts belong in generated references and compiler
   internals docs.
4. Run `tools/docs_check.py`.
