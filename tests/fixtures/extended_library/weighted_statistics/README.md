# Weighted statistics executable tests

The Lanius producers import the real `ext::weighted_statistics` implementation.
The Python code is an independent test oracle; it does not supply library math.

## Public contracts

`contracts.lani` has five scenario functions covering validated zero weights,
coordinate-before-weight error precedence, reliability versus frequency policy,
equal/scaled weights, exact count and self-merging, late batch rollback,
different native-storage views, read-only aliases, overflow rollback and paired
fits. Paired-specific checks reject each malformed view and unequal coordinate/
weight lengths before reading a nonfinite first row. They also preserve both
marginals when a later candidate Y update overflows.
Both summary types reach the actual 2^53 positive-observation cap through 53
bounded self-merges without enumerating that many observations. Equal
minimum-subnormal weights check effective count for counts one through four.
The executed contract allocation trace is empty.

## Numerical oracle

`model.lani` accepts binary row triples and explicit topological merge-tree
instructions. All calculations use the public APIs. Fixed arrays hold at most
32 rows and 63 summaries. Each output separates operation status/index/count
from eleven typed query results, so a variance overflow or underflow does not
imply a standard-deviation failure. Inputs run in stack arrays and separately
constructed typed native-storage views with different logical offsets. Both
constructions use descending f64 stride on the accepted compiler profile;
these two input modes do not establish positive-stride packed f64 support.

`oracle.py` converts binary64 observations and weights to exact `Fraction`
values. It computes complete weighted sums, centered sums, pair mass and
effective count directly, with 220-digit `Decimal` square roots and derived
correlation/linear-fit references. It does not copy the production recurrence.
Coverage includes every ordered binary merge tree through six rows, larger
left/right/balanced merges, seeded dyadic samples, common weight scaling,
frequency population equivalence, large centers with small spread, opposite
maximum centers, 600-exponent weight imbalance, minimum-subnormal equal weights,
invalid inputs and rejected-operation progress. Query tolerances and the
documented correction-denominator subnormal profile are explicit in the oracle.

The oracle's controls check known exact weighted results and require rejection
of four deliberately wrong answers, including the subnormal rounded-norm
effective-count mistake. They also check error precedence and atomic batch
rejection independently of the executable.

## Executed acceptance

The registered driver compiles the Lanius producers through the GPU compiler
and runs the generated raw x86-64 executables on Linux. It imports the stdlib
and extended-library source roots without a native math implementation.

- `target/stdlib-work/statistics-extension-runtime-final.log`: all three
  weighted-statistics tests passed in 13.07 seconds. This covers 1,908 exact
  model cases across the two input constructions, the independent oracle's
  controls, and the contract producer before the final paired guard additions.
  Model source SHA256:
  `98da9f5fa0ee5468957bf8e810579fed7892d8ab539d33634339619c4b3ebbe5`;
  oracle SHA256:
  `a998451318bf481f9a23905b2167c0559b50b2c5ad4992f1a3998d8739615bfe`.
- `target/stdlib-work/weighted-statistics-paired-contracts-final.log`: the exact
  registered contract test passed in 6.03 seconds after the paired view,
  count-limit and overflow-rollback additions. Its allocation trace contains no
  `mmap`, `mremap`, `munmap` or `brk` calls. Final contract source SHA256:
  `add5015087f6d8688b2185aa0949ed016faf60fc993a470264ccb7643082524b`.

The model and oracle were unchanged between these receipts. No formal accuracy
bound, correct rounding, arbitrary overflow recovery, user-program GPU execution
or formal proof is claimed.
