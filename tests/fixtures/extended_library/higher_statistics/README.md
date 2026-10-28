# Higher descriptive statistics execution fixtures

These fixtures exercise the public `ext::higher_statistics` accumulator. They
leave the original second-order `ext::statistics` tests unchanged.

- `contracts.lani` checks empty and n=1..4 query domains, zero-spread degeneracy,
  exact two-point values, atomic push/merge/batch failure, a late NaN and late
  fourth-moment overflow, late Underflow, subsequent updates after a rejected
  operation, empty merge identity, self-merge duplication, the exact 2^53 count
  cap, malformed views, current aliased storage and two backing forms. An old
  second-order accumulator control accepts a finite M2 when the new raw M4
  cannot fit. No allocation is permitted.
- `model.lani` is a binary batch adapter. Its eight modes are sequential push,
  one batch, forward and reverse split merges, balanced merge tree, repeated
  singleton merges, self-merge duplication and `summarize`. It reports update
  errors/count plus every public moment/query error or value. Input guard bytes
  and exact input bits are checked after each operation.
- `oracle.py` compares 1,212 cases over 51 datasets and two storage forms.
  Fraction computes exact centered sums directly from the binary64 inputs;
  Decimal supplies square roots and normalization. It does not reproduce the
  streaming/merge recurrence. Data includes symmetric/nearly symmetric shapes,
  repeated values, n boundaries, large centers with small representable spreads,
  scales from 1e-75 to 1e75, a retained positive subnormal M4 and raw-underflow
  rejection. Random inputs use seed `0x48344d2026`.

Both forms use the current descending f64 descriptor: one is a native array,
and one is caller-owned storage viewed through `typed_slice_from_storage`. The
fixtures do not construct or claim a positive-stride f64 ABI. An initial model
startup assertion incorrectly expected the storage descriptor to have stride
+8; the `core::mem` contract specifies -8 for f64, so the fixture was corrected.

The normalized references use:

- `g1 = sqrt(n) M3 / M2^(3/2)`;
- `g2 = n M4 / M2^2`, with population excess `g2 - 3`;
- adjusted skew `sqrt(n(n-1))/(n-2) * g1`;
- adjusted excess `(n-1)/((n-2)(n-3)) * ((n+1)(g2-3) + 6)`.

This finite IEEE binary64 profile rejects a nonconstant update atomically with
`Underflow` when its positive raw M4 rounds to zero, and with `Overflow` when
required finite state cannot fit. Constants with M4=0 remain valid; derived
normalizations are `Degenerate` for zero M2. Positive subnormal M4 is allowed,
with an explicit absolute-rounding budget in the oracle. The tests make no
uniform relative-accuracy claim near underflow or severe odd-moment
cancellation. Error budgets for nearly-zero M3 use the exact sum of absolute
centered third powers rather than relative error against zero.

## Running

After compiling the two sources through the x86 backend:

```sh
strace -qq -e trace=mmap,munmap -e inject=mmap:error=ENOMEM:when=1+ \
  target/stdlib-work/higher-statistics-contracts.elf
python3 -B tests/fixtures/extended_library/higher_statistics/oracle.py \
  target/stdlib-work/higher-statistics-model.elf
```

## Accepted execution receipts

The registered Rust driver `tests/extended_higher_statistics_execution.rs`
passed both runtime tests in 9.54 seconds. The receipt is
`target/stdlib-work/statistics-extension-runtime-final.log`. Its build receipt,
`target/stdlib-work/statistics-extension-driver-build.log`, records 2.45 seconds.
The accepted sources are contracts `02dde616`, model `e3723d35`, higher moments
`3f224ad3` and its scaling dependency `775960e8`.

The model test executed 1,212 comparisons over 51 datasets, two descending f64
storage forms and eight accumulation/merge modes. The contract test executed
all normal, error, rollback, Underflow, count and borrowed-storage assertions
with mmap denied; its allocation trace was empty. The direct model run also
passed in `target/stdlib-work/higher-statistics-model-native-storage-fix.log`.
These are actual executable checks. The separate CPU oracle self-check and
corrupted-kurtosis rejection establish only reference/protocol-verifier signal.

The initial startup SIGILL came from this fixture's incorrect +8 stride
assertion, corrected to the documented -8; it was not a compiler or statistics
failure. No compiler change was made for it.

Expected host execution is Linux x86_64. The library source uses no host math or
allocation; these fixtures establish no GPU execution or formal proof.
