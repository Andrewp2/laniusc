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
  Two levels pass when the argument is an annotated `let two: Twice<Twice<Rect>>`;
  only a type inferred from the nested struct literal fails (handed to P7a).

Gaps found while writing the generic core::vec, core::set and core::pair
(2026-10-15). Each probe returns 42 once the feature works; the diagnostic is
what the current compiler prints. "Blocks" counts the existing per-type
stdlib modules that a generic replacement cannot cover until the gap closes.
- b05: `Self` in a trait member signature, `fn same(self, other: Self)`.
  LNC0007 "unknown type" at 1:35. With b06 this is the other route to an Eq
  without type arguments.
- b06: a bound on an imported trait, `where T: core::cmp::Eq<T>` and
  `T::eq(a, b)`. LNC0027 "call resolution failed" at 6:13: no candidate is
  offered for the imported trait's required member. Blocks every module family that compares
  elements: option_* (11, contains), result_* (12, contains), slice_* (10),
  range_* (6), vec_* (10, sort and search), set_* (8), map_* (8) and deque_*
  (10, contains), 75 modules in all. core::set works around it with its own
  Key trait, so only types implemented in core::set can be set items.
- b09: the array repeat expression `[10; 4]`. LNC0016 at 2:30 ("expected `]`
  or `,`, found `;`"). Generic fixed-capacity containers take their backing
  array from the caller instead. Blocks none.
- b11: a diverging match arm, `None -> core::panic::panic()`, in a generic
  function returning T. LNC0006 "type mismatch" at 4:58 (no never type).
  Blocks a generic unwrap or expect; no existing module panics.
- b12: a user type implementing a stdlib trait (`pub impl core::set::Key for
  Point` in app::main), used through the bound in core::set. The bound call
  now routes to the user's impl; x86 then fails with LNC0017 "x86 callee
  function lost its checked aggregate result layout" at core/set.lani:78 for
  `Set<Point, 3>` (the record-element aggregate layout gap). The i32 control
  passes. Blocks user item types in core::set.
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
- A local type that shadows an imported variant's owner, `import
  core::choices; enum Choice<T> { Local(T) }` then `Choice::Imported(42)` or
  `Choice<i32>::Imported(42)`, is rejected with LNC0027 "call resolution
  failed" instead of the LNC0005 or LNC0042 that
  qualified_enum_variants_bind_qualifier_scope_before_members
  (tests/compiler_generic_types_execution.rs) expects. Present on 656fd44e;
  the test's accepted forms run and return 42.
- A generic declaration that contains itself by value,
  `struct Node<T> { value: T, next: Node<T> }`, is accepted while nothing
  instantiates it (a compile exits normally). It should be rejected with
  LNC0006 "recursive type has infinite size", as the non-generic cases are
  since 4528e7b6. The check lives in the native layout walker (01c), which
  sees only instantiated layouts. Not a probe because the expected result is a
  rejection rather than exit 42 (docs/compiler-generic-types.md, "Recursive
  by-value types").

Passed and moved to the matrix: b00 (a generic impl method called through a
`T: Area` bound) is p30, with variants p31..p34; the cross-module trait impls
P10 found (x1..x5) are the directory probes m00..m05. b03 (a generic trait's
method through `S: Get<T>`, on `Slot<i32>` and `Slot<Rec>`) is p43; the
static member `T::same(a, b)` through `T: Same<T>` is p44; a self method
through `T: Conv<i32>` is p45; a const-generic impl's method through
`S: Size` on `Buf<i32, 3>` is p46. b07 (a const parameter as a cast operand,
`N as i32`) is p47. b08 (a match expression as the value of an arm that
other arms follow) is p48. b10 (`core::mem::size_of<T>()`, directly and from a
generic body) is p52; generic allocation-backed buffers over it and
`core::mem::typed_slice_from_storage` are
tests/fixtures/stdlib_foundation/core_mem_size_of.lani.

Open stdlib needs (owner TBD):
- String equality on `str` elements. `words[0] != "after"` with
  `words: [str; 2]` fails with LNC0006, and docs/compiler-generic-types.md
  calls the operator unsupported. Keyed string containers and parsers need
  it. Repro: tests/fixtures/stdlib_foundation/repro_ordinary_string_comparison.lani
  (expects exit 42; listed in tests/fixtures/known_gaps.txt).
