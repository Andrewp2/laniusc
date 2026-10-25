# Comparison compiler dependencies

These failing reductions are outside the passing library surface. They were
reproduced on 2026-10-23 without editing compiler/runtime code. The adjacent
controls execute on x86_64 Linux. See `docs/library-dependencies.md` and
`docs/stdlib-comparison.md` for affected APIs and supported call forms.

| Entry | Standard library root | Result |
| --- | --- | --- |
| `blanket-partial.lani` | Adjacent `blanket-root` | LNC0027 on bound dispatch through a conditional generic implementation. |
| `generic-partial-cmp-match.lani` | Repository `stdlib` | LNC0006 when matching an associated generic call directly. |
| `generic-partial-cmp-match-control.lani` | Repository `stdlib` | Typed intermediate result; compiles and exits 0. |
| `generic-record-vec-at.lani` | Repository `stdlib` | Compiles; native execution receives SIGSEGV. |
| `generic-record-vec-slice-control.lani` | Repository `stdlib` | Changes only element extraction to a typed slice/index; exits 0. |

Run from the repository root, choosing one entry at a time, for example:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib \
  tests/fixtures/stdlib_compiler_state/comparison/generic-partial-cmp-match-control.lani \
  -o target/stdlib-work/comparison-control
timeout --kill-after=2s 10s target/stdlib-work/comparison-control
```

For the blanket entry, set `--stdlib-root` to
`tests/fixtures/stdlib_compiler_state/comparison/blanket-root`.
Failed compilations produce no executable support claim. Run the Vec.at
reduction only when investigating the crash; it is not a success test.

The Vec.at reduction uses a total float wrapper, but a plain one-field `u32`
record also reproduces the crash against the archived `5bbdc70f` stdlib. Direct
concrete wrapper `at`/`get`, generic typed-slice extraction, actual vector sort
and search, tree/hash maps and set identity pass in
`tests/stdlib_comparison_execution.rs`. This identifies a preexisting generic
composition limitation without establishing its compiler root cause.
