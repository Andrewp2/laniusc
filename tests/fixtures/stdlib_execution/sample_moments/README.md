# Numerical CSV summary application

The fixture independently models the exact binary64 parsed inputs using Python
`Fraction` central sums and 110-digit `Decimal` square roots/ratios. It compares
all 24 metrics, exact profile/name ordering, explicit undefined statuses, finite
numeric output and canonical fully quoted CRLF CSV. The model has no production
streaming recurrence or memory tracker.

| Group | Cases | Contract |
| --- | ---: | --- |
| model | 26 | Empty/all-zero, one/two/three observations, constant data, three minimum-subnormal weights, unit/unequal/scaled weights, ignored finite zero-weight outliers, signed zero, decimal underflow-to-zero, skewed and shifted data, 4096 rows, exact 1 MiB input, eight seeded samples |
| rejection | 30 | 26 CSV/schema/number/weight/limit rejections, then four numerical failures: weighted overflow, fourth-moment overflow, total-weight overflow and positive fourth-moment underflow |
| cli | 8 | Invalid operands/options/duplicate help and both help forms; help bypasses stdin |
| io | 2 | Actual stdin directory read error and closed stdout reader |

Count, total weight and extrema require exact binary64 equality to the rounded
reference. This makes tiny positive total weights distinguishable from zero.
For other defined metrics, absolute tolerance is the larger of `1e-12` and 512 ULPs
at the independent reference value rounded to binary64. Undefined values must
be empty with their exact status; NaN and infinity never satisfy a comparison.
The tolerance permits floating arithmetic while exposing profile mixups,
incorrect weight denominators, wrong central powers and adjustment factors.

Seven CPU-only controls validate hand-computable profile differences,
effective count, reliability variance, empty statuses and literal lengths.
They are separate from native application acceptance.

```sh
python3 -B tests/fixtures/stdlib_execution/sample_moments/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/sample_moments/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sample_moments/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sample_moments/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sample_moments/oracle.py io PATH_TO_ELF
```

Each native child has a 20-second timeout; the Rust driver has an 85-second
group timeout. The Python implementation is test-only.

## Accepted application evidence

The registered Rust driver compiled the Linux x86_64 application, passed the
shared strict ELF checker and passed all four tests on 2026-10-28. The cases
are model 26, rejection 30, CLI 8 and I/O 2: 66 finite application cases, separate
from the underlying modules' broader numerical models.

Runtime receipt: `target/stdlib-work/statistics-extension-runtime-final.log`
(application test suite: 9.87 seconds). Build receipt:
`target/stdlib-work/statistics-extension-driver-build.log` (2.45 seconds).
Registered evidence directories: `/tmp/sample-moments-model-y3awkzjl`,
`/tmp/sample-moments-rejection-upoxq9o2`, `/tmp/sample-moments-cli-200vm0i5`
and `/tmp/sample-moments-io-enea7v4r`.

Application source SHA-256:
`cdf6dcdfdd4fea27753fd32c31f4910d000737038c824bad485076bc542cde66`.
Oracle SHA-256:
`0d92191011f4ad258022255dc0518745373805550585c2f8d6c228e36e96a88c`.
Accepted dependency SHA-256 values:

- `weighted_statistics.lani`: `d3cea094113a28d375214657e8cda170997fcb70cbb4d7fccca638abfb8e2d61`
- `higher_statistics.lani`: `3f224ad3e1b55640d4a5bf621b4d2382c0902772f8a20c71e4dd5f64b8ab0937`
- `statistics_scaling.lani`: `775960e8b101a374da8e1bc907cc999a7b1ab8d4839f34d016c5f3b5f8a18c5e`

The model includes three `7,5e-324` rows after the weighted module repaired
its subnormal effective-count query. Total weight must round to three minimum
subnormals, effective count must be three, and the unweighted-positive profile
must contain three constant observations. Exact total-weight comparison avoids
accepting zero under a broad absolute tolerance.

The retained raw executable was separately rebuilt against these same final
dependencies and also passes all 66 cases. Its SHA-256 is
`b0ff96218219214213199979a7b00c320e622c3e7fda101142edc92137663745`.
Receipts under `target/stdlib-work/` are `sample-moments-compile-final.log` and
`sample-moments-{model,rejection,cli,io}-native-final.log`. Direct evidence
directories are `/tmp/sample-moments-model-l1zd8kwg`,
`/tmp/sample-moments-rejection-ofm0bmr_`, `/tmp/sample-moments-cli-bwo38imw`
and `/tmp/sample-moments-io-bm6wdjk7`. The registered executable is a separate
producer; binary hashes are not assumed equal and repeated cases are not added
as distinct coverage.

No allocation-failure, leak-freedom, GPU execution or formal verification claim
is made by these functional fixtures.
