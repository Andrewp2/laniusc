# Items And Declarations

This chapter describes the item declarations accepted by the current
`unstable-alpha` language surface. It sits between the compact
[Syntax reference](syntax.md) and the semantic [Types and values](types-and-values.md)
chapter: syntax says which source shapes parse, while this chapter says what
each declaration is for, what namespace it contributes to, and which support
boundaries users should check before treating it as executable.
Use [Name resolution](name-resolution.md) for the lookup rules that decide
which declaration a name or path refers to at a use site.
Use [Functions and calls](functions-and-calls.md) for the focused reference on
function signatures, parameters, arguments, direct calls, qualified calls,
generic calls, constructor calls, method calls, extern/runtime boundaries, and
call ABI behavior.
Use [Generics and bounds](generics-and-bounds.md) for the rules around generic
parameter lists, type arguments, const parameters, trait bounds, where clauses,
and generic impl/method boundaries.
Use [Traits and impls](traits-and-impls.md) for the focused trait declaration,
inherent impl, trait impl, method contract, visibility, and dispatch-boundary
reference.

For exact support claims, use the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md), the
[standard library generated reference](../stdlib/generated/reference.md), and
the [diagnostic index](../diagnostics/generated/error-index.md). The grammar is
[grammar/lanius.bnf](../../grammar/lanius.bnf).

## Source Files

A source file is a sequence of items. Empty files are grammar-valid, but normal
entry points need a useful declaration such as a function, module declaration,
or import metadata.

```text
item*
```

Package and source-root workflows add rules above the grammar. In those modes,
the loader uses module declarations and imports as file identity and dependency
metadata. Use [Modules, imports, and packages](modules-and-imports.md) and
[Packages and source roots](../packages.md) for those rules.

## Item Families

The current grammar accepts these top-level item families:

| Family | Shape | Declares |
| --- | --- | --- |
| Module declaration | `module app::main;` | source module identity |
| Import | `import core::option;` | dependency/module metadata |
| Function | `fn name(params) -> Type { ... }` | value callable with a body |
| Extern function | `extern "abi" fn name(params) -> Type;` | value callable backed outside the source body |
| Constant | `const NAME: Type = expression;` | value item |
| Type alias | `type Name<T> = Type;` | type name |
| Struct | `struct Name<T> { fields }` | nominal type and named fields |
| Enum | `enum Name<T> { variants }` | nominal type and value constructors |
| Trait | `trait Name<T> { methods }` | predicate/interface declaration |
| Impl | `impl Type { methods }`, `impl Trait for Type { methods }` | method and predicate implementation facts |

Most item families accept a leading `pub`. Module declarations and imports are
file metadata rather than exported declarations and are not documented as `pub`
forms.

```lanius
module app::math;

pub const FEE: i32 = 4;

pub fn add_fee(value: i32) -> i32 {
    return value + FEE;
}
```

Parsing an item is not the same as every backend supporting every use of that
item. A trait declaration can be recorded by the frontend while a specific
generic method dispatch shape still fails closed. A runtime-backed extern can
type-check as a source contract while not being executable on a selected
target.

## Namespaces

Declarations are resolved in the namespace demanded by the use site:

| Use site | Typical declarations |
| --- | --- |
| Module metadata | `module`, `import` |
| Type position | primitive types, structs, enums, traits where accepted, type aliases, generic parameters |
| Value position | functions, extern functions, constants, local bindings, enum constructors |
| Predicate position | traits, visible type arguments, generic parameters |
| Method lookup | inherent impl methods and trait impl methods in the bounded slice |

The same spelling can appear in different contexts only when the resolver and
type checker can disambiguate it for the current use site. Ambiguous or
unsupported shapes should fail closed with a source-spanned diagnostic instead
of silently choosing a declaration.

## Module Declarations

A module declaration gives the file an explicit module identity:

```lanius
module app::main;
```

Module paths use `::`-separated identifiers. Source-root and package loaders use
the declaration to validate that the file content matches the module path being
loaded. A module declaration is source identity metadata; it does not import
anything by itself.

