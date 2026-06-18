# Lanius Expressions And Control Flow

This chapter describes expression and control-flow behavior in the current
`unstable-alpha` language slice. It is the behavior-facing companion to the
expression and statement sections in [Syntax reference](syntax.md).
Use [Patterns and matching](patterns-and-matching.md) for match arm syntax,
path patterns, tuple-payload patterns, literal patterns, binding scope, and
exhaustiveness boundaries.
Use [Aggregates and indexing](aggregates-and-indexing.md) for field access,
array indexing, aggregate assignment, enum constructors, slice indexing
boundaries, and aggregate backend lowering.
Use [Functions and calls](functions-and-calls.md) for function declarations,
parameters, arguments, direct calls, qualified calls, generic calls,
constructor calls, method calls, extern/runtime calls, and call ABI boundaries.
Use [Literals and operators](literals-and-operators.md) for literal families,
operator precedence, unary, binary, assignment, division, modulo, logical
operators, and their type/backend support boundaries.

The current compiler separates three questions:

- whether the parser accepts the source shape
- whether type checking can validate the source shape
- whether the selected backend can execute the validated shape

When this page names a supported behavior, it is a summary of generated slice
rows, compiler docs, and current stdlib examples. The generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md) remains the
row-level source of truth.

## Source Of Truth

Use these layers together:

| Question | Primary source |
| --- | --- |
| Which statement and expression forms parse? | [Syntax reference](syntax.md) and [grammar/lanius.bnf](../../grammar/lanius.bnf) |
| What types can expressions have? | [Types and values](types-and-values.md) |
| Which function and call forms are supported? | [Functions and calls](functions-and-calls.md) |
| Which pattern forms can match expressions use? | [Patterns and matching](patterns-and-matching.md) |
| Which aggregate/indexing forms are supported? | [Aggregates and indexing](aggregates-and-indexing.md) |
| Which literal and operator forms are supported? | [Literals and operators](literals-and-operators.md) |
| Which control-flow facts does type checking validate? | [generated unstable-alpha slice](generated/unstable-alpha-slice.md) and [type-checker internals](../compiler/type-checker.md) |
| Which expressions execute on a target? | [Codegen and backends](../compiler/codegen.md) and [x86 backend internals](../compiler/x86-backend.md) |
| Which diagnostic explains a rejection? | [Diagnostics](../DIAGNOSTICS.md) and [generated error index](../diagnostics/generated/error-index.md) |

Parser acceptance is never enough by itself. A grammar-valid expression can
fail at type checking, and a type-checked expression can fail at backend
lowering with a source-spanned diagnostic.

## Blocks And Statements

A block is a braced statement list:

```lanius
{
    let value: i32 = 1;
    return value;
}
```

The grammar accepts these statement families:

| Statement | Example |
| --- | --- |
| Local declaration | `let value: i32 = 1;` |
| Return | `return value;` or `return;` |
| Conditional | `if (value > 0) { return value; } else { return 0; }` |
| While loop | `while (value < limit) { value += 1; }` |
| For loop | `for item in values { total += item; }` |
| Break | `break;` |
| Continue | `continue;` |
| Nested block | `{ let local: i32 = 1; }` |
| Expression statement | `call(value);` |

The parser records statement, block, nearest-control, nearest-loop, and
nearest-function HIR context rows. Type checking and backend lowering consume
those rows instead of rediscovering control-flow shape from source text.

## Returns

`return` exits the current function. A function with no return type can use
`return;`. A function with a return type must return a value of the declared
type along every accepted return path in the current bounded model.

```lanius
fn abs_i32(value: i32) -> i32 {
    if (value < 0) {
        return -value;
    } else {
        return value;
    }
}
```

The type checker has bounded return-convergence evidence for direct fallthrough
returns and direct `if`/`else` forms whose arms both return. It also has
bounded evidence for one nested direct `if`/`else` propagation step. Branch-only
nested returns outside that bounded form still fail closed rather than letting
the backend synthesize a zero or default return.

This is an important user-facing boundary: if the compiler cannot prove a
non-void function returns, the diagnostic should point at the function or the
construct that made convergence unprovable.

## Conditions

`if`, `while`, and `match` discriminants use expression records built by the
parser and validated by type checking or backend-specific rows. Boolean
conditions are the primary documented condition surface today.

```lanius
fn choose(flag: bool, left: i32, right: i32) -> i32 {
    if (flag) {
        return left;
    } else {
        return right;
    }
}
```

