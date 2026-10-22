# Stdlib generic helper composition

Expected: compile and exit zero. Current compiler built from `441e66f9` reports
LNC0047, detail 6: a replay argument has no complete GPU native layout.

`core/io.lani` preserves the original stream-copy composition: a generic copy
operation calls a generic complete-write helper, whose error is a nominal
record in the same module. The ordinary client uses a small record implementing
both stream traits. There are no host calls or allocations in this reproduction.

The library classification matters. Loading these sources through `--source-root`
as user modules compiles; load all four dependencies as **stdlib** to reproduce:

```sh
mkdir -p target/stdlib-work/repro-stream-stdlib/core
cp stdlib/core/cmp.lani stdlib/core/result.lani stdlib/core/panic.lani \
  target/stdlib-work/repro-stream-stdlib/core/
cp tests/fixtures/stdlib_foundation/stream_copy_dependency/core/io.lani \
  target/stdlib-work/repro-stream-stdlib/core/io.lani
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/stream_copy_dependency/main.lani \
  --stdlib-root target/stdlib-work/repro-stream-stdlib \
  -o target/stdlib-work/repro-stream-copy
```

Adding `LANIUS_DEBUG_INSTANCE_CLOSURE=1 LANIUS_DEBUG_STAGE_ERRORS=1` to the
compiler's environment prints the generic closure and rejection detail.

The production `core::io::copy` handles short writes directly in its copy loop.
That implementation retains the same public contracts and executes for native
descriptors, slice streams and owned byte buffers. It does not establish that
the compiler's nested generic composition has been repaired. The runtime suite
is `tests/stdlib_stream_execution.rs`.
