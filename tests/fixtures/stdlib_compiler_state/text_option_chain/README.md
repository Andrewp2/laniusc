# Generic chained Option method resolution

The first remaining bidirectional Text test run observed LNC0027 at
`source.next().is_none()` and `source.next_back().is_none()` inside generic
helpers bounded by the shared iterator traits. Both original fixtures already
imported `core::option`; an omitted Option import does not explain those
observations. No compiler root cause is established.

The exact original diagnostics are in
`target/stdlib-work/text-bidirectional-direct-final.log`. That run took
7.59 seconds: the intended ExactSize rejection group passed, while the two
positive fixtures failed to compile and never executed. Replacing only the
exhaustion helpers with typed `Option<T>` locals and direct matches preserved
generic traversal/call order and produced two native passes in 7.99 seconds:
`target/stdlib-work/text-bidirectional-direct-revised.log`.

## Reduced pair

- `chained.lani` retains the failing expression in a generic Iterator helper.
- `typed_match.lani` uses an explicitly typed Option local and direct match.

Both import the same modules, construct the same zero-length `Iter<i32>` over
actual one-element backing, and call the same generic helper instantiation.
Using the slice cursor avoids introducing a zero-sized `Empty<T>` return into
the reduction. Root executed this reduced pair on the native Linux x86_64
GPU-compiler profile; its observed result is below.

`tests/stdlib_text_bidirectional_execution.rs` includes the ignored,
positive-expected test
`generic_chained_option_executes_like_explicit_match_on_bounded_slice_cursor`.
It compiles and actually executes the typed control first, then requires the
chained case to compile and execute too. Each success has strict ELF/shared
jump checks and a complete no-host-effects trace. The test fails while the
compiler limitation persists; it does not treat the broken behavior as an
expected success. Root runs this probe explicitly under the existing serial
compiler lock and command deadline.

## Observed reduced result

`target/stdlib-work/text-option-chain-dependency.log` records the explicit
ignored-gate run: **0 tests passed, 1 failed**, in **4.79 seconds**, after a
separate **1.69-second Rust build**. Within that one test:

1. `typed_match.lani` compiled, passed strict ELF/shared jump validation,
   executed successfully and passed its complete pure syscall trace.
2. `chained.lani` failed compilation with **LNC0027**, “call resolution failed,”
   at **line 7, column 26**, on `is_none` in
   `assert(source.next().is_none());`. The diagnostic reports that the call
   does not match a resolved function or method. It did not execute.

The successful control does not make the overall test a pass. The positive
expectation is retained so a compiler repair must compile and execute both
forms. This finite observation isolates the expression-shape difference for
`Iter<i32>` under an `Iterator<T>` bound with explicit imports; it does not
establish the compiler's internal root cause or behavior for arbitrary types.

To rerun the built probe from the repository root, using the executable
recorded in that receipt:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_text_bidirectional_execution-1b0b053b8c5e5aab \
  --exact generic_chained_option_executes_like_explicit_match_on_bounded_slice_cursor \
  --ignored --test-threads=1 --nocapture
```

This command currently exits unsuccessfully at the chained case. The binary
name is specific to the observed build; use the corresponding test executable
reported by a subsequent build if its artifact hash changes. Other targets,
user-program GPU execution and unrelated chained generic calls were not
established by this probe.

## Frozen sources

| Source | SHA-256 |
| --- | --- |
| `tests/stdlib_text_bidirectional_execution.rs` | `c3ae5c1ea8b642b767b5707f5a6337099e72c094cb7ba5ea2fd45cfb3332cdfa` |
| `chained.lani` | `037c6e9062108400903b1de89b1111cf47960dfb1f1e98eed45659d618c21cbc` |
| `typed_match.lani` | `4156cbc7d4aa58ac585d2c939bcd960e6d876bfefa9c822bcb09339742ed24c3` |

No production library, compiler, ABI or proof change was made for this
workaround. This record is evidence about these expression shapes, not a claim
that generic Option operations or imported iterators fail generally.
