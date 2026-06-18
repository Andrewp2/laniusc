# Name Resolution

This chapter explains how the current `unstable-alpha` language resolves names
and paths. It is the user-facing companion to
[Items and declarations](items-and-declarations.md),
[Functions and calls](functions-and-calls.md),
[Generics and bounds](generics-and-bounds.md),
[Traits and impls](traits-and-impls.md),
[Modules, imports, and packages](modules-and-imports.md), and the compiler-side
[Module and source-root resolution](../compiler/module-resolution.md) guide.

The core rule is that name meaning comes from source declarations, imports, and
use-site context. Package names, file paths, source-root directory names,
lockfile edges, generated artifacts, and old path spellings do not become
semantic names.

For exact support claims, use the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md), especially
the `imports`, `packages`, `parser-hir`, `semantics`, and `codegen` rows.

## Resolution Contexts

The same text can be resolved differently depending on where it appears:

| Context | Can resolve to |
| --- | --- |
| Module declaration | a module identity for the current source file |
| Import declaration | a dependency module path |
| Type position | primitive type, struct, enum, trait where accepted, type alias, generic parameter |
| Value expression | local, parameter, function, extern function, constant, enum constructor |
| Pattern position | enum variant, tuple-payload variant, or payload binding in supported match rows |
| Predicate position | trait declaration plus visible type arguments |
| Method lookup | inherent or trait impl method in the bounded receiver/trait rows |
| Field/member access | field on the resolved nominal aggregate or method lookup where supported |

The resolver should reject unresolved, ambiguous, or wrong-context names with a
source-spanned diagnostic rather than guessing from the first declaration that
has the same spelling.

## Source Modules

A module declaration names the current source module:

```lanius
module app::math;
```

Source-root and package workflows validate that source module identity agrees
with the loaded file. The file path can help discover candidate source files,
but the source declaration remains the semantic module identity.

Single-file inputs can compile without a leading `module` declaration when they
do not need source-root or package identity. Once a source file participates in
source-root, stdlib-root, package manifest, or lockfile loading, the leading
module/import metadata rules in
[Modules, imports, and packages](modules-and-imports.md) apply.

## Imports And Visibility

An import declaration makes another module available to the current module:

```lanius
module app::main;

import app::math;

fn main() {
    print(app::math::add_fee(36));
    return 0;
}
```

Only public declarations are visible across module boundaries:

```lanius
module app::math;

pub fn add_fee(value: i32) -> i32 {
    return value + 4;
}

fn private_helper(value: i32) -> i32 {
    return value;
}
```

The importing module can use `app::math::add_fee`. It should not treat
`private_helper` as cross-module API even if it can spell the name.

Imported names must be unambiguous. If two imported modules expose the same
public value or type name and a use site asks for the unqualified name, the
current resolver rejects the ambiguity instead of selecting by source order,
import order, package order, or root order.

## Qualified Paths

Qualified paths use `::`:

```lanius
let max: i32 = core::i32::MAX;
let value: core::option::Option<i32> = core::option::Some(1);
```

The leading segments identify a module or visible declaration depending on the
use site. The final segment is validated by the consuming context:

- a type annotation expects a type declaration or type alias
- a call expects a callable value or enum constructor
- a constant expression expects a value declaration that is a constant
- a pattern expects a variant or payload binding shape supported by match rows

Qualified syntax alone is not a support guarantee. The generated slice owns the
current rows for qualified type paths, qualified value paths, imported
constants, enum constructors, generic calls, and backend lowering.

## Locals, Parameters, And Blocks

Function parameters and `let` declarations introduce local value names:

```lanius
fn add(left: i32, right: i32) -> i32 {
    let total: i32 = left + right;
    return total;
}
```

Local lookup is scoped to the function and nested blocks. The current compiler
has evidence for block-scoped shadowed locals in supported frontend/backend
rows:

```lanius
fn pick(value: i32) -> i32 {
    let result: i32 = value;
    {
        let result: i32 = value + 1;
        return result;
    }
}
```

Do not infer a broad declaration-merging or overload system from local
shadowing. Duplicate items, duplicate generic parameter names, duplicate struct
fields, and ambiguous imported names are separate validation questions and can
fail closed before later consumers use the name.

## Generic Parameters

Generic parameters introduce names inside the declaration that owns them:

