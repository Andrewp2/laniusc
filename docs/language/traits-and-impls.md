# Traits And Impls

This chapter describes the current `unstable-alpha` trait declaration, trait
bound, inherent impl, trait impl, and method lookup surface. It is the
user-facing reference for trait and impl behavior; use
[Generics and bounds](generics-and-bounds.md) for the broader generic
parameter and where-clause model, and [Name resolution](name-resolution.md) for
lookup rules. Use [Functions and calls](functions-and-calls.md) for function
signatures, method calls, constructor calls, extern/runtime calls, and call ABI
boundaries outside the trait/impl contract itself.

The current compiler validates selected trait and impl contracts, but it does
not claim a complete trait system. For exact support claims, use the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md), especially
the `parser-hir`, `semantics`, `imports`, and `codegen` rows that mention
traits, impls, predicates, methods, receivers, and dispatch.

## Trait Declarations

A trait declaration names a method contract:

```lanius
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
    fn ne(left: T, right: T) -> bool;
}
```

Trait methods are signatures, not bodies. A method signature can carry
parameters, an optional return type, generic parameters in the grammar, and a
where clause. The current semantic surface is narrower than the grammar:
method-level generics in trait method contracts are intentionally fail-closed
until the method-contract rows carry enough substitution data.

Trait declarations can be public:

```lanius
pub trait Describe<T> {
    pub fn describe(value: T) -> i32;
}
```

Trait method visibility is part of the trait contract. Impl methods must match
the resolved trait method's visibility.

## Inherent Impls

An inherent impl attaches methods to a receiver type:

```lanius
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn contains(self: Range, value: i32) -> bool {
        return value >= self.start && value < self.end;
    }
}
```

The current type checker has bounded evidence for direct receiver methods,
including `self`, `self: Type`, `&self`, and concrete generic receiver cases:

```lanius
struct Boxed<T> {
    value: T,
}

impl Boxed<i32> {
    fn get(self: Boxed<i32>) -> i32 {
        return self.value;
    }
}
```

Method lookup is receiver-driven. Same-spelled free functions or methods on
different concrete receivers should not be selected unless the receiver and
current method rows match.

## Trait Impls

A trait impl provides methods for a trait/receiver pair:

```lanius
impl Eq<i32> for i32 {
    fn eq(left: i32, right: i32) -> bool {
        return left == right;
    }

    fn ne(left: i32, right: i32) -> bool {
        return left != right;
    }
}
```

The impl header must resolve to a trait declaration. If the header names a
struct or another non-trait declaration, the compiler should reject the impl at
the header instead of treating it as an unresolved type or silently accepting
method rows.

Trait impl validation is contract-based:

- every required trait method must be implemented
- an impl method must not appear unless the trait declares it
- method arity must match
- parameter and return types must match the resolved trait declaration after
  supported substitution
- duplicate impl methods fail closed
- method-level generics in impl methods fail closed

Impl method order does not need to match trait declaration order. The contract
is method-name and owner based, not source-order based.

## Visibility Agreement

Public trait contracts and impl contracts must agree:

```lanius
module core::describe;

pub trait Describe<T> {
    pub fn describe(value: T) -> i32;
}

pub impl Describe<i32> for i32 {
    pub fn describe(value: i32) -> i32 {
        return value;
    }
}
```

A private impl header cannot satisfy a public trait contract across modules. A
private impl method cannot satisfy a public trait method. Conversely, a public
impl header for a private trait contract is rejected because it would publish a
relationship whose trait is not public.

Visibility is checked as part of trait impl validation, before later obligation
matching can erase the boundary.

## Bounds And Obligations

Trait bounds create obligations:

```lanius
fn keep<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}
```

The current slice has bounded evidence for qualified trait bounds, selected
generic-slot substitution, two generic bound argument slots, alias
normalization in predicate arguments, and private predicate argument rejection.

Bounds are not a complete trait solver promise. Missing impls, ambiguous
candidate sets, unsupported predicate shapes, const-generic bound subjects, and
over-deep inline bound chains can fail closed with trait-solving diagnostics.

## Method Lookup And Dispatch

Dot-call method syntax uses the receiver expression to select a method in the
bounded method rows:

```lanius
fn read(range: Range) -> i32 {
    if (range.contains(2)) {
        return 1;
    }
    return 0;
}
```

Current evidence includes direct self receiver method calls, same-name methods
on different concrete generic receiver instances, source-pack method resolution
with two concrete receiver type arguments, and methods on projected concrete
generic struct fields.

The current reference does not claim broad trait dispatch, dynamic dispatch,
trait objects, associated types, blanket impls, coherence/orphan rules,
specialization, method-level generic dispatch, or qualified method callees.
Unsupported method lookup should fail at the receiver, member name, method
declaration, impl header, or call site named by the diagnostic.

## Trait Impl Methods Are Not Free Functions

Trait impl methods validate trait contracts. They do not publish ordinary
module-level value declarations:

```lanius
trait Describe<T> {
    fn describe(value: T) -> i32;
}

impl Describe<i32> for i32 {
    fn describe(value: i32) -> i32 {
        return value;
    }
}
```

Calling `describe(1)` as a free function is not documented as supported just
because a trait impl method with that name exists. The generated slice has an
explicit fail-closed boundary for trait impl methods as free functions until
dispatch and monomorphization rows support a stronger rule.

## Diagnostics

Trait and impl failures should report `LNC0021` when the impl contract is
invalid, or the relevant trait-solving/call-resolution code when a use site
cannot satisfy or dispatch a bound.

Typical failures include:

| Failure | Preferred source location |
| --- | --- |
| impl header does not resolve to a trait | impl header |
| missing required trait method | impl header, with the missing contract named in notes |
| extra impl method | extra method declaration |
| wrong method arity | impl header or mismatched method declaration |
| wrong parameter or return type | impl header or mismatched method declaration |
| duplicate impl method | duplicate method declaration |
| method-level generics | method declaration with generic parameters |
| visibility mismatch | impl header or method whose visibility disagrees |
| unsupported method dispatch | member name, receiver, or call site |

The diagnostic should describe the contract mismatch, not leak raw GPU status
words or let a later backend phase guess a partial dispatch.

## What Not To Infer

Do not infer these stronger claims from trait or impl syntax:

- A trait declaration creates a trait object type.
- A trait impl method is a free function.
- Dot-call syntax implies arbitrary trait dispatch.
- Method-level generics are supported because the grammar parses them.
- Impl method order matters.
- Public and private trait contracts can be mixed freely.
- A type-checked trait or method shape is executable on every target.

## Updating This Chapter

When trait or impl behavior changes:

1. Update focused tests at the owner boundary: parser-HIR records, trait impl
   validation, predicate solving, method lookup, visibility, or backend
   metadata.
2. Update `docs/language_slice_unstable_alpha.tsv` and regenerate the slice
   when a public support row changes.
3. Update this chapter for user-visible trait/impl rules, examples, and
   diagnostics.
4. Keep shader pass details, row strides, and buffer names in compiler
   internals or generated references unless they directly explain a
   user-visible diagnostic.
5. Run `tools/docs_check.py`.
