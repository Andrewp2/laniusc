# Heap migration to alloc::vec

`binary_heap.lani` is the attempted migration of the working heap to the new
borrowed-owner vector API. It delegates reserve, push, bulk extension, clone and
shrink through explicit Results, and obtains counted views from Vec directly.
It is a compiler reproduction, outside the production stdlib root.

On 2026-10-22, the ten-line `main.lani` failed with LNC0047 against this
implementation. The diagnostic points to `core::cmp` and says a replay argument
has no complete GPU native layout. The same entry compiles and exits zero with
the production heap backed by `std::vec`. The attempted migration also failed
the existing heap contracts, stateful model and allocation-failure fixtures;
its top-scores and large-construction cases compiled and ran. Those successes
do not establish a working migration.

This failure remains after the independent nested-view-factory issue is avoided
by direct Vec view construction. Its exact compiler cause is not established.
No compiler or proof code was changed. The production heap retains the earlier
implementation until this dependency can be resolved.

Prepare a fresh copy of the current stdlib and replace only the heap module:

```sh
timeout --kill-after=2s 10s cp -R stdlib target/stdlib-work/vec-heap-repro
timeout --kill-after=2s 10s cp \
  tests/fixtures/stdlib_foundation/vec_heap_dependency/binary_heap.lani \
  target/stdlib-work/vec-heap-repro/alloc/binary_heap.lani
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/vec_heap_dependency/main.lani \
  --stdlib-root "$PWD/target/stdlib-work/vec-heap-repro" \
  -o target/stdlib-work/vec-heap-repro-program
```

Use a new destination for each preparation. Expect LNC0047; do not execute the
output after failed compilation. Compile the same entry with `--stdlib-root
stdlib` for the working control, then execute that successful output under a
ten-second timeout. The source entry only constructs a min-heap, pushes one i32,
checks its length and destroys it.