```lanius
fn keep<T>(value: T) -> T {
    return value;
}

struct Pair<T> {
    left: T,
    right: T,
}
```

Generic names can appear in type positions, bounds, and where clauses supported
by the current slice. Use [Generics and bounds](generics-and-bounds.md) for the
generic support boundary. Duplicate generic parameter names should fail before
inference or substitution can choose an arbitrary binding.

Const generic parameters introduce value-like names for type expressions that
accept array lengths:

```lanius
struct Buffer<const N: usize> {
    values: [i32; N],
}
```

Const generic support is bounded. A const parameter appearing in a parsed
declaration does not imply arbitrary const evaluation, predicate solving, alias
substitution, or backend lowering.

## Enum Variants And Patterns

Enum variants contribute value names for constructors and pattern matching:

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

In a tuple-payload pattern, the variant path is resolved first, then payload
bindings are introduced for that arm expression. Same-name decoy variants from
another enum should not drive payload typing for the matched enum.

Use [Patterns and matching](patterns-and-matching.md) for match-arm syntax,
binding scope, payload order, and exhaustiveness boundaries.

## Methods And Fields

Member syntax can name fields or methods depending on the receiver and current
support rows:

```lanius
fn score(pair: Pair) -> i32 {
    return pair.left + pair.right;
}
```

Field lookup is against the resolved nominal struct declaration. The same field
name can exist on unrelated structs without making those fields
interchangeable.

Method lookup is bounded. Direct self methods and selected concrete generic
receiver method rows have evidence, including same-name inherent methods on
different concrete generic receiver instances. Broad trait dispatch,
method-level generic dispatch, qualified method callees, and dynamic dispatch
are not implied by member syntax. Use [Traits and impls](traits-and-impls.md)
for the focused method and trait dispatch boundaries.

## Standard Library Names

The source-level standard library is not implicitly preloaded. To resolve
stdlib modules and declarations, the compiler must receive a stdlib root or
package metadata that supplies one:

```bash
laniusc check --source-root src --stdlib-root stdlib src/app/main.lani
```

User/package imports search user roots first, then stdlib fallback candidates.
Stdlib sources may import other stdlib modules, but they may not import back
into user/package roots.

This precedence is a resolution rule, not a compatibility alias. A package name
or directory name does not stand in for a missing source module declaration, and
a lockfile cannot preserve a stale stdlib fallback when user source now supplies
the imported module.

## Ambiguity And Failure

Resolution must fail closed when a name has no supported meaning or more than
one supported meaning in the requested context:

| Failure | Typical diagnostic |
| --- | --- |
| missing local, item, field, variant, or path | `LNC0005` unresolved identifier |
| missing source-root import target | `LNC0001` missing source-root module |
| ambiguous source-root candidate | `LNC0003` ambiguous source-root module |
| ambiguous imported public name | source-spanned import/name diagnostic from the type checker |
| duplicate module declaration | `LNC0013` duplicate module declaration |
| unsatisfied or ambiguous trait predicate | `LNC0008` or `LNC0009` |
| unsupported import syntax | `LNC0011` unsupported import form |

The primary label should point at the use, declaration, import, path, pattern,
or member access that exposed the problem. Raw module ids, source-pack row ids,
GPU status words, and lockfile edge ids are not user-facing locations.

## What Not To Infer

Do not infer these stronger claims from current name syntax:

- Package names, file names, root names, or output artifact names are modules.
- The compiler has a prelude that auto-imports stdlib declarations.
- Imported ambiguity resolves by source order, import order, or root order.
- Qualified paths support every value, method, constructor, and backend shape.
- Local shadowing implies item overloading or declaration merging.
- A parsed method call implies broad trait dispatch.
- A lockfile can keep using a stale resolution when live source now disagrees.

## Updating This Chapter

When name resolution changes:

1. Update the implementation and focused tests at the owner boundary:
   source-root discovery, parser HIR, module path resolution, projection,
   type checking, or backend metadata.
2. Update `docs/language_slice_unstable_alpha.tsv` and regenerate the slice
   when a public support row changes.
3. Update [Modules, imports, and packages](modules-and-imports.md) for loading
   and package behavior.
4. Update this chapter for user-visible lookup, visibility, ambiguity, and
   source-spanned diagnostic rules.
5. Run `tools/docs_check.py`.
