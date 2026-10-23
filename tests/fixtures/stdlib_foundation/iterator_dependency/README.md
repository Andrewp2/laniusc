# Imported generic iterator dispatch

Expected: `main.lani` compiles and exits zero. On compiler base `441e66f9`,
the generic-bound call `source.next()` reports LNC0027. The imported module
contains only a generic trait, a generic cursor and its implementation.

Two controls compile and exit zero:

- `direct_control.lani` calls the same imported implementation directly.
- `local_control.lani` uses a generic-bound call with a local implementation.

The boundary is the combination of imported generic implementation and
generic-bound member dispatch. The diagnostic's claim that generic
implementations are unsupported is too broad; the local control works.
All three cases were compiled and the successful controls executed on
x86_64 Linux on 2026-10-22.

Load the probe as a standard-library module:

```sh
mkdir -p target/stdlib-work/iterator-repro-stdlib
cp -r stdlib/core target/stdlib-work/iterator-repro-stdlib/
cp tests/fixtures/stdlib_foundation/iterator_dependency/core/pull_probe.lani \
  target/stdlib-work/iterator-repro-stdlib/core/
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/iterator_dependency/main.lani \
  --stdlib-root target/stdlib-work/iterator-repro-stdlib \
  -o target/stdlib-work/iterator_repro
```

Substitute either control filename and a separate output path to run the
controls. Execute a binary only after its compilation succeeds.

`prototype/` preserves the proposed `Iterator<T>`, borrowed `Take<I,T>` adapter,
and nested-adapter client. These are **unverified prototypes**, outside the
production stdlib root. The adapter fails even with a single `Take` and after
borrowing its source field into a typed local. Shared adapters, generic consumers
and collection integration remain pending. The production slice and text
cursors expose inherent methods; their execution does not establish support for
this shared protocol. No compiler implementation is changed here.
