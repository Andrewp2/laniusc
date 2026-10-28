# Signed sparse powers application fixture

The small-graph model materializes dense matrices, independently of production
CSR indexing, scratch markers, touched-column sorting and its two passes.
Ordered duplicate inputs first coalesce with ordinary binary64 addition.
Dyadic graph cases then use exact `Fraction` dense products. Separate dense
binary64 controls exercise increasing-inner-index product/add rounding and
gradual underflow. A rounded one-node fourth power distinguishes left
association from squaring. Powers retain the original base.

Output checks require the exact `source,target,weight` header, fully quoted
CRLF CSV, increasing unique coordinates, finite nonzero values and exactly
the reference coordinates/values. Current model cases require exact binary64
equality. Large admission cases use explicit combinatorial results rather
than allocating a 4096-square reference matrix.

| Group | Cases | Coverage |
| --- | ---: | --- |
| model | 34 | Empty matrices, signed directed paths, orientation, cancellation, ordered duplicate sums, rounded left association, zero omission, lengths 1/16, subnormal/large finite inputs, exact input/raw-edge/result caps and ten seeded dyadic dense/Fraction models |
| rejection | 37 | Schema/CSV/UTF-8/endpoint/numeric/field/input/edge failures, complete length-one input validation, duplicate/product/sum/later-power overflow, result-entry and product-work caps |
| cli | 36 | Required/bounded nodes, length grammar/bounds, duplicate aliases, unknown options/operands, argument caps, help validation/input bypass and attached/equal values |
| io | 15 | Actual directory stdin, closed data/help stdout, traced native baseline, eight reached allocation denials, read/write EINTR and SIGPIPE setup failure |

The small I/O graph has seven nodes, fourteen input edges and twenty-one
squared entries. The current source's contiguous allocation-size recipe
identifies its three product scratch reservations and three result buffers.
Together with an early allocation and a late staging allocation, these give
eight selected ENOMEM sites. Every injection must actually occur at the
selected ordinal with the same mmap arguments, return status 4 and publish
no output. This recipe selects fault sites; allocation order is not a public
library promise.

For each traced process, the oracle pairs every observed successful mmap
with a successful munmap of the same address and size, rejects unexpected
allocation services and requires no observed live mappings at exit. This is
a finite syscall observation, not a resource checker, exhaustive denial
campaign, lifetime/alias check or proof of leak freedom. EINTR tests also
require the fault to be reached and compare the complete retried result.
No positive transfer count is fabricated.

The 16 MiB staging cap is a documented application bound. The maximum
65,536 finite output entries do not approach it in these fixtures; no claim
is made that this larger bound was independently reached.

```sh
python3 -B tests/fixtures/stdlib_execution/sparse_paths/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/sparse_paths/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sparse_paths/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sparse_paths/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sparse_paths/oracle.py io PATH_TO_ELF
```

Each native child has a 25-second deadline and each registered group an
85-second deadline. Commands, inputs, stdout, stderr, status and optional
syscall traces are retained per case. CPU-only controls cover hand-computed
powers, orientation, ordered coalescing, subnormal behavior, canonical output,
exact-cap construction, case counts and a deliberately missing release.

## Acceptance

The current four groups cover 122 distinct native Linux x86_64 cases, accepted
on 2026-10-28 across two receipts. The registered driver used the GPU compiler
to emit the executable and passed the shared strict ELF checker.

- The initial four-group run passed 121 cases in 20.45 seconds: model 33,
  rejection 37, CLI 36 and I/O 15. Receipt:
  `target/stdlib-work/sparse-paths-runtime-first.log`.
- One rounded left-association case was then added. The amended model group
  passed all 34 cases in 14.73 seconds, with the other three tests filtered.
  Receipt: `target/stdlib-work/sparse-paths-model-association.log`.
- Rejection 37, CLI 36 and I/O 15 were unchanged by that amendment. Their
  accepted evidence comes from the initial run; they were not rerun afterward.

The model rerun overlaps the initial 33 model cases. These receipts therefore
support 122 distinct cases across 155 native process runs.

Evidence directories:

- Current model: `/tmp/sparse-paths-model-p5ce95ju`.
- Initial model: `/tmp/sparse-paths-model-6hvlau0r`.
- Rejection: `/tmp/sparse-paths-rejection-0w7zwvox`.
- CLI: `/tmp/sparse-paths-cli-p_8z0m3y`.
- I/O: `/tmp/sparse-paths-io-tox_t_lf`.

Accepted application SHA-256:
`1c01bd461535b5a87e1a783ad38c1b66281c350468f72760e79a83d53f7f1011`.
Current oracle SHA-256:
`1e42dd2f4003fe915345e1b8f7c953b0da08c65d221b3f0c44c499cb97f77f37`.
Current root-formatted driver SHA-256:
`6284516378b67271e65c6f5b5d2d778ba434d5edf66c071bbbcaa6945be3e41d`.
The initial oracle was
`6d8d4318d7aae26037a287c75d6fa29db2abee017d44d94442c3b61ba03149f3`.

Fourteen CPU-only controls also passed. Native acceptance covers finite
application behavior and the selected reached faults. It does not claim
device-side execution, formal verification or exhaustive allocation-failure
coverage.
