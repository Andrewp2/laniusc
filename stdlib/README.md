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
    return lstd_i32_abs(-7);
}
```

All exported helper names use the `lstd_` prefix so copied files are less likely
to collide with application functions.

Current scope is intentionally small:

- `i32.lani` has integer constants and helpers built from supported arithmetic
  and comparison operators.
- `bool.lani` has boolean combinators and conversions built on the current bool
  expression surface, including `true` and `false` literals.
- `array_i32_4.lani` has fixed-size `[i32; 4]` helpers. There are no generics or
  const parameters yet, so other array sizes need separate source helpers.

Imports are source-level includes expanded before lexing/parsing. Module-style
imports such as `core::i32` resolve through the package stdlib lookup. Quoted
user file imports resolve relative to the importing file; source-only compiler
APIs also look relative to the current working directory and package root.