Current source-root and package workflows are intentionally explicit. If a file
depends on another module, use an import declaration. If a package manifest or
lockfile names modules, use the package docs for the manifest-level contract.

## Imports

An import declaration names another module that the current source file needs:

```lanius
import core::option;
import app::math;
```

The current public import form is a module path followed by `;`. The grammar
contains a quoted import shape, but source-root and package loading reject
quoted imports before treating them as reliable metadata. Glob imports, import
aliases, dotted module paths, and filesystem path separators are not documented
as supported import syntax.

Imports affect which module-level declarations are visible to the importing
module. They do not imply implicit prelude loading. The source-level standard
library is loaded only when the compiler is given the relevant `--stdlib-root`
or package metadata.

## Functions

A function item declares a callable value with a body:

```lanius
fn identity(value: i32) -> i32 {
    return value;
}
```

Parameters are comma-separated. Return types are optional in the grammar; when
present, they follow `->`. Function bodies contain statements, and control-flow
behavior is covered by
[Expressions and control flow](expressions-and-control-flow.md).

Generic parameters and where clauses can appear on function signatures:

```lanius
fn keep<T>(value: T) -> T {
    return value;
}

fn choose<T>(left: T, right: T) -> T where T: core::cmp::Ord<T> {
    return left;
}
```

The type checker has bounded evidence for selected direct generic calls,
qualified trait bounds, nested generic instances, and return consistency cases.
Those rows are the current support contract. Do not infer arbitrary generic
width, dispatch, or backend lowering from the grammar alone.

## Extern Functions

An extern function item declares a callable value without a source body:

```lanius
extern "lanius_panic" fn panic();
extern fn host_value() -> i32;
```

The ABI string is optional in the grammar. Extern declarations are useful for
source-level contracts, runtime binding metadata, and stdlib declarations whose
implementation lives outside the source file.

An extern declaration does not prove a host service is executable. Runtime-bound
stdlib modules can expose declarations and metadata while still failing closed
at compile, link, or target-runtime boundaries. Use [Targets and output](../targets.md)
and [Standard library](../stdlib/README.md) before treating an extern as
available on a target.

## Constants

A constant item declares a typed value item:

```lanius
pub const LIMIT: i32 = 4;

fn apply(value: i32) -> i32 {
    return value + LIMIT;
}
```

Constants live in the value namespace and can be accessed through visible
module paths when imports and visibility permit it:

```lanius
import core::i32;

fn max_value() -> i32 {
    return core::i32::MAX;
}
```

The strongest executable evidence today is bounded scalar constant use.
Aggregate constants, broad constant evaluation, const-generic substitution, and
target-specific constant lowering remain row-based support questions.

## Type Aliases

A type alias item gives a type expression another name:

```lanius
type Count = i32;
type MaybeCount = core::option::Option<Count>;
```

Aliases live in the type namespace. They can carry generic parameters and where
clauses in the grammar:

```lanius
type Maybe<T> = core::option::Option<T>;
```

Alias normalization is bounded. Scalar aliases and selected generic/predicate
uses have evidence, but recursive aliases, deep alias chains, broad
const-generic alias substitution, and arbitrary backend-lowered alias targets
are not a general compile-time rewrite guarantee.

## Structs

A struct item declares a nominal type with named fields:

```lanius
struct Pair {
    left: i32,
    right: i32,
}

fn score(pair: Pair) -> i32 {
    return pair.left * 10 + pair.right;
}
```

Struct fields are part of the selected nominal declaration. Same-spelled fields
on unrelated structs are not interchangeable. Struct literals name fields
explicitly:

```lanius
let value: Pair = Pair { left: 1, right: 2 };
```

Generic parameters and where clauses are accepted on struct declarations.
Current aggregate support is bounded by frontend, type-checker, and backend
rows. Selected struct literals, member reads, aggregate copies, and duplicate
field diagnostics have evidence; broad nested aggregate lowering and every
aggregate return shape should be checked against the generated slice.

## Enums

An enum item declares a nominal variant set:

```lanius
enum Option<T> {
    Some(T),
    None,
}
```

