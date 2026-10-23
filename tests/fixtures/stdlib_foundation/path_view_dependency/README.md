# Direct malformed View construction

On compiler base `441e66f9`, `inline.lani` reports LNC0017 with unsupported target
LIR opcode 31 at the `core::slice::View` literal. It supplies a native byte array
directly to the slice field of the imported generic record, with a negative
start, then calls `core::path::from_view`. This is a reduced construction failure;
it does not establish the compiler's internal root cause.

`from_view.lani` constructs the same one-byte view through `core::slice::view`,
sets its start to -1, and executes the expected Bounds result. It is included in
the normal path execution suite. Production path construction remains through
the checked byte/range/view APIs; no compiler implementation changes are made.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/path_view_dependency/inline.lani \
  --stdlib-root stdlib -o target/stdlib-work/path-view-inline
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/path_view_dependency/from_view.lani \
  --stdlib-root stdlib -o target/stdlib-work/path-view-control
timeout --kill-after=2s 10s target/stdlib-work/path-view-control
```

The first command is expected to fail compilation; run an executable only after
its compilation succeeds. The control compiles and exits zero on x86_64 Linux.
