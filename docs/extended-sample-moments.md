# Weighted and higher moments from CSV

`sample_programs/library/sample_moments.lani` reads numerical CSV through EOF,
validates it, computes two explicitly labelled summaries and publishes one
staged CSV table:

```sh
sample-moments [--help] < samples.csv
printf 'value,weight\n1,1\n3,3\n' | sample-moments
```

The input header must contain exactly `value,weight`, in that order and case.
Quoted header fields are allowed. Every data record has exactly two fields.
Numbers use the existing binary64 decimal parser with no surrounding
whitespace. Values and weights must parse to finite binary64 numbers, and
weights must be nonnegative. Signed zero weights are zero. Decimal values
that round to binary64 zero follow the same zero rules.

The full CSV and every number are validated before statistics are updated.
That includes values in zero-weight rows: a NaN, infinity or malformed value
still rejects the input. Zero weights then contribute to neither profile.
Header-only input and all-zero weights are valid.

## Profiles and output

Output fields are `profile,metric,value,status`. Every field is quoted by the
CSV writer and every record ends with CRLF. There are 24 metric rows plus the
header, in the following order:

| Profile | Metrics |
| --- | --- |
| `weighted` | `count`, `total_weight`, `effective_count`, `mean`, `minimum`, `maximum`, `m2`, `population_variance`, `population_stddev`, `reliability_variance` |
| `unweighted_positive` | `count`, `mean`, `minimum`, `maximum`, `m2`, `m3`, `m4`, `population_variance`, `population_stddev`, `population_skewness`, `population_kurtosis`, `population_excess_kurtosis`, `adjusted_skewness`, `adjusted_excess_kurtosis` |

`weighted` uses `ext::weighted_statistics::Moments` with the supplied weights.
`count` counts positive-weight rows. With total weight `W`, reliability variance
uses the denominator `W - sum(weight²)/W`; effective count is
`W²/sum(weight²)`. Positive-weight extrema use the original values.

`unweighted_positive` uses `ext::higher_statistics::Moments`. Each row with
positive weight contributes its value exactly once. The magnitude of the
weight does not affect this profile. Thus input `1,1` and `3,3` has weighted
mean 2.5 and unweighted-positive mean 2. The profile label makes that distinction
visible in every metric row.

`m2`, `m3` and `m4` are sums of centered powers; population moments divide by
the positive-row count in the unweighted profile. Kurtosis is the normalized
fourth moment; excess kurtosis subtracts three. The adjusted statistics apply
their library sample-size corrections. Algorithms and query contracts live
in the weighted/higher statistics modules; the application composes those APIs.

| Status | Value cell | Meaning |
| --- | --- | --- |
| `ok` | Finite decimal | Defined result |
| `empty` | Empty | No positive-weight observation for the query |
| `insufficient` | Empty | Too few observations or no usable reliability divisor |
| `degenerate` | Empty | Shape statistic has zero spread |

Both profile counts and weighted total weight remain defined as zero for empty
or all-zero input. Empty weighted reliability variance is `insufficient`.
Adjusted skewness requires three positive rows and adjusted excess kurtosis
requires four; their insufficient-size check precedes the zero-spread check.
Constant data otherwise has zero variance and zero raw centered powers, with
undefined normalized shape statistics explicitly marked `degenerate`.

Any other numerical library error, a nonfinite metric, or inability to format
a result aborts the entire output with exit 6. This includes overflow and
reported positive-moment underflow. No NaN or infinity is published and no
failed metric is silently replaced with zero. Output is fully encoded before
the first stdout write; a later write failure can still publish a prefix.

## Bounds, ownership and status

| Resource | Bound |
| --- | ---: |
| Raw input / data rows | 1 MiB / 4096 |
| Total CSV records / fields per record | 4097 / 2 |
| Numeric field / decoded record content | 128 / 256 bytes |
| Decimal digits / conversion work per input number | 128 / 1000000 |
| Decimal formatting work per result | 1000000 |
| Independent staged output | 16 KiB |
| stdin attempts / CSV staging writes / stdout attempts | 4096 / 256 / 64 |
| Captured arguments / total argument bytes | 4 / 1024 |

