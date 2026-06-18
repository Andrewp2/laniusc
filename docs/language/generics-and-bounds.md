# Generics And Bounds

This chapter describes the current `unstable-alpha` generic parameter, type
argument, const parameter, trait bound, and where-clause surface. It is the
user-facing reference for generic source shapes; use
[Types and values](types-and-values.md) for the broader type model,
[Name resolution](name-resolution.md) for lookup rules, and
[Items and declarations](items-and-declarations.md) for the item families that
can carry generic parameters. Use [Functions and calls](functions-and-calls.md)
for function signatures, generic calls, method calls, call inference, and call
ABI boundaries. Use [Traits and impls](traits-and-impls.md) for
the focused trait, impl, method contract, and dispatch-boundary reference.
Use [Aggregates and indexing](aggregates-and-indexing.md) for generic structs,
generic enums, array/slice type arguments, and aggregate backend boundaries.

The current compiler is bounded. A generic source shape can parse before every
type-checker, trait, method, enum, alias, or backend row needed for broad
support exists. For exact support claims, use the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md), especially
the `parser-hir`, `semantics`, `imports`, and `codegen` rows.

## Where Generics Appear

The grammar accepts generic parameters on these declarations:

| Declaration | Example |
| --- | --- |
| Function | `fn keep<T>(value: T) -> T { ... }` |
| Extern function | `extern fn host<T>(value: T);` |
| Type alias | `type Maybe<T> = core::option::Option<T>;` |
| Struct | `struct Boxed<T> { value: T }` |
| Enum | `enum Option<T> { Some(T), None }` |
| Trait | `trait Eq<T> { ... }` |
| Impl | `impl Eq<i32> for i32 { ... }` |

Generic arguments appear on type paths, value paths where the parser accepts
them, bound paths, enum constructors, and qualified paths. Syntax acceptance is
not enough by itself; the consuming context decides whether a generic name or
argument list can be resolved and checked.

## Type Parameters

A type parameter introduces a type name inside the declaration that owns it:

```lanius
struct Boxed<T> {
    value: T,
}

fn keep<T>(value: T) -> T {
    return value;
}
```

Type parameters can be used in parameter types, return types, field types,
variant payloads, type aliases, bounds, and where clauses supported by the
current slice. Duplicate generic parameter names should fail before inference,
substitution, or trait solving can choose an arbitrary binding.

Generic parameter scope is declaration-local. A `T` on one function is not the
same declaration as a `T` on another function unless a later use resolves
through an explicit generic argument or type relationship.

## Type Arguments And Instances

Generic type arguments instantiate nominal declarations:

```lanius
struct Pair<T> {
    left: T,
    right: T,
}

fn first(value: Pair<i32>) -> i32 {
    return value.left;
}
```

The current type checker has bounded evidence for:

- direct generic calls
- nested generic helper forwarding
- nested generic instance return consistency
- nominal instance return inference
- repeated nominal generic slot checking
- scalar alias normalization in generic call arguments
- selected generic enum constructors and match payload substitutions

Those are support rows, not broad monomorphization guarantees. Nested generic
instance parameters, unknown instance argument slots, uninferred direct generic
returns, and generic call argument-width boundaries can still fail closed with
source-spanned diagnostics.

## Generic Functions

A generic function can relate argument and return types through a type
parameter:

```lanius
fn identity<T>(value: T) -> T {
    return value;
}

fn main() {
    let value: i32 = identity(7);
    return value;
}
```

The direct-call rows substitute bounded argument and return information on the
GPU type-check path. They do not imply arbitrary overload resolution, method
dispatch, higher-rank behavior, or unlimited argument width.

When inference cannot determine a generic return slot from the current bounded
records, the call should fail at the call site instead of publishing an
unresolved symbolic type.

## Generic Structs And Enums

Generic structs are nominal types parameterized by type arguments:

```lanius
struct Boxed<T> {
    value: T,
}

fn unbox<T>(value: Boxed<T>) -> T {
    return value.value;
}
```

Generic enums can carry type-parameterized payloads:

```lanius
enum Option<T> {
    Some(T),
    None,
}

fn wrap<T>(value: T) -> Option<T> {
    return Some(value);
}
```

The current frontend/type-checker evidence includes contextual generic enum
constructors and selected generic enum match payload substitution. Backend
support is narrower. A generic enum can be valid source while a selected target
still rejects the constructor, payload, match, layout, or aggregate lowering
shape.

## Const Generic Parameters

Const generic parameters use `const NAME: Type`:

