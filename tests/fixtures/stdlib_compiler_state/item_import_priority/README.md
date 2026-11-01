# Item-import priority with colliding function names

The [item-import contract](../../../../docs/language-ergonomics.md#item-imports)
states that an item import beats module imports for its name. The graph-walk
application exposed a current limitation when importing the generic slice
`view` alongside the sparse module's different `view` function.

`reject_selected.lani` explicitly imports `core::slice::view`, then calls
`view(cells,1)` in an explicitly typed context. The current compiler rejects
that call with `LNC0006`. The original application's chained expression
reported `LNC0027` instead. These diagnostics do not establish a problem with
CSR storage or computation; the library runtime tests use qualified calls.

`qualified.lani` has the same imports and input, but calls
`core::slice::view(cells,1)`. It compiles and executes, checking the value 7.
The application uses qualified slice functions with `import core::slice;`;
removing the item import without importing that module leaves the function
unavailable and is not a valid repair.

Current checks, each bounded independently:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_compiler_state/item_import_priority/reject_selected.lani \
  --stdlib-root stdlib --source-root extended --emit x86_64 \
  -o target/stdlib-work/item-import-selected

timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_compiler_state/item_import_priority/qualified.lani \
  --stdlib-root stdlib --source-root extended --emit x86_64 \
  -o target/stdlib-work/item-import-qualified

timeout --kill-after=2s 20s flock -w 15 target/stdlib-work/library-gpu.lock \
  target/stdlib-work/item-import-qualified
```

The first exits 1; both qualified-control commands exit 0. Receipts are
`item-import-selected.log`, `item-import-qualified.log` and
`item-import-qualified-native.log` under `target/stdlib-work/`. They establish
native Linux x86_64 behavior from the GPU compiler. No compiler, ABI or proof
source was changed. This is a diagnostic reduction; no test requires the
documented import form to keep failing after a compiler repair.
