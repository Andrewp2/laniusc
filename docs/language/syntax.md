# Lanius Syntax Reference

This chapter describes the syntax accepted by the current `unstable-alpha`
grammar. It is the language-facing companion to
[grammar/lanius.bnf](../../grammar/lanius.bnf), which remains the exact parser
source of truth.
Use [Lexical structure](lexical-structure.md) for the source tokens, comments,
keywords, literals, punctuation, and lexer/parser retag boundaries that feed
the grammar.
Use [Items and declarations](items-and-declarations.md) for the semantic
companion to top-level declarations: module metadata, imports, functions,
externs, constants, aliases, structs, enums, traits, impls, visibility, and
namespace boundaries.
Use [Functions and calls](functions-and-calls.md) for the semantic and backend
companion to function signatures, parameters, arguments, direct calls, qualified
calls, generic calls, constructor calls, method calls, extern declarations, and
call ABI boundaries.
Use [Name resolution](name-resolution.md) for the semantic companion to names,
paths, imports, qualified paths, local bindings, generic parameters, enum
variants, fields, and methods.
Use [Generics and bounds](generics-and-bounds.md) for the semantic companion to
generic parameter lists, type arguments, const parameters, inline bounds, and
where clauses.
Use [Traits and impls](traits-and-impls.md) for trait declarations, impl
blocks, method signatures, receiver forms, trait impl contracts, and dispatch
boundaries.
Use [Types and values](types-and-values.md) for the semantic companion to this
chapter: primitive names, aliases, constants, generics, aggregates, traits,
arrays, runtime-backed declarations, and backend boundaries.
Use [Aggregates and indexing](aggregates-and-indexing.md) for the semantic
companion to struct literals, enum constructors, array literals, field access,
indexing, and aggregate backend boundaries.
Use [Literals and operators](literals-and-operators.md) for the semantic and
backend support boundaries for literal families, operator precedence, unary,
binary, assignment, division, modulo, and logical operators.
Use [Expressions and control flow](expressions-and-control-flow.md) for the
behavior-facing companion to the statement, expression, operator, loop, match,
call, indexing, and literal syntax in this chapter.
Use [Patterns and matching](patterns-and-matching.md) for match arm syntax,
path patterns, tuple-payload patterns, literal patterns, binding scope, and
exhaustiveness/backend boundaries.

Syntax acceptance is not the same as full semantic or backend support. When a
feature needs a support claim, use the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md), the
[diagnostic index](../diagnostics/generated/error-index.md), or the relevant
compiler/backend chapter.

## Source Files

A source file is a sequence of items. Empty files are grammar-valid, though
they usually are not useful as compile entries.

```text
item*
```

Source files use `.lani` paths in normal tooling. Package and source-root
loading add module/file mapping rules on top of the grammar; see
[Language slice and versioning policy](../LANGUAGE_SLICE.md) and
[Package metadata and lockfiles](../compiler/package-metadata.md).

## Items

The current grammar accepts these top-level item families:

| Item | Shape |
| --- | --- |
| Function | `fn name(params) -> Type { statements }` |
| Extern function | `extern "abi" fn name(params) -> Type;` |
| Import | `import module::path;` |
| Module declaration | `module module::path;` |
| Type alias | `type Name<T> = Type;` |
| Constant | `const NAME: Type = expression;` |
| Struct | `struct Name<T> { fields }` |
| Enum | `enum Name<T> { variants }` |
| Trait | `trait Name<T> { methods }` |
| Impl | `impl Type { methods }` or `impl Trait for Type { methods }` |

Most item families also accept a leading `pub`. Public items become visible to
cross-module consumers when the source-root or package boundary exposes the
declaring module. Private items remain local to their module.

```lanius
module app::math;

pub const FEE: i32 = 4;

pub fn add_fee(value: i32) -> i32 {
    return value + FEE;
}
```

## Modules And Imports

Module identities and imports use `::`-separated path segments:

```lanius
module app::main;

import core::option;
import core::result;
```

The parser grammar also has a quoted import form, but source-root and package
loading currently reject quoted imports before they can become reliable module
metadata. For current code, use module-path imports.

Import paths are explicit. The current language surface does not document glob
imports, aliases, dotted paths, package-name separators, or path separators as
supported import syntax.
Use [Modules, imports, and packages](modules-and-imports.md) for source-root,
stdlib-root, visibility, package manifest, and lockfile replay rules.
For declaration semantics and current support boundaries, use
[Items and declarations](items-and-declarations.md).

