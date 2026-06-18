# Lanius Literals And Operators

This chapter describes the literal and operator surface in the current
`unstable-alpha` language slice. It sits between
[Lexical structure](lexical-structure.md), which describes source token
spelling, and [Expressions and control flow](expressions-and-control-flow.md),
which describes expression behavior in statements, calls, loops, matches, and
backend lowering.

Literal and operator support is intentionally documented in layers:

- the lexer recognizes token spellings
- the parser groups tokens into expression records
- type checking validates the operand and result types
- a selected backend either lowers the expression or fails closed with a
  source-spanned diagnostic

Do not treat a token or grammar production as a complete execution guarantee.
For row-level support claims, use the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md).

## Source Of Truth

Use these layers together:

| Question | Primary source |
| --- | --- |
| Which literal and operator tokens exist? | [Lexical structure](lexical-structure.md) |
| How are operator expressions grouped? | [Syntax reference](syntax.md) and [grammar/lanius.bnf](../../grammar/lanius.bnf) |
| Which operand and result types are valid? | [Types and values](types-and-values.md), [Traits and impls](traits-and-impls.md), and generated slice rows |
| Which expression forms execute on a target? | [Expressions and control flow](expressions-and-control-flow.md), [Codegen and backends](../compiler/codegen.md), and generated slice codegen rows |
| Which diagnostic explains a rejected literal or operator? | [Diagnostics](../DIAGNOSTICS.md) and [generated error index](../diagnostics/generated/error-index.md) |

If a maintained prose page and the generated slice disagree, trust the
generated slice and its named tests first, then update the prose.

## Literal Families

The current lexer and parser recognize these literal families:

| Literal family | Example spellings | Current support boundary |
| --- | --- | --- |
| Integer | `0`, `42`, `0xff`, `0b1010`, `1_000` | Strongest current scalar execution evidence, especially on `x86_64`. Type checking still decides the expected type and target-specific lowering still applies. |
| Boolean | `true`, `false` | Used by conditions, match patterns, and selected scalar boolean operators. |
| Float | `1.0`, `.5`, `1e3` | Token and type-name support exist, but x86 lowering currently fails closed for unsupported float literal execution shapes. |
| String | `"hello"` | Token recognition exists. Broad executable string storage, ABI, and runtime lowering are not documented as complete. |
| Char | `'x'`, `'\n'` | Token recognition and the `char` type name exist. Broad executable char lowering is not documented as complete. |
| Array | `[1, 2, 3]` | Array literal behavior belongs to [Aggregates and indexing](aggregates-and-indexing.md). |

Spelling recognition and execution support are different claims. For example,
the lexer can recognize a float literal while the selected backend still rejects
that literal with an unsupported-feature diagnostic.

## Integer Literals

Integer literals include decimal, hexadecimal, binary, and octal spelling
families, with underscores allowed inside digit runs:

```lanius
let decimal: i32 = 42;
let grouped: i32 = 1_000;
let hex: i32 = 0xff;
let binary: i32 = 0b1010;
let octal: i32 = 0o755;
```

The literal token does not by itself choose the final value type. Type checking
uses the surrounding expectation, annotation, or declaration to decide which
integer type the literal must fit.

The strongest executable evidence today is scalar and target-bounded. Integer
literal support does not imply broad constant evaluation, target-independent
overflow behavior, or support for every integer operation in every expression
nesting shape.

## Boolean Literals

Boolean literals are `true` and `false`:

```lanius
let enabled: bool = true;

if (enabled) {
    return 1;
} else {
    return 0;
}
```

Boolean literals are ordinary expression leaves. They are also accepted in
selected pattern positions, such as match arms. The x86 backend has bounded
evidence for scalar boolean operators in branches, but that is not a blanket
claim for every boolean expression shape or every target.

## Float, String, And Char Literals

Float, string, and char literals are part of the source language frontier, but
their executable support is narrower than their token support:

```lanius
let ratio: f32 = 1.0;
let message: str = "hello";
let initial: char = 'x';
```

The primitive names `f32`, `f64`, `str`, and `char` exist in the type checker.
That does not mean every literal of those families can be lowered by every
backend. Current x86 codegen rows include fail-closed evidence for unsupported
float, string, and char literal lowering cases.

When these literals are rejected, the diagnostic should point at the literal or
the expression that forced unsupported lowering, not at a later backend artifact.

## Operator Precedence

Binary operators are grouped from lowest precedence to highest precedence:

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

Parentheses override the default grouping:

```lanius
let grouped: i32 = (left + right) * scale;
```

Parser grouping is not the same as target support. A parsed operator expression
can still fail during type checking or backend lowering.

