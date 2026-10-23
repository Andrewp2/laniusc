# Generic set-to-map composition

Current revalidation at `8cb1af7b` still fails for both `HashMap<T, Unit>` and
`TreeMap<T, Unit>` generic set wrappers. Direct controls for both maps compile
and execute. See [the current minimized evidence](../../stdlib_compiler_state/owned_sets/README.md)
for exact diagnostics, source/compiler hashes, and bounded commands. The
prototype below remains unverified.

Expected: compile `main.lani` and exit zero. With the compiler built from
`441e66f9`, it reports LNC0047: a replay argument has no complete GPU native
layout. The diagnostic points at `alloc::allocator`; the direct map APIs execute.

The reduced `alloc/probe_set.lani` wraps `HashMap<T, Unit>` inside `Set<T>`
and forwards insertion through a borrowed receiver. There are 21 lines of
wrapper code and ten lines of client code. The full set wrapper also failed
when its underlying map used `HashMap<T, bool>`; the observed boundary is not
limited to a zero-sized or private payload.
In contrast, direct client use of `HashMap<i32, Unit>` compiles and executes
(covered in `../alloc_hash_types.lani`).

Load these dependencies as **stdlib**, preserving the failing classification:

```sh
mkdir -p target/stdlib-work/hash-set-repro-stdlib/alloc
cp -r stdlib/core target/stdlib-work/hash-set-repro-stdlib/
cp stdlib/alloc/allocator.lani stdlib/alloc/hash_map.lani \
  target/stdlib-work/hash-set-repro-stdlib/alloc/
cp tests/fixtures/stdlib_foundation/hash_set_dependency/alloc/probe_set.lani \
  target/stdlib-work/hash-set-repro-stdlib/alloc/
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/hash_set_dependency/main.lani \
  --stdlib-root target/stdlib-work/hash-set-repro-stdlib \
  -o target/stdlib-work/hash_set_repro
```

The full proposed `alloc::hash_set` implementation and its intended contract/
allocation fixtures are retained here as `alloc/hash_set.lani`,
`set_contracts.lani`, and `set_allocation_failure.lani`. They are **unverified
prototypes**, excluded from the production standard-library source root and
passing test claims. The boolean-payload experiment did not resolve the
failure; the prototype retains its intended empty marker.

The set contract fixture exhaustively compares union, intersection, difference,
symmetric difference, subset and disjointness for all pairs of subsets of a
five-element universe, then tests copies and removal. These checks still need
to run after compiler support is repaired. No compiler code is changed here.