## Functions

Function parameters are comma-separated. Return types are optional in the
grammar; when present, they follow `->`.

```lanius
fn identity(value: i32) -> i32 {
    return value;
}

fn no_value_return() {
    return;
}
```

Parameters can be ordinary named parameters, `self`, `&self`, or typed `self`
parameters in grammar positions that accept them:

```lanius
fn method_like(self: Widget) -> i32 {
    return self.value;
}
```

Use the generated slice before treating a particular `self` form as fully
supported in traits, impls, type checking, or backend lowering.

## Extern Functions

Extern functions have a semicolon instead of a body. An ABI string is optional
in the grammar.

```lanius
extern "lanius_panic" fn panic();
extern fn host_value() -> i32;
```

Extern declarations can type-check as source-level contracts without making the
host service executable. Runtime-bound stdlib APIs document that distinction in
[Standard library](../../stdlib/README.md).

## Types

The current type syntax includes:

| Type form | Example |
| --- | --- |
| Path type | `i32`, `core::option::Option` |
| Generic type arguments | `Option<i32>`, `Result<i32, bool>` |
| Array type | `[i32; 4]` |
| Slice type | `[i32]` |
| Reference type | `&i32` |

Array lengths can be integer literals or identifiers:

```lanius
type FourI32 = [i32; 4];
type Buffer = [u8; BUFFER_LEN];
```

The grammar accepts nested generic arguments and qualified type paths. Semantic
support for generic instantiation, trait bounds, arrays, slices, references,
and backend lowering is row-based in [Types and values](types-and-values.md)
and the generated slice.

## Generics And Bounds

Functions, type aliases, structs, enums, traits, and impls can carry generic
parameters. Generic parameters may have bounds, and const generic parameters
use `const NAME: Type`.

```lanius
struct Pair<T> {
    left: T,
    right: T,
}

fn keep<T>(value: T) -> T {
    return value;
}

struct Wide<const N: u32> {
    value: [i32; N],
}
```

Where clauses use comma-separated predicates:

```lanius
fn choose<T>(left: T, right: T) -> T where T: core::cmp::Ord<T> {
    return left;
}
```

Type bounds use `+` for multiple bounds and may include reference-shaped bound
types. The current type checker has explicit fail-closed diagnostics for
unsupported or unknown bound forms.

## Structs And Struct Literals

Struct declarations use named fields:

```lanius
struct Pair {
    left: i32,
    right: i32,
}
```

Struct literals use field names and allow a trailing comma:

```lanius
let value: Pair = Pair { left: 1, right: 2, };
```

Member access uses dot syntax:

```lanius
let total: i32 = value.left + value.right;
```

## Enums And Matches

Enum variants can be unit variants or tuple-payload variants:

```lanius
enum Option<T> {
    None,
    Some(T),
}
```

`match` is an expression form:

```lanius
let value: i32 = match (option) {
    Option::Some(inner) -> inner,
    Option::None -> 0,
};
```

Patterns currently include path patterns, tuple-like payload patterns, integer
literals, `true`, and `false`. Exhaustiveness, enum payload typing, and backend
execution are semantic/backend questions, not grammar-only claims.

## Traits And Impls

Trait declarations contain semicolon-terminated method signatures:

```lanius
trait Eq<T> {
    pub fn eq(left: T, right: T) -> bool;
    pub fn ne(left: T, right: T) -> bool;
}
```

Inherent impls and trait impls contain method bodies:

```lanius
impl Pair {
    pub fn sum(self: Pair) -> i32 {
        return self.left + self.right;
    }
}

impl Eq<i32> for i32 {
    pub fn eq(left: i32, right: i32) -> bool {
        return left == right;
    }
}
```

The syntax exists to let the compiler record and check bounded trait, impl, and
method cases. Dot-call dispatch, method-level where clauses, and some trait
lookup forms are intentionally fail-closed in the current slice.

## Blocks And Statements

Blocks contain zero or more statements:

```lanius
{
    let value: i32 = 1;
    return value;
}
```

The grammar accepts these statement families:

| Statement | Shape |
| --- | --- |
| Let | `let name: Type = expression;` |
| Return | `return;` or `return expression;` |
| If | `if (condition) { statements } else { statements }` |
| While | `while (condition) { statements }` |
| For | `for name in iterable { statements }` |
| Break | `break;` |
| Continue | `continue;` |
| Block | `{ statements }` |
| Expression | `expression;` |

