# Formatter corrupts negative exponents

## Historical observation

Observed on 2026-10-23 with the compiler built from base `168065b9`.
No compiler source changed during this library milestone.

`input.lani` compiles and its emitted x86_64 Linux executable exits 0.
Formatting it through `fmt --stdin` exits 0 and emits `observed.lani`, changing
the numeric literal `1e-15` into `1e - 15`. The formatted source fails compilation
with LNC0046. `fmt --check` nevertheless accepts that formatted source and exits
0. `observed.stderr.txt` preserves the exact compiler diagnostic from the
temporary observation path.

Historical reproduction with that baseline compiler, from the repository root;
each command is bounded separately:

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

## Formatter closeout

The failure was reproduced again before the repair in the worktree based on
`1602e5bbd48a44fdeacf2ebf753285465a52260e`: CPU-only `fmt --stdin` returned 0
and split `1e-15`; checking that output also returned 0. The original snapshots
above remain unchanged. No new native compile or GPU execution was needed;
the preserved native control already establishes that the input is supported.

The formatter's word scanner consumed `1e`, then its ordinary minus-spacing rule
emitted ` - ` before `15`. A decimal float scanner now retains the complete
mantissa/exponent spelling as one lexical unit, including `e`/`E` and exponent
`+`/`-`. Leading-dot and trailing-dot mantissas and digit separators are retained.
Adjacent subtraction, radix integers, identifiers, range dots, comments and
quoted text keep their own token boundaries. The production edit is confined
to `crates/laniusc-compiler/src/formatter.rs`; no compiler parser, IR, ABI or
formal contract changed.

`fmt --check` already compares the complete input with the formatter's output.
It remains a canonical-format check, not semantic or syntax validation. The old
corrupted output was a stable formatter result; accepting it did not establish
that it was valid Lanius. The formatter cannot infer that an existing `1e - 15`
was intended to be `1e-15`, and does not reconstruct that spelling.

Current CPU regressions compare independent lexer token kinds **and complete
token spellings** before/after formatting, including comments and quoted text.
Removing whitespace for comparison would miss this particular corruption.
Coverage includes positive, negative and unsigned exponents; both marker cases;
fractional mantissas; separators; unary minus and adjacent subtraction; radix
integer controls; range dots; the exact original source; and second-pass
idempotence. The CLI regression verifies file and stdin check failures for the
unformatted original, no file mutation during checking, preserved exponent
tokens in the rewrite, and successful file/stdin checks of that rewrite.

Verification: the four new exponent/token regressions first failed against the
old formatter. After the repair, all 17 CLI formatter tests and the then-16
formatter tests passed. One additional exact range-boundary control then passed
(17 formatter tests in the final source). These tests use CPU lexer oracles;
they do not add a CPU parser/compiler fallback or infer native execution from
formatting success. Logs are retained under the ignored
`target/stdlib-work/format-negative-exponent-1602e5bb/` directory.

Run the focused CPU-only formatter targets:

```sh
timeout --kill-after=2s 100s env \
 CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
 CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
 cargo test --test formatter --test cli_formatter -- --nocapture
```