Variants can be unit variants or tuple-payload variants. Constructors live in
the value namespace for expression and pattern positions supported by the
current slice:

```lanius
fn unwrap_or(value: Option<i32>, fallback: i32) -> i32 {
    return match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
}
```

The frontend and type checker have bounded evidence for selected generic enum
constructors and match payload substitution cases. Backend support is narrower.
A generic enum declaration can be valid source while a specific constructor or
payload lowering still fails closed with a diagnostic.

## Traits

A trait item declares method signatures and predicate facts:

```lanius
trait Eq<T> {
    pub fn eq(left: T, right: T) -> bool;
    pub fn ne(left: T, right: T) -> bool;
}
```

Trait methods are semicolon-terminated signatures, not bodies. Method
signatures can use generic parameters, return types, and where clauses in the
same broad grammar family as functions.

Current trait support is intentionally bounded. Trait declarations, selected
qualified bounds, selected predicate argument shapes, and visibility checks have
evidence. Broad trait-object behavior, arbitrary dispatch, and every
method-level generic form are not implied by the declaration grammar.

## Impls

An impl item records methods for a receiver type or for a trait/receiver pair:

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

    pub fn ne(left: i32, right: i32) -> bool {
        return left != right;
    }
}
```

Impl methods have bodies. A method inside an impl can be public to consumers of
the receiver or trait relationship when visibility and the current lookup rules
allow it.

The current compiler records and checks bounded impl cases. Direct self methods
and selected trait impl predicates have evidence; broad dot-call dispatch,
method-level generic dispatch, and every qualified trait lookup form remain
support-boundary questions.

## Visibility

`pub` exposes a declaration outside its declaring module when the surrounding
source-root, stdlib-root, or package boundary makes the module visible:

```lanius
pub fn exported(value: i32) -> i32 {
    return value;
}

fn local_only(value: i32) -> i32 {
    return value + 1;
}
```

Private declarations remain available inside their module. They are not
documented as cross-module API even if another file can spell the same name.
Private type aliases and predicate arguments should be rejected when a public
cross-module use would leak them.

Visibility is not a compatibility promise. In `unstable-alpha`, changing a
private declaration can still break current users if they depended on
unsupported behavior, but the documented public surface is the visible module
API plus the generated slice evidence.

## Generics, Bounds, And Const Parameters

Functions, aliases, structs, enums, traits, and impls can carry generic
parameters. A generic parameter may have bounds, and const generic parameters
use `const NAME: Type`:

```lanius
struct Buffer<const N: usize> {
    values: [i32; N],
}
```

Where clauses are comma-separated predicate lists:

```lanius
fn first<T>(left: T, right: T) -> T where T: core::cmp::Eq<T> {
    return left;
}
```

The supported semantic shape is intentionally not a simple token-count limit.
The compiler should either accept a construct because the relevant frontend,
type-checker, and backend rows support it, or fail closed at the source span
that explains the unsupported part. When bounded rows are expanded, update this
chapter and the generated slice evidence together.

## What Not To Infer

Do not infer these stronger claims from item syntax:

- A parsed declaration is executable on every target.
- A type-checked runtime-backed declaration has an available host service.
- An accepted generic declaration supports every argument width or nested type
  shape.
- A trait or impl declaration means arbitrary dynamic dispatch exists.
- A private declaration is part of the cross-module API.
- A generated stdlib declaration is implicitly preloaded.

The supported language surface is the combination of grammar, resolver/type
checker behavior, backend evidence, target selection, and generated slice rows.

## Updating This Chapter

When item behavior changes:

1. Update the implementation and focused tests that prove the new boundary.
2. Update `docs/language_slice_unstable_alpha.tsv` and regenerate the slice
   reference when the public support row changes.
3. Update this chapter only for user-facing rules and examples that should
   remain stable enough to read as reference prose.
4. Run `tools/docs_check.py`.

Avoid documenting a wish as a rule. If the current compiler rejects a reasonable
source shape, say where it fails closed or leave the stronger behavior out of
the reference until there is evidence.
