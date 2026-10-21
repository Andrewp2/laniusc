Generics probes for features the standard library needs that are not
implemented yet. Run with `tools/generics_matrix.py --probes tests/fixtures/generics_backlog`.
When a probe passes, move it to `tests/fixtures/generics_matrix/`.

Probes:

Gaps found while writing the generic core::vec, core::set and core::pair
(2026-10-15). Each probe returns 42 once the feature works; the diagnostic is
what the current compiler prints. "Blocks" counts the existing per-type
stdlib modules that a generic replacement cannot cover until the gap closes.
- b14 (directory): a self method called through a path on a type imported
  from a local module, `Counter::get(next)` after `import gen::count;`.
  LNC0027 "call resolution failed" ("call does not match a resolved function
  or method"). `next.get()` works (p57). Fails before and after bf4fd323,
  so it is not the import-visible capacity. It is not about imports at all:
  a local `Counter::get(next)` fails the same way, and so does the qualified
  `gen::count::Counter::get(next)`, while a static `Counter::make(40)` works
  locally and imported. Calling a self method through its type's path is
  not an implemented call form (no doc or test claims it). Owner: P13.
- b16 (Wasm only): a function whose result type is an imported generic
  enum, `fn half(x: i32) -> core::option::Option<i32>`, compiles to a module
  node rejects ("not enough arguments on the stack for local.set"). The same
  shape with a local `enum R<T>` runs, and x86 runs both. It blocks the
  generic Option/Result stdlib on Wasm (found 2026-10-20). Owner: TBD.
- b17: `some.unwrap()` on the stdlib's Option<T> inside a generic body with
  a record T (`fn run<T>(value: T)` called with a struct) segfaults (-11)
  at run time on x86. The free `core::option::unwrap(some)` runs in the same
  place, and so do scalar payloads, a direct call outside a generic body and
  a local enum's diverging method. Result's unwrap and unwrap_err methods
  crash the same way. core_option_result.lani calls the free forms from
  its generic checker and the methods on concrete records (found
  2026-10-20). Owner: TBD.

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

Passed and moved to the matrix: b02 (a bound proved through two levels of a
generic impl) is p79 and b13 (returning another generic function's imported
Option<T>) is p80, both passing by 2026-10-20. b15 (a bounded generic stdlib
body over a stdlib type whose impl is in its own module, such as
`std::vec::is_sorted(Vec<WideI64>)`) is p81: impl_bindings now binds
implementations of the template's own unit too, and template blanking maps
a dependency target in that unit back to the full template. b00 (a generic impl method called through a
`T: Area` bound) is p30, with variants p31..p34; the cross-module trait impls
P10 found (x1..x5) are the directory probes m00..m05. b03 (a generic trait's
method through `S: Get<T>`, on `Slot<i32>` and `Slot<Rec>`) is p43; the
static member `T::same(a, b)` through `T: Same<T>` is p44; a self method
through `T: Conv<i32>` is p45; a const-generic impl's method through
`S: Size` on `Buf<i32, 3>` is p46. b07 (a const parameter as a cast operand,
`N as i32`) is p47. b08 (a match expression as the value of an arm that
other arms follow) is p48. b09 (the array repeat `[10; 4]`, also
in a generic body) is p70. b10 (`core::mem::size_of<T>()`, directly and from a
generic body) is p52; generic allocation-backed buffers over it and
`core::mem::typed_slice_from_storage` are
tests/fixtures/stdlib_foundation/core_mem_size_of.lani.
`Self` in a trait member signature
(b05) is p49; a user type implementing a stdlib trait used through the bound
in core::set (b12) is p50; a where-clause bound on a scalar subject
(b01, `where bool: Inner<[i32; M]>`) is p51. A record type as a concrete
subject is still rejected with LNC0008. A bound on an imported trait,
`where T: core::cmp::Eq<T>` with `T::eq(a, b)` (b06), is p53; it unblocks the
module families that compare elements (option_*, result_*, slice_*, range_*,
vec_*, set_*, map_* and deque_*, 75 modules).
b11 (a diverging match arm, `None -> core::panic::panic()`, in a generic
function returning T) is p78: `!` is the never type and
`core::panic::panic()` returns it.

Open stdlib needs (owner TBD):
- String equality on `str` elements. `words[0] != "after"` with
  `words: [str; 2]` fails with LNC0006, and docs/compiler-generic-types.md
  calls the operator unsupported. Keyed string containers and parsers need
  it. Repro: tests/fixtures/stdlib_foundation/repro_ordinary_string_comparison.lani
  (expects exit 42; listed in tests/fixtures/known_gaps.txt).
