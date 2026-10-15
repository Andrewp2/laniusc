Generics probes for features the standard library needs that are not
implemented yet. Run with `tools/generics_matrix.py --probes tests/fixtures/generics_backlog`.
When a probe passes, move it to `tests/fixtures/generics_matrix/`.

Probes:
- b01: a where-clause bound on a concrete subject (`where bool: Inner<[i32; M]>`).
  The predicates collector admits only type-parameter subjects (LNC0008). Moved out
  of the matrix (was p26); the code-38 impl-head fix it also needed is covered by p27.
- b02: a bound proved through two levels of a generic impl
  (`total(Twice { inner: Twice { inner: Rect {..} } })`, `impl<T> Area for Twice<T>
  where T: Area`). The call fails LNC0008 (no matching impl); one level is p30.

Passed and moved to the matrix: b00 (a generic impl method called through a
`T: Area` bound) is p30, with variants p31..p34; the cross-module trait impls
P10 found (x1..x5) are the directory probes m00..m05.
