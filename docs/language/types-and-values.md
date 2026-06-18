# Lanius Types And Values

This chapter describes the current `unstable-alpha` type and value model from
the user side. It is the semantic companion to [Syntax reference](syntax.md):
syntax says which source shapes the parser accepts, while this page says what
those shapes mean when the current type checker, standard library seeds, and
backend evidence are considered.
Use [Expressions and control flow](expressions-and-control-flow.md) for
statement behavior, operator boundaries, return convergence, loops, matches,
calls, indexing, literals, and target execution details.
Use [Functions and calls](functions-and-calls.md) for function signatures,
parameters, arguments, direct calls, qualified calls, generic calls,
constructor calls, method calls, extern/runtime calls, and call ABI boundaries.
Use [Name resolution](name-resolution.md) for type-position, value-position,
qualified-path, local, generic-parameter, import, and visibility lookup rules.
Use [Generics and bounds](generics-and-bounds.md) for generic parameters, type
arguments, const parameters, trait bounds, where clauses, generic calls, generic
enums, aliases, and method/impl support boundaries.
Use [Traits and impls](traits-and-impls.md) for trait declarations, inherent
impls, trait impl contracts, method lookup, visibility matching, and dispatch
boundaries.
Use [Aggregates and indexing](aggregates-and-indexing.md) for structs, enums,
arrays, slices, literals, constructors, member access, indexing, and aggregate
backend boundaries.
Use [Literals and operators](literals-and-operators.md) for literal families,
operator precedence, unary, binary, assignment, division, modulo, logical
operators, and their type/backend support boundaries.

The current compiler is still bounded. A type form can be grammar-valid without
being accepted by the type checker, and a type-checked expression can still be
outside a backend's executable slice. For exact support claims, use the
generated [unstable-alpha slice reference](generated/unstable-alpha-slice.md)
and the generated [standard library reference](../stdlib/generated/reference.md).

## Source Of Truth

Use these layers together:

| Question | Primary source |
| --- | --- |
| What tokens and syntax parse? | [Lexical structure](lexical-structure.md) and [Syntax reference](syntax.md) |
| What semantic rows are supported or fail closed? | [generated unstable-alpha slice](generated/unstable-alpha-slice.md) |
| How do names and paths resolve? | [Name resolution](name-resolution.md) |
| How do functions and calls work? | [Functions and calls](functions-and-calls.md) |
| How do generics and bounds work? | [Generics and bounds](generics-and-bounds.md) |
| How do traits and impls work? | [Traits and impls](traits-and-impls.md) |
| How do aggregate values and indexing work? | [Aggregates and indexing](aggregates-and-indexing.md) |
| How do literals and operators work? | [Literals and operators](literals-and-operators.md) |
| Which builtin names exist in the compiler? | [Type checker internals](../compiler/type-checker.md) and `params.rs` |
| Which stdlib declarations exist? | [generated stdlib reference](../stdlib/generated/reference.md) |
| Which target executes a shape? | [Codegen and backends](../compiler/codegen.md), [x86 backend](../compiler/x86-backend.md), and generated slice codegen rows |
| Which error explains a rejection? | [Diagnostics](../DIAGNOSTICS.md) and [generated error index](../diagnostics/generated/error-index.md) |

If a maintained prose page and a generated reference disagree, trust the
generated reference and its named tests first, then update the prose.

## Namespaces

Lanius distinguishes declarations by the context that asks for them. A path in
a type position resolves to a type declaration, primitive type, generic
parameter, or visible type alias. A path in a value position resolves to a
function, extern function, constant, local, enum variant, or other visible value
declaration supported by the current slice.

```lanius
module app::types;

pub type Count = i32;
pub const LIMIT: Count = 4;

pub fn add(value: Count) -> Count {
    return value + LIMIT;
}
```

Module visibility applies before type or value use. A private declaration can
be valid in its own module while remaining invisible to importing modules. See
[Modules, imports, and packages](modules-and-imports.md) for source-root,
stdlib-root, package, and lockfile loading rules.

## Primitive Types

The type checker materializes builtin language declarations for these primitive
type spellings:

| Family | Names |
| --- | --- |
| Boolean | `bool` |
| Signed integers | `i8`, `i16`, `i32`, `i64`, `isize` |
| Unsigned integers | `u8`, `u16`, `u32`, `u64`, `usize` |
| Floating point | `f32`, `f64` |
| Text scalars | `char`, `str` |

Those declarations make the names available to type checking. They do not, by
themselves, mean every operator, literal form, ABI shape, stdlib helper, or
backend lowering for every primitive is complete.

The strongest executable evidence today is narrower than the primitive name
table. The x86 backend has bounded rows for selected integer, unsigned,
boolean, branch, call, array, and control-flow cases. Float, string, char, and
some aggregate or runtime-backed uses can parse or type-check in selected
contexts while still failing closed before executable output.

## Type Expressions

The current type syntax includes path types, generic arguments, arrays, slices,
and references:

