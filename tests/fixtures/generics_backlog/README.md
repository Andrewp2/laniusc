Generics probes for features the standard library needs that are not
implemented yet. Run with `tools/generics_matrix.py --probes tests/fixtures/generics_backlog`.
When a probe passes, move it to `tests/fixtures/generics_matrix/`.

Known gaps that need multi-file probes (not runnable by the single-file matrix yet):
- A trait from another source-root module implemented in the caller module:
  `pub impl gen::lib::Score for Rec` fails with LNC0007 (unknown type at the
  trait path), and `import gen::lib; pub impl Score for Rec` fails with
  LNC0021. Repros by P10 in its scratchpad (p10/xmod/x1..x5).
