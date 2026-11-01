# Verified facts: `distinct` types and `requires` clauses

Status: implemented on `lang`, 2026-10-27, except where marked *not yet*.

## Summary

Two small features let a program state facts that the compiler checks:

- **`distinct` types.** `type Meters = distinct i64;` is a new type with the
  same representation as `i64`. A `Meters` value never silently becomes a
  `Seconds` value. This is the Odin/Jai idea, and the scoped-stacks design
  uses it for typed handles.
- **`requires` clauses.** `fn halve(n: i32) -> i32 requires (n >= 0) { ... }`
  states a precondition. Today it runs as a check on entry and traps when the
  condition is false. Later, the verified compiler can prove such a fact at
  each call site and delete the check.

Both features are deliberately signature-level. A fact sits where a caller
and a proof tool can see it without reading the body.

## `distinct` types

### Syntax

```
type Meters = distinct i64;
type Seconds = distinct i64;
type Span = Meters;          // a plain alias of a distinct type is the same type
```

`distinct` is a keyword only in this one position: right after the `=` of a
type alias and right before a type name. Everywhere else it is an ordinary
identifier, so `let distinct: i64 = 3;` still works and no existing program
breaks. The lexer retags the word to `TK_DISTINCT` only when the previous
token is a single `=` and the next token is a non-keyword identifier. The
grammar gives the alias production an optional `distinct_opt` symbol.

### Semantics

A distinct alias stays **transparent** for type checking, layout and code
generation: `Meters` is checked, stored and lowered exactly like `i64`. A
separate pass, `type_checker/conditions/compact_distinct`, then checks
**brands**:

- A value's brand is the distinct alias it was declared with. The pass
  follows chains of plain aliases (`Span` → `Meters`).
- Values of any other type have the brand BASE. Literals have the brand
  LITERAL and take the brand of their context. A value the pass does not
  follow has the brand UNKNOWN.
- The pass rejects a pair when **both sides have known brands that differ**.
  BASE is a known brand, so a plain `i64` does not become a `Meters`, and a
  `Meters` does not become an `i64`, without `as`. LITERAL and UNKNOWN never
  cause an error. The error is `LNC0006`, with the label "this value's
  distinct type differs from the one expected here" and a note suggesting
  `as`.

The pass checks these (expected, value) pairs:

| Site | Expected | Value |
| --- | --- | --- |
| `let x: T = v` | `T` | `v` |
| `return v` | the function's return type | `v` |
| `x = v`, `x += v` | `x` | `v` |
| call argument | the parameter's type | the argument, skipping `self` on a method call |
| `a + b`, `a < b`, … | `a` | `b` |

A value's brand comes from its declaration: a local's annotation, a
parameter's type, a field's declared type, a call's return type, or a cast's
target type. Arithmetic keeps the brand of its operands, so `m + m` is still
`Meters`.

`as` converts in either direction: `total as i64`, `raw as Meters`.

### Decisions

- **No implicit conversion either way, as in Odin.** Only literals mix
  freely, so `let m: Meters = 4;` and `m * 2` need no cast. This matches the
  handle rule in `docs/memory-scoped-stacks-design.md`. Arithmetic is allowed
  on every distinct type; whether a declaration should opt in to it is still
  an open question there.
- **Unfollowed values are accepted.** The pass gives up (UNKNOWN) rather than
  guess, so its holes, listed below, accept programs and never reject a
  correct one.
- **A separate pass, not a new type ID.** Giving distinct types their own
  canonical type IDs would touch every type-equality site in the GPU type
  checker, generic instantiation and both back ends. The brand pass is two
  kernels:
  - `compact_distinct_nodes` (122 inlined instructions) maps tokens to HIR
    rows;
  - `compact_distinct` (3,327 inlined instructions) checks the pairs.

  They run only when the unit has type aliases.
- **Stackless walk.** The pass finds a value's brand by walking the
  expression tree without a stack or per-thread array. On a literal it climbs
  parent links to resume at the other operand. `brand_of` has one call site,
  so it is inlined once.

### Known holes (*not yet*)