```lanius
struct Buffer<const N: usize> {
    values: [i32; N],
}
```

Today, const generic names are most relevant to array-length type expressions.
Do not infer broad const evaluation, const arithmetic, trait predicates over
const subjects, const-generic alias substitution, or backend lowering from the
syntax alone. The generated slice owns the current fail-closed rows for const
generic predicates and alias/lowering boundaries.

## Inline Bounds

A type parameter can carry inline bounds:

```lanius
fn keep<T: core::cmp::Eq<T> >(value: T) -> T {
    return value;
}
```

Multiple inline bounds use `+`:

```lanius
fn choose<T: core::cmp::Eq<T> + core::cmp::Ord<T> >(left: T, right: T) -> T {
    return left;
}
```

The grammar also accepts reference-shaped bound types. Semantic support is
bounded. Over-deep inline bound chains, unknown bound subjects, private
predicate argument leaks, and unsupported bound type shapes should fail closed
with diagnostics at the bound or predicate source span.

## Where Clauses

Where clauses attach predicates after a signature or item header:

```lanius
fn choose<T>(left: T, right: T) -> T where T: core::cmp::Ord<T> {
    return left;
}
```

Where predicates participate in trait obligation checking. The generated slice
has bounded evidence for qualified trait bounds, nonzero generic slot subjects,
two generic bound argument slots, alias normalization in predicate arguments,
and private predicate argument rejection across modules.

Where clauses are not a general trait solver promise. Missing, ambiguous, or
unsupported obligations should report a trait-solving diagnostic instead of
letting later codegen infer behavior.

## Trait Impls And Generic Receivers

Trait declarations and impls can be generic:

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

The current compiler validates bounded trait impl method contracts: required
methods, extra methods, arity, parameter and return types, duplicate methods,
and visibility agreement between trait declarations and impl methods.

Inherent methods on concrete generic receivers also have bounded evidence:

```lanius
struct Boxed<T> {
    value: T,
}

impl Boxed<i32> {
    pub fn get(self: Boxed<i32>) -> i32 {
        return self.value;
    }
}
```

Method-level generics, nested inherent impl receiver arguments, generic
inherent method return substitution, trait impl headers with unsupported
generic arguments, and trait impl methods called as free functions remain
fail-closed support boundaries.

## Generic Aliases

Generic type aliases name type expressions:

```lanius
type Maybe<T> = core::option::Option<T>;
```

Alias normalization is bounded. Scalar aliases and selected alias use in
generic calls and predicate arguments have evidence. Recursive aliases, deep
generic alias chains, broad const-generic alias substitution, and arbitrary
backend-lowered alias targets are not documented as general rewrite behavior.

## Diagnostics

Generic and bound failures should point at the source construct that made the
unsupported or invalid relationship visible:

| Failure | Typical diagnostic |
| --- | --- |
| duplicate generic parameter names | `LNC0033` invalid generic parameter list |
| type argument or generic call mismatch | `LNC0006` type mismatch or `LNC0027` call resolution failed |
| unsatisfied trait bound | `LNC0008` unsatisfied trait bound |
| ambiguous trait bound | `LNC0009` ambiguous trait bound |
| invalid trait impl contract | `LNC0021` invalid trait implementation |
| unsupported generic method dispatch | `LNC0027` call resolution failed |

If an implementation limit remains, the diagnostic should identify the
offending parameter list, argument, bound, receiver, impl header, method, call,
or return expression. It should not accept a prefix of the generic relationship
or erase unsupported arguments.

## What Not To Infer

Do not infer these stronger claims from generic syntax:

- Generic calls have arbitrary argument width.
- Nested generic instances are accepted wherever the outer nominal type matches.
- Const generic parameters imply broad const evaluation.
- Trait bounds imply a complete trait solver.
- Trait impl methods become free functions.
- Method syntax implies broad trait dispatch or method-level generic dispatch.
- Generic aliases are a general recursive rewrite system.
- Backend support follows automatically from frontend type checking.

## Updating This Chapter

When generic support changes:

1. Update the implementation and focused tests at the owner boundary:
   parser-HIR records, type checker substitution, predicate solving, method
   lookup, enum payload typing, alias normalization, or backend metadata.
2. Update `docs/language_slice_unstable_alpha.tsv` and regenerate the slice
   when a public support row changes.
3. Update this chapter for user-facing generic rules, examples, and
   fail-closed boundaries.
4. Keep implementation loops, strides, buffers, and pass names in compiler
   internals or generated references unless they are needed to explain a
   user-visible diagnostic.
5. Run `tools/docs_check.py`.