The x86 backend has bounded execution evidence for scalar boolean operators in
branches and bool-returning helper calls used as branch conditions. Aggregate
comparisons and broader condition forms are type-checker/backend questions, not
syntax-only guarantees.

## If And Else

`if` conditions are parenthesized and `if` bodies use the dedicated brace tokens
recorded by the parser. `else` is optional in the grammar:

```lanius
if (value > limit) {
    return limit;
}
```

For non-void return convergence, an `if` without `else` usually cannot prove
that every path returns unless there is another accepted return path after it.
Use an explicit `else` when both branches return:

```lanius
if (value > limit) {
    return limit;
} else {
    return value;
}
```

The current docs do not claim a broad expression-valued `if`. Treat `if` as a
statement form unless a generated slice row names a stronger behavior for a
specific construct.

## While Loops

`while` repeats a block while its condition is true:

```lanius
fn count_to(limit: i32) -> i32 {
    let value: i32 = 0;
    while (value < limit) {
        value += 1;
    }
    return value;
}
```

The type checker validates loop control using parser-owned nearest-loop HIR
context rows. `break` and `continue` inside nested blocks can type-check
because the parser records the enclosing loop relation directly.

The x86 backend has bounded execution evidence for while loops, nested while
loops with scalar local mutation, break/continue, and loop-contained direct
helper calls. Unsupported loop/value shapes should fail closed at the loop,
call, index, or expression node instead of being silently skipped.

## Break And Continue

`break;` exits the nearest enclosing loop. `continue;` advances the nearest
enclosing loop. They are only valid when the parser/type-checker context can
prove an enclosing loop.

```lanius
while (value < limit) {
    if (value == stop) {
        break;
    } else {
        value += 1;
        continue;
    }
}
```

The current evidence is about loop control statements, not labeled breaks,
value-carrying breaks, or loop expressions.

## For Loops And Ranges

The grammar accepts `for name in iterable { ... }` where the iterable is a path
or a numeric range expression:

```lanius
for item in values {
    total += item;
}

for index in 0..10 {
    total += index;
}

for index in 0..=10 {
    total += index;
}
```

The backend support surface is narrower than the grammar. The x86 backend has
bounded execution evidence for array `for` loops with `break` and `continue`.
It also has a fail-closed source-pack diagnostic for scalar `for` iterables
until iterable lowering supports that shape.

Do not treat every parsed range form as executable on every target. Range
syntax, range stdlib structs, and backend loop lowering are separate surfaces.

## Match Expressions

`match` is a primary expression form:

```lanius
fn unwrap_or(value: Option<i32>, fallback: i32) -> i32 {
    return match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
}
```

The parser records match arms, patterns, and enum payload context. The type
checker has bounded evidence for generic enum match payload substitution,
including selected two-slot generic payload cases.

Backend support is still bounded. A match expression can be type-correct while
some enum or aggregate payload lowering remains outside the target backend's
executable slice. Unsupported target shapes must fail closed with a diagnostic
that points at the match, constructor, payload, or related expression.

## Assignment

Assignment is an expression form in the grammar:

```lanius
value = next;
value += 1;
value <<= amount;
```

Compound assignments currently parsed by the grammar are:

| Family | Operators |
| --- | --- |
| Arithmetic | `+=`, `-=`, `*=`, `/=`, `%=` |
| Bitwise | `^=`, `&=`, `|=` |
| Shift | `<<=`, `>>=` |

Type checking validates that the target and value make sense for the operator
and target expression. The x86 backend has bounded execution evidence for
selected scalar and indexed assignment cases, including unsigned indexed
compound division and modulo.

The language has no documented `mut` keyword today. Assignability is governed
by current type-checker and backend records, not by a source-level mutability
marker.

## Operators

The parser groups binary operators from lowest precedence to highest
precedence:

| Precedence | Operators |
| --- | --- |
| Logical or | `||` |
| Logical and | `&&` |
| Bitwise or | `|` |
| Bitwise xor | `^` |
| Bitwise and | `&` |
| Equality | `==`, `!=` |
| Comparison | `<`, `>`, `<=`, `>=` |
| Shift | `<<`, `>>` |
| Additive | `+`, `-` |
| Multiplicative | `*`, `/`, `%` |

The documented unary operators are `+`, `-`, and `!`:

```lanius
let positive: i32 = +value;
let negative: i32 = -value;
let inverted: bool = !flag;
```