The pass does not check these, so they are accepted silently:

- generic parameters and type arguments (`Vec<Meters>` vs `Vec<Seconds>`);
- aggregate types built from distinct ones (`[Meters; 4]`, `&Meters`);
- index, `match` and struct-literal values, and struct-literal fields;
- distinct aliases declared in the standard library (the pass sees one unit's
  declarations).

Each of these is a missing (expected, value) pair or a missing walk step, not
a design change.

## `requires` clauses

### Syntax

```
fn halve(n: i32) -> i32 requires (n >= 0) requires (n % 2 == 0) {
    return n / 2;
}

impl Window {
    fn shrink(self, by: i32) -> i32 requires (by > 0 && by < self.width) { ... }
}
```

Any number of clauses can follow the `where` clause of a function or method.
`requires` and `ensures` are now reserved keywords. No tracked source used
either word as an identifier.

### Semantics

On entry, before the body runs, each clause's condition is evaluated in
order. If one is false, the program traps: `ud2` (SIGILL) on x86-64 and
`unreachable` on Wasm. This is the same trap as `test::assert`. The condition
must be `bool`, otherwise `LNC0006`. It can read the parameters, `self`
included.

### Implementation

- **Parser.** `contract_list_opt` follows `where_clause_opt` in `fn_item`
  and `impl_fn_item`. The contract production is
  `'Requires' 'GroupLParen' expr 'GroupRParen'`.
- **HIR.** A clause is an `if` record whose then arm is missing:
  `HIR_IF_STMT` with the condition in `b` and `c = d = INVALID`. Type
  checking of the condition comes for free from the `if` rules.
- **LIR.** `semantic_lir_is_contract` recognises that shape. It lowers to
  four rows, `IF_BEGIN, ELSE, TRAP, CONTROL_END`, which is
  `if (cond) {} else { trap }`.
  - The condition's HIR span includes the parentheses, so `IF_BEGIN` sorts
    last on the `)` token.
  - The other three rows are scheduled at the clause's end token: the next
    clause or the body's `{`. No other row opens at that token.

### Debug only? (*not yet*)

The plan calls these "debug run-time asserts". The compiler has no release
mode yet, so clauses are always checked. When a release mode exists, it
removes clauses the verified compiler has proved and keeps the rest.

### `ensures` (*not yet*)

`ensures (cond)` states a postcondition over a `result` binder. It needs two
things `requires` does not:

- a binder for the returned value;
- a check before every `return`, or one shared epilogue.

The keyword is reserved, and a clause is currently a syntax error. The plan
is to lower every `return v` in a function with postconditions to
`let result = v; <checks>; return result;` when the HIR is built.

## Toward the verified compiler

These facts are what the verified compiler and its optimizer will consume:

- A **`requires` clause** is a hypothesis for the body's proof and an
  obligation at each call site. The extraction pilot (`formal/`, the mini
  compiler) can carry it as a premise of the function's specification. When
  every call site is proved, the run-time check goes away. Until then it
  stays, so a missing proof costs speed, never soundness.
- A **distinct brand** is a refinement the optimizer can trust. Two
  differently branded values come from different sources. For handles into a
  pool, that means indexes from different pools never alias.
- Facts are **signature-level** so proofs stay modular. Checking a caller
  needs the callee's clauses, not its body. This matches the Aeneas-style
  extraction in Phase 4, where a function's Lean specification is generated
  from its signature.

## Tests

- `tests/language_ergonomics_execution.rs`:
  - `distinct_types_mix_with_themselves_literals_and_casts`
  - `distinct_types_reject_values_of_another_type` (seven rejection fixtures)
  - `requires_clauses_that_hold_let_the_body_run`
  - `a_broken_requires_clause_traps_before_the_body` (prints `4`, then
    SIGILL)
  - `a_requires_condition_must_be_bool`
- Fixtures: `tests/fixtures/language/distinct_types_*.lani` and
  `requires_*.lani`.
- `crates/laniusc-compiler/src/lexer/test_cpu.rs`:
  `distinct_is_a_keyword_only_between_assign_and_an_identifier`.
