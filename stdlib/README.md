# Lanius Source Standard Library

This directory contains the initial Lanius standard library as plain `.lani`
source files.

The long-term design is tracked in [PLAN.md](PLAN.md). Compiler and runtime
prerequisites for implementing those layers are tracked in
[LANGUAGE_REQUIREMENTS.md](LANGUAGE_REQUIREMENTS.md).

Lanius does not have modules or imports yet. These files are not auto-imported by
the compiler. To use a helper today, concatenate the needed stdlib source before
your program source:

```sh
cat stdlib/i32.lani stdlib/bool.lani my_program.lani > combined.lani
laniusc combined.lani
```

All exported helper names use the `lstd_` prefix so copied files are less likely
to collide with application functions.

Current scope is intentionally small:

- `i32.lani` has integer helpers built from supported arithmetic and comparison
  operators.
- `bool.lani` has boolean combinators and conversions that avoid unavailable
  bool literals.
- `array_i32_4.lani` has fixed-size `[i32; 4]` helpers. There are no generics or
  const parameters yet, so other array sizes need separate source helpers.

Keep these files source-level and explicit until a real package/import system
lands.
