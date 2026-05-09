# Lanius Source Standard Library

This directory contains the initial Lanius standard library as plain `.lani`
source files.

The full desired standard library surface is tracked in
[STANDARD_LIBRARY_SPEC.md](STANDARD_LIBRARY_SPEC.md). The long-term roadmap is
tracked in [PLAN.md](PLAN.md). Compiler and runtime prerequisites for
implementing those layers are tracked in
[LANGUAGE_REQUIREMENTS.md](LANGUAGE_REQUIREMENTS.md).

These files are not auto-imported by the compiler. To use a helper, add explicit
module-style source import lines before the code that calls it:

```lani
import core::i32;
import core::bool;

fn main() {
    return core::i32::abs(-7);
}
```

Module-form helpers live under `stdlib/core/` and use module names such as
`core::i32::abs`. Legacy flat files are still available through quoted imports
and keep the `lstd_` prefix so copied files are less likely to collide with
application functions.

Current scope is intentionally small:

- `core/i32.lani` has module-form integer constants and helpers built from
  supported arithmetic and comparison operators.
- `core/bool.lani` has module-form boolean combinators and conversions built on
  the current bool expression surface, including `true` and `false` literals.
- `i32.lani` and `bool.lani` keep the older `lstd_` compatibility helpers.
- `array_i32_4.lani` has fixed-size `[i32; 4]` helpers. There are no generics or
  const parameters yet, so other array sizes need separate source helpers.

Imports are source-level includes expanded before lexing/parsing. Module-style
imports such as `core::i32` resolve through the package stdlib lookup. Quoted
user file imports resolve relative to the importing file; source-only compiler
APIs also look relative to the current working directory and package root.

Imported files may declare `module app::name;`. In that case, source expansion
rewrites module declarations and uses such as `app::name::helper()` to
compiler-private identifiers before lexing. Public declarations are visible
through the module path, and private declarations can be used by other code in
the same imported module. This is still a source-level namespace bridge, not a
full package system.
