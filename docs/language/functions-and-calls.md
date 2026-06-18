# Lanius Functions And Calls

This chapter describes function declarations, callable values, call
expressions, parameters, arguments, methods, extern declarations, and
target-call boundaries in the current `unstable-alpha` language slice.

It sits between [Items and declarations](items-and-declarations.md), which
lists item syntax and namespaces, [Expressions and control flow](expressions-and-control-flow.md),
which describes statements and expression behavior, [Generics and bounds](generics-and-bounds.md),
which describes generic substitution, and [Traits and impls](traits-and-impls.md),
which describes method contracts and dispatch boundaries.

Function support is documented in layers:

- the parser records function signatures, return types, method signatures, and
  call arguments
- name resolution selects a callable declaration, enum constructor, or method
  target for the use site
- type checking validates argument types, return expectations, generic slots,
  trait bounds, and method receiver rows
- the selected backend either lowers the call through its ABI slice or fails
  closed with a source-spanned diagnostic

For row-level support claims, use the generated
[unstable-alpha slice reference](generated/unstable-alpha-slice.md).

## Source Of Truth

Use these layers together:

| Question | Primary source |
| --- | --- |
| Which declaration and call syntax parses? | [Syntax reference](syntax.md) and [grammar/lanius.bnf](../../grammar/lanius.bnf) |
| Which declarations create callable names? | [Items and declarations](items-and-declarations.md) and [Name resolution](name-resolution.md) |
| How do generic parameters, arguments, and bounds affect calls? | [Generics and bounds](generics-and-bounds.md) |
| How do methods and trait impls affect calls? | [Traits and impls](traits-and-impls.md) |
| Which calls execute on a target? | [Codegen and backends](../compiler/codegen.md), [x86 backend](../compiler/x86-backend.md), and generated slice codegen rows |
| Which diagnostic explains a rejected call? | [Diagnostics](../DIAGNOSTICS.md) and [generated error index](../diagnostics/generated/error-index.md) |

If a maintained prose page and the generated slice disagree, trust the
generated slice and its named tests first, then update the prose.

## Function Items

A function item declares a callable value with a body:

```lanius
fn add(left: i32, right: i32) -> i32 {
    return left + right;
}
```

Parameters are comma-separated and named. A return type follows `->` when the
function returns a value:

```lanius
fn ignore(value: i32) {
    return;
}
```

Return types are optional in the grammar. A function with no return type uses
`return;` or falls through only when the current type-checker and backend rows
allow that source shape. A function with a return type must satisfy the current
return-convergence rules before codegen can continue.

## Parameters And Locals

Function parameters introduce local value names inside the function body:

```lanius
fn clamp_low(value: i32, minimum: i32) -> i32 {
    if (value < minimum) {
        return minimum;
    } else {
        return value;
    }
}
```

Parameter names participate in the same local-value namespace as `let`
bindings. Duplicate names, unsupported shadowing shapes, or wrong-context uses
should fail in name resolution or type checking instead of being repaired by a
later backend.

Parser-owned parameter, return-type, and nearest-function records are important
compiler evidence. Downstream passes should consume those records rather than
rescanning source text to rediscover which function owns a statement or
expression.

## Return Types And Return Statements

Return statements exit the current function:

```lanius
fn abs_i32(value: i32) -> i32 {
    if (value < 0) {
        return -value;
    } else {
        return value;
    }
}
```

The current type checker has bounded evidence for direct non-void return
convergence and one nested direct `if`/`else` propagation shape. Branch-only
nested returns outside those rows can still fail closed.

This is a user-facing diagnostic boundary: a non-void function should not let
codegen synthesize a default return when the frontend cannot prove a returned
value. The diagnostic should point at the function, return statement, or
control-flow construct that made convergence unprovable.

## Visibility And Namespaces

Top-level functions live in the value namespace:

```lanius
pub fn exported(value: i32) -> i32 {
    return value;
}

fn local_only(value: i32) -> i32 {
    return value + 1;
}
```

`pub` makes a function visible outside its declaring module when the source-root
or package boundary exposes that module. Private functions remain local to
their module even if another module can spell the same identifier.

Function names do not occupy the type namespace. Impl and trait methods are
also not ordinary module-level function items unless the current method/dispatch
rows explicitly publish such a callable surface.

## Extern Functions And Runtime Boundaries

An extern function declares a callable contract without a source body:

```lanius
extern "host" fn read_value() -> i32;
extern fn panic();
```

The ABI string is optional in the grammar. Extern declarations are useful for
stdlib contracts and runtime metadata, but a declared extern is not automatically
available on every target.

Runtime-bound stdlib declarations can type-check as source contracts while
remaining non-executable until a runtime service, ABI, linker binding, or target
backend row exists. A call to a known-unbound runtime function should fail
closed with a source-spanned diagnostic rather than becoming an unresolved
identifier or native-code placeholder.

## Direct Calls

A direct call invokes a callable value expression with positional arguments:

```lanius
fn add(left: i32, right: i32) -> i32 {
    return left + right;
}

fn main() {
    let total: i32 = add(1, 2);
    return;
}
```

The parser records the callee, each argument ordinal, and the source span for
the call and its arguments. Type checking validates the selected callable's
parameter count and parameter types against those argument rows.

The x86 backend has bounded execution evidence for scalar direct calls,
recursive scalar calls, bool-returning helper calls in branch conditions,
loop-contained calls, and four-argument calls with mixed literal/local
arguments.

