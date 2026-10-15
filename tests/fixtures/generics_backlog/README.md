Generics probes for features the standard library needs that are not
implemented yet. Run with `tools/generics_matrix.py --probes tests/fixtures/generics_backlog`.
When a probe passes, move it to `tests/fixtures/generics_matrix/`.

Probes:
- b00: a generic impl method called through a `T: Area` bound ("call resolution failed").
- b01: a where-clause bound on a concrete subject (`where bool: Inner<[i32; M]>`).
  The predicates collector admits only type-parameter subjects (LNC0008). Moved out
  of the matrix (was p26); the code-38 impl-head fix it also needed is covered by p27.

Known gaps that need multi-file probes (not runnable by the single-file matrix yet):
- A trait from another source-root module implemented in the caller module:
  `pub impl gen::lib::Score for Rec` fails with LNC0007 (unknown type at the
  trait path), and `import gen::lib; pub impl Score for Rec` fails with
  LNC0021. Repros by P10 in its scratchpad (p10/xmod/x1..x5).

Open stdlib needs (owner TBD):
- String equality on `str` elements. `words[0] != "after"` with
  `words: [str; 2]` fails with LNC0006, and docs/compiler-generic-types.md
  calls the operator unsupported. Keyed string containers and parsers need
  it. Repro: tests/fixtures/stdlib_foundation/repro_ordinary_string_comparison.lani
  (expects exit 42; listed in tests/fixtures/known_gaps.txt).