The x86 backend has bounded execution evidence for selected scalar division,
modulo, bitwise, shift, unsigned right-shift, boolean, comparison, and branch
uses. That evidence does not imply every primitive type supports every
operator, or that every expression nesting shape is executable.

`++` and `--` are lexer tokens, but increment/decrement expressions are not a
documented source surface today. Backend rows that encounter unsupported
postfix or prefix expression forms must fail closed instead of treating them as
no-ops.

## Division, Modulo, And Checked Failure

Division and modulo have explicit backend failure behavior. The x86 backend
fails closed for statically known zero divisors before native code can fault:

```lanius
fn invalid(value: i32) -> i32 {
    return value / 0;
}
```

Dynamic divisors have bounded x86 evidence through generated runtime trap
checks when the divisor is not statically known to be zero. Signed `-1`
overflow paths also have bounded runtime-overflow-check evidence.

These rows are backend behavior, not a general constant-evaluation language
spec. Check the generated slice before assuming the same behavior for every
target, primitive type, or expression form.

## Calls

Call expressions use postfix call syntax:

```lanius
let result: i32 = helper(value, 4);
```

The type checker resolves direct calls, generic calls, source-pack calls,
qualified calls, intrinsic calls, and selected method calls through parser and
type-check records. Current call support is bounded by the generated slice,
including direct generic substitution width, method receiver metadata, and
source-pack import evidence.

The x86 backend has bounded execution evidence for direct scalar calls,
recursive scalar calls, four-argument calls, imported source-pack helper calls,
loop-contained calls, and direct self receiver method calls. Calls outside the
current ABI or lowering rows should fail closed at the call or parameter token.

## Indexing And Member Access

Indexing and member access are postfix expression forms:

```lanius
let first: i32 = values[0];
let sum: i32 = pair.left + pair.right;
```

The parser records index spans, member spans, array element rows, and struct
field rows. Type checking connects those rows to array, struct, enum, and
generic instance metadata.

The x86 backend has bounded evidence for selected local-array reads, indexed
assignments, and static out-of-bounds diagnostics. Unsized slice parameter
indexing currently fails closed before native memory planning can continue
without a useful source span. Nested aggregate member receivers and member
reads from aggregate return temporaries also fail closed until backend lowering
has the needed aggregate path and temporary materialization rows.

## Literals

The parser accepts integer, float, string, char, and boolean literal forms.
Current target execution evidence is narrower:

| Literal family | Current boundary |
| --- | --- |
| Integer | Strongest current scalar execution evidence. |
| Boolean | Used in scalar conditions and selected boolean operations. |
| Float | Type names and constants exist, but x86 currently fails closed for unsupported float literal lowering. |
| String | Parser support exists, but executable string literal lowering is not broadly documented. |
| Char | Type names and stdlib helpers exist, but executable char literal lowering is not broadly documented. |

This distinction matters for docs quality: a literal being parsed is not the
same as a literal being executable on every target.

## Short-Circuit And Evaluation Boundaries

The grammar has logical `&&` and `||` operator groups. The current generated
slice has bounded x86 evidence for scalar boolean operators in branches, but it
also publishes bounded backend contracts around control-flow bridging and
lowering. Do not claim broad short-circuit evaluation behavior without a row
that proves the specific source shape.

If a call, trap, index, division, or aggregate operation appears in a logical
expression shape that the current backend cannot lower safely, the backend
should fail closed with a source-spanned diagnostic rather than relying on
source-text recognition or accidental evaluation order.

## Backend Boundary

`x86_64` is the primary executable target today. Its expression/control-flow
slice includes bounded evidence for:

- scalar boolean operators in branches
- scalar division, modulo, bitwise, shift, and unsigned right-shift cases
- bool-returning helper calls in branch conditions
- direct scalar, recursive, source-pack, and selected method calls
- while loops, nested while loops, break, and continue
- array `for` loops with break/continue
- indexed assignments and selected local-array reads
- static out-of-bounds and zero-divisor diagnostics

The same syntax may fail on `wasm`, which currently accepts the target selector
but fails closed at the backend boundary.

## Update Rule

Update this chapter when grammar, parser HIR, type checking, generated slice
rows, diagnostics, or backend lowering changes what a user can reasonably
believe about statements, expressions, operators, loops, returns, calls,
matches, indexes, literals, or source-spanned control-flow failures.

If an implementation change adds an internal bounded loop or row-capacity
constraint, update the compiler docs and generated slice first. This page
should describe user-facing behavior, not internal scratch limits.
