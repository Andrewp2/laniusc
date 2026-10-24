# Empty destructor body control

These are isolated compiler admission controls, not production API workarounds
or tests requiring compilation to keep failing.

In the controlled run before the unit-body repair, both sources had
the same nonzero `Local { value:i32 }`, error type, protocol implementation,
imported generic clone/destruction calls and assertions. The only semantic-source
difference is `Destroy::destroy_value`'s body:

- `leaf_entry.lani`: `{}`. Compilation stops with LNC0017, native function has no
  emitted definition: library1, unit1, declaration2147483687, relocation11.
- `leaf_entry_return.lani`: `{ return; }`. Compilation succeeds, the unchanged
  shared x86 checker passes, and native execution exits0. Trace records one
 16-byte outer mapping followed by its matching successful unmap.

Compile each entry with this command, selecting a fresh output/log:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/clone_fixture/ENTRY.lani \
  --stdlib-root stdlib -o OUTPUT
```

The logs are `leaf-entry-empty-control.log` and `leaf-entry-return-control.log`
under `target/stdlib-work/clone-production/`; the passing native trace is
`leaf-entry-return-control.trace`. That directory also preserves the exact
compiler binary/version, source/checker hashes and emitted passing executable.
`entry-body-before.sha256` records the CLI and source hashes. The CLI loads
external SPIR-V artifacts; its binary hash alone does not pin the shader
generation or reproduce the historical failure. The
[repair and durable regression](../../../../docs/compiler-unit-body-contract.md)
record current executable acceptance separately.
No production clone source was changed to add artificial return statements.