```lanius
type Count = i32;
type MaybeCount = core::option::Option<Count>;
type FourCounts = [Count; 4];
type CountSlice = [Count];
type CountRef = &Count;
```

Path types can be qualified with `::`. Generic arguments are comma-separated
inside angle brackets. Array lengths can be integer literals or identifiers.

Semantic support is row-based:

- scalar path types and visible type aliases are type-checker concepts
- parser HIR records source-address type arguments, array elements, and path
  leaves
- nested generic instances have positive evidence in selected direct-call and
  return-consistency cases
- some nested generic parameter annotations, trait predicate shapes, and
  generic call widths are intentionally fail-closed until the GPU rows carry
  enough relation data

Do not infer a semantic limit from row-width constants. For example,
`TYPE_INSTANCE_ARG_REF_STRIDE = 4` is the number of stored words in one
type-instance argument-reference row. It is not a four-type-argument language
limit. The current direct generic call substitution window is separately
bounded by generated slice rows and diagnostics.

## Type Aliases

A type alias gives a name to another type expression:

```lanius
type Count = i32;
type UserId = Count;

fn same(left: UserId, right: i32) -> bool {
    return left == right;
}
```

The current type checker has semantic evidence for bounded scalar alias
normalization, including aliases used as generic call arguments and predicate
type arguments. The stdlib uses aliases heavily for runtime contract metadata,
for example `PathByte = u8` or capability aliases to `bool`.

Alias support is not an arbitrary compile-time rewrite engine. Recursive
aliases, deep generic alias chains, const-generic alias substitution, and broad
alias targets remain bounded or unsupported according to the generated slice
and compiler docs.

## Constants

Constants are typed item declarations:

```lanius
pub const LIMIT: i32 = 4;

fn apply(value: i32) -> i32 {
    return value + LIMIT;
}
```

Qualified constants can be imported from supplied modules:

```lanius
import core::i32;

fn max_value() -> i32 {
    return core::i32::MAX;
}
```

The current x86 slice includes bounded evidence for source-pack qualified
scalar constants in small arithmetic returns. Broader constant evaluation,
aggregate constants, and target-specific lowering should be checked against the
generated slice before being documented as executable.

## Locals And Assignment

`let` introduces a local binding. The grammar accepts optional annotations and
optional initializers, but the current semantic surface is strongest when the
source gives the type checker an explicit type or an initializer with clear
context.

```lanius
fn sum_pair(value: Pair) -> i32 {
    let total: i32 = value.left + value.right;
    return total;
}
```

Assignments and compound assignments are expression forms:

```lanius
fn add_until(limit: i32) -> i32 {
    let value: i32 = 0;
    while (value < limit) {
        value += 1;
    }
    return value;
}
```

The language has no documented `mut` keyword today. Whether a particular
assignment target is valid depends on the parser HIR target records, the
type-checker assignment rules, and the selected backend lowering.

## Struct Types

Struct declarations introduce nominal types with named fields:

```lanius
struct Pair {
    left: i32,
    right: i32,
}

fn sum(value: Pair) -> i32 {
    return value.left + value.right;
}
```

Field names are checked against the selected struct declaration, not against
same-spelled fields in unrelated structs. Duplicate field declarations in one
struct fail closed through GPU aggregate validation, while the same field name
can appear on different structs.

Struct literals are typed by context and by the resolved struct identity:

```lanius
let value: Pair = Pair { left: 1, right: 2, };
```

The x86 backend has bounded aggregate evidence, including selected struct
literals, member reads, aggregate copies, and fail-closed diagnostics for
nested aggregate member receivers or aggregate return temporaries that are not
yet lowered.

## Enum Types

Enum declarations introduce nominal variant sets. Variants can be unit variants
or tuple-payload variants:

```lanius
enum Option<T> {
    Some(T),
    None,
}
```

The stdlib currently seeds `core::option::Option<T>`,
`core::result::Result<T, E>`, and `core::ordering::Ordering`. Generic enum
constructors and match payload substitution have bounded type-checker evidence,
including selected two-slot generic payload cases.

```lanius
fn unwrap_or(value: Option<i32>, fallback: i32) -> i32 {
    return match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
}
```

Type-checker support and backend support are separate. A generic enum
constructor can type-check in a context where the backend still rejects a
multi-payload enum constructor or another unlowered enum shape with a
source-spanned diagnostic.

## Generic Types And Functions

Functions, type aliases, structs, enums, traits, and impls can have generic
parameters:

```lanius
struct Boxed<T> {
    value: T,
}

fn keep<T>(value: T) -> T {
    return value;
}
```

The type checker has bounded GPU evidence for direct generic calls, nested
generic helper forwarding, nested generic instance return consistency, nominal
instance return inference, repeated nominal generic slots, and scalar alias
normalization.

Current generic boundaries are explicit:

- direct generic calls beyond the current substitution window fail closed
- module-qualified generic calls have a matching fail-closed width boundary
- nested generic instance parameters such as `Maybe<Boxed<i32>>` are not
  accepted everywhere only because the outer nominal declaration matches
- uninferred generic return slots fail at the call token instead of publishing
  unresolved symbolic types

