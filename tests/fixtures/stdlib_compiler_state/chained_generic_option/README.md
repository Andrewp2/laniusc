# Generic Option receiver resolution

The exact-size sequence fixture exposed a compiler method-resolution limit.
The reduction uses only the existing Iterator and Option APIs:

```lani
fn present<I,T>(source:&I) -> bool where I:core::iter::Iterator<T> {
    return source.next().is_some();
}
```

`reject_chained.lani` currently reports `LNC0027` at `is_some`. The equivalent
`typed_local.lani` assigns the returned value to `Option<T>` before querying
it. That control compiles and executes, including a successful first pull and
exhaustion on the second pull. This establishes a narrow receiver-resolution
dependency, not a failure of generic Option storage or exact-size traversal.

Both were checked with the current GPU compiler and Linux x86_64 CPU output:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_compiler_state/chained_generic_option/reject_chained.lani \
  --stdlib-root stdlib --emit x86_64 -o target/stdlib-work/chained-generic-option-reject

timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_compiler_state/chained_generic_option/typed_local.lani \
  --stdlib-root stdlib --emit x86_64 -o target/stdlib-work/chained-generic-option-control

timeout --kill-after=2s 20s flock -w 15 target/stdlib-work/library-gpu.lock \
  target/stdlib-work/chained-generic-option-control
```

The first command exits 1 with the diagnostic; the control commands exit 0.
Receipts are `chained-generic-option-reject.log`,
`chained-generic-option-control.log` and
`chained-generic-option-control-runtime.log` in `target/stdlib-work/`.
The library model uses the typed local with unchanged pull and assertion
behavior. No compiler production source was changed. This reduction is
diagnostic material; compiler repair should make the chained spelling work,
and no test requires that limitation to remain.
