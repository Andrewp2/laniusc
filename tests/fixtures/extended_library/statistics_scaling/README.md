# Statistics scaling kernel execution fixtures

These tests call all six `ext::statistics_scaling` helpers. Production
arithmetic remains in Lanius; Python supplies an independent test reference
and binary transport.

- `contracts.lani` checks exact dyadic results after intermediate overflow or
  underflow would lose range, subnormal normalization, final infinity and
  round-to-even underflow, all zero-sign combinations, and invalid inputs at
  every argument position. Nonfinite inputs and zero denominators must return
  NaN even when an earlier numerator is zero.
- `model.lani` reads a little-endian binary batch: one `u64` case count, then
  one `u64` operation number and six binary64 bit patterns per case. Operations
  0 through 5 select `product3`, `product5`, `quotient2`, `quotient4`,
  `quotient5` and `quotient2_2`. Unused slots contain 1.0. Output is one
  binary64 bit pattern per case. The test program caps batches at 8,192 cases.
- `oracle.py` generates 1,926 deterministic cases with seed
  `0x5343414c45323026`. It computes mathematical products and quotients with
  `Fraction.from_float`, without reproducing exponent extraction, normalization
  or the production mantissa mask. Exact dyadic and single-factor recovery
  cases require bit equality. General products allow eight ULP and relative
  error at most `9 * 2^-53`, plus half a minimum subnormal for final rounding.
  A narrow overflow-edge allowance accounts for intermediate rounding. Sign
  and invalid-input classification are checked separately.

Selected exponent/fraction patterns, both signs, subnormal denominators,
large cancelling exponent sums and random full-range factors cover the
numerical kernel. This test is not a claim of fused or correctly rounded
arbitrary products. Helpers accept scalar factors, so no caller slice-layout
contract is implied.

The Rust driver is
[`extended_statistics_scaling_execution.rs`](../../../extended_statistics_scaling_execution.rs).
Both registered tests passed in 7.31 s in
`target/stdlib-work/statistics-extension-runtime-final.log`. The shared driver
build completed in 2.45 s; its receipt is
`target/stdlib-work/statistics-extension-driver-build.log`.

Direct runs also passed: the contract receipts are
`target/stdlib-work/statistics-scaling-contracts-compile-first.log` and
`target/stdlib-work/statistics-scaling-contracts-native-first.log`; the model
receipt is `target/stdlib-work/statistics-scaling-model-native-first.log`.
The direct model and registered driver execute the same 1,926-case corpus,
including 1,122 cases marked for exact comparison. These are repeated receipts
for that finite corpus, not distinct additional cases. Maximum observed ULP
distances for general cases were:

| Helper | Maximum observed ULP |
| --- | --- |
| `product3` | 1 |
| `product5` | 2 |
| `quotient2` | 1 |
| `quotient4` | 2 |
| `quotient5` | 2 |
| `quotient2_2` | 1 |

Executed source SHA-256 values:

| Source | SHA-256 |
| --- | --- |
| `extended/ext/statistics_scaling.lani` | `775960e8b101a374da8e1bc907cc999a7b1ab8d4839f34d016c5f3b5f8a18c5e` |
| `contracts.lani` | `0aedd70305b0dae961bd63504792d6bca054ddd5ee02fa76309dbe7f79f351db` |
| `model.lani` | `9764b233fede93304254a93823ff0d25bf86ef19386c2215966a754a8df4cb70` |
| `oracle.py` | `77d97831af789d5361ad6c72724179d000be79eea77f831e55f53634d7400375` |

The CPU-only oracle self-check passed 1,926 reference-output cases and six
deliberately wrong-output controls. This is a test-harness check, not execution
of Lanius. It verifies that the checker rejects exponent loss, a wrong mantissa,
lost zero signs, early-zero validation and intermediate range loss.

Direct exact-rational comparison command after compiling the model:

```sh
python3 -B tests/fixtures/extended_library/statistics_scaling/oracle.py \
  target/stdlib-work/statistics-scaling-model.elf
```

The executable fixtures currently target Linux x86_64. No GPU runtime or
formal-verification result is established by these checks.