## Unary Operators

The documented unary operators are `+`, `-`, and `!`:

```lanius
let same: i32 = +value;
let negated: i32 = -value;
let inverted: bool = !flag;
```

The lexer has token spellings for `++` and `--`, but increment and decrement
expressions are not documented source forms in the current slice. Prefix or
postfix shapes outside the supported unary/postfix rows should fail closed
instead of being treated as no-ops or rewritten silently.

## Arithmetic And Bitwise Operators

The current arithmetic, bitwise, and shift spellings are:

| Family | Operators |
| --- | --- |
| Arithmetic | `+`, `-`, `*`, `/`, `%` |
| Bitwise | `&`, `|`, `^` |
| Shift | `<<`, `>>` |

```lanius
let sum: i32 = left + right;
let masked: u32 = value & 0xff;
let shifted: u32 = value >> amount;
```

The x86 backend has bounded evidence for selected scalar division, modulo,
bitwise, shift, and unsigned right-shift cases. That evidence is deliberately
narrow: it does not prove every primitive type, every operand width, every
target, or every expression nesting shape.

## Division, Modulo, And Checked Failure

Division and modulo have explicit fail-closed behavior on the current x86
backend. A statically known zero divisor is rejected before native code can
fault:

```lanius
fn invalid(value: i32) -> i32 {
    return value / 0;
}
```

Dynamic divisors have bounded evidence through generated runtime trap checks
when the divisor is not statically known to be zero. Signed overflow cases that
need runtime checks are also target-specific backend contracts, not a general
language-wide constant-evaluation model.

Diagnostics for these cases should identify the operator expression or divisor
that makes the operation unsupported or unsafe.

## Assignment Operators

Assignment writes a value to an assignable target:

```lanius
value = next;
```

Compound assignment combines an operation with assignment:

| Family | Operators |
| --- | --- |
| Arithmetic | `+=`, `-=`, `*=`, `/=`, `%=` |
| Bitwise | `^=`, `&=`, `|=` |
| Shift | `<<=`, `>>=` |

```lanius
value += 1;
value <<= amount;
```

The language has no documented `mut` keyword today. Assignability is governed
by parser records, type checking, and backend lowering for the target
expression. The x86 backend has bounded evidence for selected scalar and
indexed assignment cases, including unsigned indexed compound division and
modulo.

## Logical Operators And Short-Circuit Boundaries

Logical operators are `&&` and `||`:

```lanius
if (ready && enabled) {
    return 1;
}
```

The generated slice has bounded x86 evidence for scalar boolean operators in
branches. Do not infer broad short-circuit execution for every effectful right
hand side. Calls, trapping arithmetic, dynamic indexing, aggregate operations,
and other backend-sensitive expressions need explicit lowering evidence for the
source shape.

If the backend cannot prove and lower the expression safely, it should fail
closed with a source-spanned diagnostic instead of relying on source-text
special cases.

## Diagnostics

Common rejection paths include:

| Case | Expected diagnostic surface |
| --- | --- |
| Unsupported operator syntax | Parser or unsupported-feature diagnostic at the operator or expression span. |
| Operand type mismatch | Type diagnostic at the operand, operator, or assignment span that made the expression invalid. |
| Unsupported literal lowering | Backend unsupported-feature diagnostic at the literal expression. |
| Zero divisor | Backend diagnostic at the division or modulo expression, preferably labeling the divisor. |
| Unsupported prefix or postfix form | Backend unsupported-feature diagnostic at the unsupported expression form. |
| Unsupported short-circuit operand shape | Backend unsupported-feature diagnostic at the logical expression or unsupported operand. |

The maintained diagnostic guide is [Diagnostics](../DIAGNOSTICS.md). The
generated code index is
[diagnostics/generated/error-index.md](../diagnostics/generated/error-index.md).

## What Not To Infer

These are not current support claims:

- every parsed float, string, or char literal executes on every target
- every primitive type supports every operator
- integer literal support means broad compile-time constant evaluation
- `++` and `--` are source-level increment or decrement expressions
- `&&` and `||` have broad short-circuit support for every effectful right hand
  side
- type-checked operators are executable on `wasm`

Use generated rows and backend tests before widening any of these claims.

## Updating This Chapter

When literal or operator support changes:

1. Update lexer/parser/type-checker/backend tests for the owned behavior.
2. Update `docs/language_slice_unstable_alpha.tsv` with the exact support row
   or fail-closed row.
3. Regenerate `docs/language/generated/unstable-alpha-slice.md`.
4. Update this page and adjacent language-reference pages.
5. Run `tools/docs_check.py`.