## Qualified And Imported Calls

Qualified paths can name visible functions or constants through module paths:

```lanius
import core::u8;

fn is_space(byte: u8) -> bool {
    return core::u8::is_ascii_whitespace(byte);
}
```

Source-root, stdlib-root, and package loading decide which imported module
declarations are visible. A package name, file path, old path spelling, or
directory name does not create a semantic callable name.

The generated slice has bounded evidence for imported source-pack helper calls,
qualified stdlib helper calls that type-check through `--stdlib-root`, and
selected x86 source-pack helper calls. Those rows are not a broad claim that
every imported or stdlib function has an executable runtime binding.

## Generic Function Calls

Generic functions relate parameter and return types through type parameters:

```lanius
fn identity<T>(value: T) -> T {
    return value;
}

fn main() {
    let value: i32 = identity(7);
    return;
}
```

Current type-checker evidence includes nested direct generic calls, nested
generic forwarding helpers, nominal instance generic return inference, repeated
generic slot consistency, and scalar alias normalization in generic call
arguments.

Those rows are bounded. Calls beyond the current GPU substitution rows, unknown
generic instance argument slots, uninferred generic returns, nested generic
instance parameter annotations outside the supported relation rows, and some
qualified generic call widths fail closed at the call or argument span.

## Constructor Calls

Enum variants with payloads can be called like constructors in supported
contexts:

```lanius
enum Option<T> {
    Some(T),
    None,
}

fn wrap(value: i32) -> Option<i32> {
    return Some(value);
}
```

Constructor calls are value-namespace uses selected by name resolution and
validated by type checking against the expected enum type and payload slots.
Generic enum constructor support is bounded to the generated rows. Backend
support can be narrower than type-checker support, especially for multi-payload
or aggregate payload lowering.

Struct literals are not function calls. Use
[Aggregates and indexing](aggregates-and-indexing.md) for struct literal and
array literal rules.

## Method Calls

Dot-call method syntax selects a method through the receiver expression:

```lanius
struct Pair {
    left: i32,
    right: i32,
}

impl Pair {
    fn sum(self: Pair) -> i32 {
        return self.left + self.right;
    }
}

fn read(pair: Pair) -> i32 {
    return pair.sum();
}
```

Current evidence includes direct self receiver method calls, concrete generic
receiver method keys, same-name methods on different concrete generic receiver
instances, source-pack method resolution with two concrete receiver type
arguments, and methods on projected concrete generic struct fields.

The current reference does not claim broad trait dispatch, dynamic dispatch,
trait objects, associated types, blanket impls, method-level generic dispatch,
or qualified method callees. Unsupported method lookup should fail at the
receiver, member name, method declaration, impl header, or call site named by
the diagnostic.

Trait impl methods validate trait contracts. They do not become free functions
just because their names appear in an impl.

## Backend ABI Boundaries

The frontend can validate a call that a selected backend still cannot lower.
The main executable target today is `x86_64`; `wasm` remains a fail-closed
backend boundary for ordinary scalar programs.

Current x86 call evidence includes:

- direct scalar calls
- direct recursive scalar calls
- bool-returning helper calls in conditions
- loop-contained direct calls
- four-argument direct calls
- imported source-pack helper calls
- direct self receiver method calls
- imported source-pack self receiver method calls with explicit scalar
  arguments

Current x86 fail-closed call boundaries include helper parameters beyond the
current SysV register-backed ABI slice, known-unbound stdio runtime calls,
unsupported trait-method dispatch, and backend shapes that need stronger
control-flow or lowering records before execution can be proven.

## Diagnostics

Common rejection paths include:

| Case | Expected diagnostic surface |
| --- | --- |
| Unknown function or wrong namespace | unresolved-name diagnostic at the callee path or identifier |
| Argument count or type mismatch | type/call diagnostic at the call, argument, or parameter-related span |
| Missing return from non-void function | return-convergence diagnostic at the function or control-flow construct |
| Unsupported generic call shape | call-resolution or type diagnostic at the call or offending type/argument slot |
| Unsupported method dispatch | method/call-resolution diagnostic at the receiver, member name, or call |
| Trait impl method used as a free function | fail-closed call-resolution diagnostic at the callee |
| Runtime-bound extern without executable binding | runtime/codegen diagnostic at the call |
| Backend ABI overflow | native-codegen diagnostic at the call or parameter that exceeds the current ABI slice |

The diagnostic should name the source-level function or call problem. It should
not leak raw GPU row ids, shader status words, or native backend placeholders as
the only explanation.

## What Not To Infer

These are not current support claims:

- every parsed function signature is executable on every backend
- extern declarations have runtime bindings
- generic calls support arbitrary width, nesting, or inference
- trait impl methods are callable as free functions
- dot-call syntax implies broad trait dispatch or dynamic dispatch
- x86 call support implies the same call support on `wasm`
- a source-pack or stdlib function that type-checks is necessarily linked or
  executable

Use generated rows and backend tests before widening any of these claims.

## Updating This Chapter

When function or call support changes:

1. Update parser, resolver, type-checker, method, or backend tests for the owned
   behavior.
2. Update `docs/language_slice_unstable_alpha.tsv` with the exact support row
   or fail-closed row.
3. Regenerate `docs/language/generated/unstable-alpha-slice.md`.
4. Update this page and the narrower owner pages for items, generics, traits,
   expressions, targets, or stdlib as needed.
5. Run `tools/docs_check.py`.
