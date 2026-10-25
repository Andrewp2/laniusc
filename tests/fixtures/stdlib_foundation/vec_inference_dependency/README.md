# Nested vector factory inference

On compiler base `441e66f9`, reproduced 2026-10-23 while adding random batches:

- `nested.lani` fails compilation with LNC0006 at `alloc::vec::with_capacity`.
  The outer `Vec<u64>` annotation does not infer the inner factory's T through
  `core::result::unwrap`.
- `typed.lani` introduces a typed `Result<Vec<u64>, alloc::vec::Error>` local;
  it compiles and exits zero after allocating, storing, reading and destroying.
- `explicit.lani` supplies `with_capacity<u64>(1)` directly inside unwrap;
  it compiles and executes the same checks successfully.

The failing source is a compiler reproduction, outside production library roots.
Do not add a test that requires compilation to keep failing. Applications can use
either successful form without changing the library's generic API. The new batch
fixture uses the typed form. No compiler source was changed.

From the repository root, compile each named fixture independently:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc tests/fixtures/stdlib_foundation/vec_inference_dependency/nested.lani --stdlib-root stdlib -o target/stdlib-work/vec-inference-nested
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc tests/fixtures/stdlib_foundation/vec_inference_dependency/typed.lani --stdlib-root stdlib -o target/stdlib-work/vec-inference-typed
timeout 2s target/stdlib-work/vec-inference-typed
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc tests/fixtures/stdlib_foundation/vec_inference_dependency/explicit.lani --stdlib-root stdlib -o target/stdlib-work/vec-inference-explicit
timeout 2s target/stdlib-work/vec-inference-explicit
```

Execute a control only after its compilation succeeds; a failed compile may leave
an older output file in place.