These are current implementation boundaries, not desired language philosophy.
When a bound is removed, the generated slice and this chapter should move
together.

## Const Generics

Const generic parameters are accepted in signatures and type declarations:

```lanius
fn first<const N: usize>(values: [i32; N]) -> i32 {
    return values[0];
}
```

The stdlib includes module-form examples such as `core::array_i32::first`.
Const generic support is still bounded. Trait predicates whose subject is a
const generic currently fail closed with a source-spanned diagnostic, and
const-generic alias substitution is not a broad supported surface.

## Traits, Bounds, And Impls

Trait declarations define required method signatures. Impl blocks validate
methods for a receiver or for a trait/receiver pair:

```lanius
trait Eq<T> {
    pub fn eq(left: T, right: T) -> bool;
    pub fn ne(left: T, right: T) -> bool;
}

impl Eq<i32> for i32 {
    pub fn eq(left: i32, right: i32) -> bool {
        return left == right;
    }

    pub fn ne(left: i32, right: i32) -> bool {
        return left != right;
    }
}
```

Where clauses and inline bounds create predicates that the type checker must
resolve:

```lanius
fn choose<T>(left: T, right: T) -> T where T: core::cmp::Ord<T> {
    return left;
}
```

The generated slice has bounded evidence for qualified trait bounds,
nonzero-generic-slot subjects, two generic bound argument slots, alias
normalization in predicate arguments, and private predicate argument rejection
across modules.

Trait support also has clear fail-closed boundaries. Method-level generics on
inherent methods, some trait impl argument shapes, duplicate trait impl methods,
visibility mismatches, overdeep inline bound chains, and trait impl methods
called as free functions are rejected until explicit dispatch and compact rows
exist.

## Methods And Receivers

Inherent impl methods can be resolved on matching concrete receivers:

```lanius
struct Pair {
    left: i32,
    right: i32,
}

impl Pair {
    pub fn sum(self: Pair) -> i32 {
        return self.left + self.right;
    }
}
```

The current type checker has evidence for direct self receiver methods,
same-name inherent methods across different concrete generic instances,
source-pack method resolution with two concrete receiver type arguments, and
methods on projected concrete generic struct fields.

Generic inherent method returns, nested receiver arguments, and method-level
generic dispatch are intentionally bounded. They should fail at the method
declaration, receiver, or call site named by the generated diagnostic row
rather than being guessed by backend lowering.

## Arrays, Slices, And Indexing

Fixed-size arrays carry an element type and a length:

```lanius
type FourI32 = [i32; 4];

fn first(values: FourI32) -> i32 {
    return values[0];
}
```

Slice types use `[T]` and reference types can point at values:

```lanius
type I32Slice = [i32];
type I32Ref = &i32;
```

The x86 backend has bounded evidence for selected local array reads, indexed
assignments, unsigned indexed compound division/modulo, array `for` loops, and
static out-of-bounds diagnostics. Unsized slice parameter indexing currently
fails closed before native memory planning can proceed without a source span.

## Runtime-Backed Types

Some stdlib modules expose type aliases, constants, extern declarations, and
contract helpers for runtime services:

```lanius
pub type StdioCapability = bool;
pub const STDIO_HAS_RUNTIME_BINDING: StdioCapability = false;
```

These declarations can be real source-level facts without being executable
host services. A module such as `std::io`, `std::fs`, `std::time`, or
`alloc::allocator` can be known to tooling, resolvable by the type checker, and
still fail closed if a program requires an unbound runtime service.

Use the runtime metadata commands for no-run discovery:

```bash
laniusc diagnostics runtime-apis
laniusc diagnostics runtime-services
laniusc diagnostics runtime-api std::io::print_i32
```

## Backend Boundary

Type checking is not target execution. The `x86_64` backend currently owns the
main executable slice, and `wasm` currently accepts the target selector but
fails closed at the backend boundary.

Examples of type/value shapes with x86 evidence include:

- scalar integer and boolean branches
- selected division, modulo, bitwise, shift, and unsigned right-shift cases
- direct scalar calls and selected source-pack calls
- direct self receiver methods
- source-pack qualified scalar constants in arithmetic
- while loops, break/continue, selected array loops, and indexed assignments

Examples of type/value shapes that deliberately fail closed today include:

- unsupported float/string/char literal lowering on x86
- multi-payload enum constructor lowering outside the current native slice
- unsized slice parameter indexing
- aggregate return temporaries and nested aggregate member receivers
- compile-time zero divisors and static out-of-bounds array indexes
- stdio runtime calls without a runtime binding

## Update Rule

Update this chapter when a type-checker, stdlib, generated-slice, or backend
change alters what a user can reasonably believe about types, values, aliases,
generics, traits, aggregates, arrays, constants, methods, or runtime-backed
declarations.

When a change is only a storage layout, row stride, dispatch shape, or scratch
capacity, update the compiler docs instead. Do not turn internal capacity facts
into language limits unless exhaustion produces a source-spanned diagnostic at
the construct a user wrote.
