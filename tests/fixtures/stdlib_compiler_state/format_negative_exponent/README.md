# Formatter corrupts negative exponents

Observed on 2026-10-23 with the compiler built from base `168065b9`.
No compiler source changed during this library milestone.

`input.lani` compiles and its emitted x86_64 Linux executable exits 0.
Formatting it through `fmt --stdin` exits 0 and emits `observed.lani`, changing
the numeric literal `1e-15` into `1e - 15`. The formatted source fails compilation
with LNC0046. `fmt --check` nevertheless accepts that formatted source and exits
0. `observed.stderr.txt` preserves the exact compiler diagnostic from the
temporary observation path.

From the repository root, each command is bounded separately:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib \
  tests/fixtures/stdlib_compiler_state/format_negative_exponent/input.lani \
  -o target/stdlib-work/negative-exponent-control
timeout --kill-after=2s 10s target/stdlib-work/negative-exponent-control
timeout --kill-after=2s 10s target/stdlib-build/debug/laniusc fmt --stdin \
  < tests/fixtures/stdlib_compiler_state/format_negative_exponent/input.lani \
  > target/stdlib-work/negative-exponent-formatted.lani
timeout --kill-after=2s 10s target/stdlib-build/debug/laniusc fmt --check \
  target/stdlib-work/negative-exponent-formatted.lani
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib target/stdlib-work/negative-exponent-formatted.lani \
  -o target/stdlib-work/negative-exponent-formatted
```

The last command is the expected compilation failure. The preceding native
control establishes that the input literal is supported. This observation does
not establish other formatter or numeric parsing failures. Library sources can
spell small constants in decimal; `tools/lanius-test` compiles saved source
without invoking the formatter.

SHA-256 of the retained source snapshots:

| File | SHA-256 |
| --- | --- |
| `input.lani` | `e8c08a79f0b22f6c1d32ad891b355ba3737404a27c23486dcb0e4c08d72307c4` |
| `observed.lani` | `069b161307295523f74f0da6a8c696d7d7baad01c83d3d7eb7fd33651db5d1e3` |