Input reads use an excess-byte probe at the raw byte limit. Every I/O attempt,
including EINTR, spends its call budget. There is no wall-clock deadline on
blocking stdin/stdout. CSV accepts LF/CRLF, doubled quotes and quoted line
breaks; unsupported ASCII controls such as TAB are rejected even inside quotes.

The CSV table is destroyed after validation copies values into an owned vector
of plain numerical pairs. Statistics contain no allocation owner. A reusable
CSV record and separate bounded output buffer hold publication bytes. Input,
table, sample vector, record and output owners are explicitly destroyed on all
returned paths; no new allocator, arena or resource checker is introduced.

| Exit | Meaning |
| ---: | --- |
| 0 | Summary or help published |
| 2 | Invalid CLI, CSV, schema, parsed number/weight or input cap |
| 3 | stdin I/O failure or invalid transfer count |
| 4 | Reported allocation failure |
| 5 | stdout I/O failure/call cap, or SIGPIPE policy setup failure |
| 6 | Numerical update/query/formatting failure or output staging cap |

Only one `--help` or `-h` is accepted; positional operands and extra options are
errors. Help does not read stdin. SIGPIPE is ignored before I/O; a failure to
configure that policy returns 5 before attempting a diagnostic. Other returning
errors attempt `sample-moments: operation failed`; diagnostic failure preserves
the primary status.

## Target and verification

The intended executable target is Linux x86_64 emitted by the GPU compiler.
All production parsing, formatting, CSV handling and statistical composition
are Lanius. The application adds no host mathematics library, C implementation,
JSON transport or Wasm dependency. Host stdin/stdout execution is distinct from
GPU-kernel execution, which is not claimed here.

The registered Rust driver compiled the Linux x86_64 application, passed the
shared strict ELF checker and passed all four application tests on 2026-10-28:
model 26 cases, rejection 30, CLI 8 and I/O 2. Runtime receipt:
`target/stdlib-work/statistics-extension-runtime-final.log` (9.87 seconds);
build receipt: `statistics-extension-driver-build.log` (2.45 seconds).

The 66 cases cover exact Fraction/110-digit Decimal references,
unit/unequal/scaled weights, positive-row-only higher moments,
empty/all-zero/constant profiles, explicit undefined statuses, exact 1 MiB
and 4096-row bounds, numerical overflow and positive fourth-moment underflow,
and actual stdin/stdout failures. They include three equal minimum-subnormal
weights: total weight must round to three minimum subnormals and effective
count must be three. Count, total weight and extrema require exact binary64
agreement with the rounded reference; other metric tolerances are documented
in the fixture guide.

Executed source SHA-256:
`cdf6dcdfdd4fea27753fd32c31f4910d000737038c824bad485076bc542cde66`.
Oracle SHA-256:
`0d92191011f4ad258022255dc0518745373805550585c2f8d6c228e36e96a88c`.
The accepted weighted, higher and scaling module revisions begin with
`d3cea094`, `3f224ad3` and `775960e8` respectively; their full hashes and
registered evidence directories are recorded in
`tests/fixtures/stdlib_execution/sample_moments/README.md`. The current retained
raw executable also passes the same 66 cases after rebuilding these dependencies.
Its SHA-256 is
`b0ff96218219214213199979a7b00c320e622c3e7fda101142edc92137663745`.
Local receipts are `sample-moments-compile-final.log` and
`sample-moments-{model,rejection,cli,io}-native-final.log` under
`target/stdlib-work/`. The registered executable is produced separately;
no binary hash equality or additional distinct cases are assumed.

Seven CPU oracle controls pass separately. These finite application results
are separate from broader numerical-module coverage. The Python reference
exists only in tests. This is not formal verification, an allocation-failure
campaign or a leak proof.
