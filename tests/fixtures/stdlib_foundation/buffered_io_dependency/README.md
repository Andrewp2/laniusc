# Generic stream adapter dispatch

Expected: `main.lani` copies `[1, 2, 3]` through a generic forwarding writer and
`core::io::write_all`, then exits zero. On compiler base `441e66f9`, it reports
LNC0027 at the `writer.write(...)` call inside `stdlib/core/io.lani`.

The adapter has no buffer, allocation, file descriptor or error-handling logic.
It only borrows a writer and forwards Write's two members. Thus this failure
precedes buffered I/O implementation and affects any such generic stream adapter.

| Case | Observed result, 2026-10-22 |
| --- | --- |
| `main.lani`: imported generic adapter, imported generic helper | LNC0027 |
| `direct_control.lani`: direct call to the imported generic adapter | Compiles and exits zero |
| `local_impl_control.lani`: local generic adapter, imported generic helper | LNC0027 |
| `local_control.lani`: local generic adapter and local generic helper | Compiles and exits zero |

The boundary involves generic implementation routing across module contexts;
the diagnostic's broad claim that generic implementations are unsupported is
not accurate for the successful controls. This complements the generic-trait
iterator reproduction in `../iterator_dependency`: Write itself is not generic.

```sh
mkdir -p target/stdlib-work/buffer-probe-root/core
cp stdlib/core/*.lani target/stdlib-work/buffer-probe-root/core/
cp tests/fixtures/stdlib_foundation/buffered_io_dependency/core/buffer_probe.lani \
  target/stdlib-work/buffer-probe-root/core/
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/buffered_io_dependency/main.lani \
  --stdlib-root target/stdlib-work/buffer-probe-root \
  -o target/stdlib-work/buffer_probe
```

Use a distinct output path for each control. Execute a binary only after a
successful compile. The two local controls need only the ordinary `stdlib` root.
No compiler files or production buffering interfaces were changed for this probe.

## Buffered I/O contract awaiting this prerequisite

The planned adapters own a fixed byte buffer and borrow their underlying stream.
Construction validates capacity and reports allocation failure. A reader keeps
unconsumed read-ahead bytes; a writer batches small writes and retains every
unwritten byte when a flush fails after partial progress. Both implement the
existing traits so `read_exact`, `write_all`, `copy` and nested adapters compose.

Finishing a writer must flush successfully before releasing its buffer; a failed
finish preserves pending output for retry or explicit discard. The underlying
stream remains separately owned. Read-ahead discard, pending output, ownership,
zero-length operations and invalid counts need executable state-machine tests.
The design follows the buffering purpose described by Rust's official
[BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html) and
[BufWriter](https://doc.rust-lang.org/std/io/struct.BufWriter.html) documentation,
with explicit Lanius ownership and failure handling instead of automatic Drop.

These are pending requirements, not supported library APIs.
