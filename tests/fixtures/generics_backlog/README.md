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
- b03: a generic trait's method called through a bound (`fn fetch<S, T>(s: S,
  fallback: T) -> T where S: Get<T> { return s.get(); }` on `Slot<i32>` and
  `Slot<Rec>`). The original compile rejects `s.get()` (LNC0027, no method
  signature matches the receiver), with and without instance copies.
- b04: a const-generic impl's method called through a bound (`measure<S>`
  with `S: Size` on `Buf<i32, 3>`). The replayed bound call fails LNC0027
  ("the receiver's implementation must be a non-generic local impl"), with and
  without instance copies. A direct call on the concrete receiver is p42.

Gaps found while writing the generic core::vec, core::set and core::pair
(2026-10-15). Each probe returns 42 once the feature works; the diagnostic is
what the current compiler prints. "Blocks" counts the existing per-type
stdlib modules that a generic replacement cannot cover until the gap closes.
- b03: a static trait member called on a type parameter, `T::same(a, b)`
  with `where T: Same<T>`. LNC0027 "call resolution failed" at 7:13. No call
  key is published for a type-parameter head. This is the shape of
  core::cmp::Eq and Ord. Blocks 75 modules (see b06).
- b04: a self method through a bound on a trait with type arguments,
  `where T: Conv<i32>` and `a.conv()`. LNC0027 at 3:62.
  07a_offer_bound_members offers no member for a bound with arguments.
  Needed for the same 75 modules.
- b05: `Self` in a trait member signature, `fn same(self, other: Self)`.
  LNC0007 "unknown type" at 1:35. With b06 this is the other route to an Eq
  without type arguments.
- b06: a bound on an imported trait, `where T: core::cmp::Eq<T>` and
  `T::eq(a, b)`. LNC0005 "unresolved identifier" at 6:13 (LNC0027 when the
  call is inside a stdlib module). Blocks every module family that compares
  elements: option_* (11, contains), result_* (12, contains), slice_* (10),
  range_* (6), vec_* (10, sort and search), set_* (8), map_* (8) and deque_*
  (10, contains), 75 modules in all. core::set works around it with its own
  Key trait, so only types implemented in core::set can be set items.
- b07: a const parameter as a cast operand, `N as i32`. Checks, but x86
  rejects it with LNC0017 "operation is not implemented by the x86 backend"
  at 1:59. `let n: usize = N; n as i32` and `(len as usize) == N` work.
  Blocks no module.
- b08: a match expression as a match arm value. LNC0016 "syntax error" at
  3:12. A helper function works around it (core::pair::zip). Blocks none.
- b09: the array repeat expression `[10; 4]`. LNC0016 at 2:30 ("expected `]`
  or `,`, found `;`"). Generic fixed-capacity containers take their backing
  array from the caller instead. Blocks none.
- b10: `core::mem::size_of<T>()` does not exist. LNC0027 at 3:24. A generic
  heap-backed container cannot size its allocation; this blocks the 36
  allocating vec_*, set_*, map_* and deque_* modules.
- b11: a diverging match arm, `None -> core::panic::panic()`, in a generic
  function returning T. LNC0006 "type mismatch" at 4:58 (no never type).
  Blocks a generic unwrap or expect; no existing module panics.
- b12: a user type implementing a stdlib trait (`pub impl core::set::Key for
  Point` in app::main), used through the bound in core::set. The compiler
  stops with LNC0057 "compiler execution failed" instead of a diagnostic.
  Blocks user item types in core::set.
- b13: a generic function returning another generic function's imported
  `core::option::Option<T>` result, `return get(value);`. LNC0006 "type
  mismatch" at 5:65, from both `check` and a compile, even with the function
  uncalled. The same shape with a local enum, or with a plain `T` result,
  passes. Present on 335e31b8; core::vec's form of it checked clean on
  b8172cdf. core::vec repeats get's
  body in first and last until it is fixed; then they should call get again.

Not probes here:
- An imported call's record result passed straight to another call, e.g.
  `try_reserve(new(), 1)` or `try_push(try_push(v, 30), 12)`, fails with
  LNC0006 at the inner call when the program is compiled (P10 group A, owned
  by P4). It blocks the set_char/map_char_u32 allocation-failure fixtures and
  their i32 counterparts.

Passed and moved to the matrix: b00 (a generic impl method called through a
`T: Area` bound) is p30, with variants p31..p34; the cross-module trait impls
P10 found (x1..x5) are the directory probes m00..m05.

Open stdlib needs (owner TBD):
- String equality on `str` elements. `words[0] != "after"` with
  `words: [str; 2]` fails with LNC0006, and docs/compiler-generic-types.md
  calls the operator unsupported. Keyed string containers and parsers need
  it. Repro: tests/fixtures/stdlib_foundation/repro_ordinary_string_comparison.lani
  (expects exit 42; listed in tests/fixtures/known_gaps.txt).