Let type annotations and initializers are individually optional in the grammar:

```lanius
let named: i32;
let inferred = 1;
let empty;
```

Whether a declaration without a type, initializer, or later assignment is
semantically useful depends on the current type-checker rules.

## For Ranges

`for` iterables can be paths or numeric range expressions:

```lanius
for item in range {
    total += item;
}

for index in 0..10 {
    total += index;
}

for index in 0..=10 {
    total += index;
}

for index in ..10 {
    total += index;
}
```

The grammar also accepts unbounded range ends in the range positions it defines.
Execution evidence for range forms belongs to the generated slice and target
backend tests. See
[Expressions and control flow](expressions-and-control-flow.md) for the
user-facing range and loop boundary.

## Expressions

Expressions are built from assignment, binary operators, unary operators,
postfix operations, and primary expressions.

Assignment is right-associative in the grammar:

```lanius
target = source;
target += delta;
target <<= amount;
```

Compound assignment operators currently parsed by the grammar are `+=`, `-=`,
`*=`, `/=`, `%=`, `^=`, `<<=`, `>>=`, `&=`, and `|=`.

## Operator Precedence

The grammar groups binary expressions in this order, from lowest precedence to
highest precedence:

- Logical or: `||`
- Logical and: `&&`
- Bitwise or: `|`
- Bitwise xor: `^`
- Bitwise and: `&`
- Equality: `==`, `!=`
- Comparison: `<`, `>`, `<=`, `>=`
- Shift: `<<`, `>>`
- Additive: `+`, `-`
- Multiplicative: `*`, `/`, `%`

The parser grammar is right-recursive for binary expression tails. Downstream
HIR and type-checker records own the behavior-facing operator contracts.

Unary operators bind tighter than binary operators. The lexer has `++` and
`--` token kinds, but this grammar does not document increment or decrement
expressions. The documented unary operators are `+`, `-`, and `!`.

Documented unary expression forms:

```lanius
let a: i32 = +value;
let b: i32 = -value;
let c: bool = !flag;
```

## Postfix Operations

Postfix operations chain after a primary expression:

```lanius
call(value, other)
array[index]
value.field
```

The grammar allows repeated postfix chaining:

```lanius
items[index].field.helper(arg)
```

Whether a particular chain type-checks depends on the current type, method,
field, call, and index records. See
[Expressions and control flow](expressions-and-control-flow.md) for the
current behavior-facing call, index, and member-access boundary.

## Primary Expressions

Primary expressions include:

| Expression | Example |
| --- | --- |
| Array literal | `[1, 2, 3]` |
| Grouped expression | `(value + 1)` |
| Path expression | `core::i32::MAX` |
| Struct literal | `Pair { left: 1, right: 2, }` |
| `self` | `self` |
| Integer literal | `123` |
| Float literal | `1.5` |
| String literal | `"text"` |
| Char literal | `'x'` |
| Boolean literal | `true`, `false` |
| Match expression | `match (value) { ... }` |

Array literals, struct literals, argument lists, pattern lists, enum payloads,
generic argument lists, generic parameter lists, and struct fields allow
trailing commas in the grammar positions that define comma tails.

## Comments And Whitespace

Line comments and block comments are lexer tokens that are skipped before the
parser grammar consumes kept tokens. Whitespace separates tokens where needed
and is otherwise not semantically significant.

The formatter owns the current normalized whitespace contract. It preserves
non-whitespace token text and token order while rewriting layout.

## Unsupported Syntax Boundaries

If a syntax form is accepted by the grammar but unsupported by a later phase,
the compiler should fail closed with a stable diagnostic at the closest useful
source span. The maintained diagnostics entry points are:

- [Diagnostics](../DIAGNOSTICS.md)
- [generated diagnostic code index](../diagnostics/generated/error-index.md)
- [Compiler diagnostics internals](../compiler/diagnostics.md)

Do not treat parser acceptance as permission to add compatibility shims,
fallback parsing, CPU semantic rewrites, or backend substitutes. A supported
source form needs row-level evidence in the language slice and focused tests at
the owning phase.

## Update Rule

Update this chapter when `grammar/lanius.bnf` changes in a way that changes
user-visible syntax families, examples, operator grouping, item forms, or
unsupported syntax boundaries. Update the generated slice first when the change
is semantic, diagnostic, stdlib, package, target, or backend support rather
than pure syntax.
