# Canonical CSR contract tests

The producers import the real Lanius sparse modules. They contain assertions
and scripted allocation-failure entry points, with no replacement matrix math.
`model.lani` and `oracle.py` provide a separate independent mathematical check.

## Pure contracts

`contracts.lani` imports `ext::sparse` and core utilities. Five bounded scenarios
exercise canonical CSR validation, row/get bounds, explicit signed zeros,
zero-row and zero-column shapes, and matvec publication behavior.

Malformed limits, shapes and integer view metadata are tested with deliberately
inaccessible backing. Only rejected metadata is used in those cases; attempting
to read an element would be invalid. Ordinary backed cases cover offset length,
first/last/monotonicity, column range, duplicates/unsorted columns and nonfinite
stored values, including error row and logical entry positions.

Matvec preflight failures leave all output unchanged. Product and sum overflow
cases preserve previously completed rows and leave the failed row and suffix
untouched. Validation and multiplication work are admitted as separate phases;
the fixture checks their exact boundary. Fixed arrays and typed native storage
exercise nonzero view starts. Both i32 input constructions use packed stride
`+4`; both f64 constructions use descending stride `-8` on this profile. No
positive-stride f64 claim is made.

## Owners, arithmetic and fault injection

`owners.lani` reads one opcode byte. Opcode zero executes four normal contract
scenarios: independent copies/clones/transposes, empty shapes and reset/double
destroy, stable input-ordinal duplicate aggregation and cancellation, sparse
arithmetic/dense composition, limits and numerical-error cleanup. Failed calls
preserve caller inputs; explicit stored zeros survive copy/clone/transpose,
while newly computed zero entries are omitted.
Zero-row cases with inaccessible x/column-factor backing require work-limit
rejection before any vector scan, including factors for unused columns.

Opcodes 1–14 isolate allocation paths:

| Opcode | Operation |
| --- | --- |
| 1–5 | zeros, from_csr, from_triplets, transpose, try_clone |
| 6–10 | add, sub, scale, scale_rows, scale_columns |
| 11–14 | matvec, from_dense, to_dense, matmul_dense |

Each returns a one-byte stderr marker: `S` for successful output cleanup, `F`
for typed AllocationFailed inside the selected operation, or `I` only when
try_clone's input-owner construction was denied first. Every failure path
checks retained inputs, and every successful result is explicitly destroyed.

`tests/extended_sparse_contract_execution.rs` compiles strict raw ELF producers
with stdlib and extended source roots. Four registered gates cover the pure
producer, normal owners, and two bounded allocation-denial groups. Each group
has an 85-second budget; individual native runs have an eight-second cap. The
driver records actual mmap sites, denies each baseline site once, requires
reached operation failures for every opcode, and matches every successful
allocation/release by full address and size. An empty pure allocation trace
and no remaining owner mapping are required. No new resource-checker framework
is introduced.

## Executed acceptance

The producers compiled through the GPU compiler and executed as raw native
x86-64 programs on Linux. All four contract-driver gates passed across two
filtered commands:

- `target/stdlib-work/sparse-contracts-owners-first.log`: the pure and normal
  owner gates passed in 11.01 seconds. The pure allocation trace was empty;
  normal owner mappings all matched explicit releases by full address and size.
- `target/stdlib-work/sparse-allocation-denials-first.log`: both denial groups
  passed in 9.92 seconds, reaching 18 constructor/clone/merge failures and 15
  scale/product/conversion failures. These 33 operation failures exclude the
  separately marked clone input-owner setup failures. Each observed baseline
  allocation was denied once, retained inputs were checked, and no successful
  mapping remained unreleased.

The registered independent model gate also passed in 8.15 seconds:
`target/stdlib-work/sparse-model-qualified.log` records 3,886 cases over 17
modes and two storage forms with seed `0xc5a20261028`. It compares canonical
storage, sparse arithmetic and sparse/dense products with independent host
references.

Accepted source SHA256 values:

| Source | SHA256 |
| --- | --- |
| `contracts.lani` | `09e466896f4234a9306bd11ad9da5143684ae6d5e4ef191028931618f6f2db55` |
| `owners.lani` | `56048148ce31de072a9b0f0bb587c066193f680e8658e9c43a37a07896c56898` |
| `model.lani` | `b99eedf80ecca5ca58e52f9991988a80512625aacf6e093f1c39d9f72f578966` |
| `oracle.py` | `6ac4aae19e8aa30012506a2a49a6799822085a7878f3be6e9db9f2144d18a556` |
| `scale.lani` | `0e20e7eb5a7ed5f7c60976643571884a7d9f84361fdd6ce72b64eb77029b9d3b` |
| `sample_programs/library/graph_walk.lani` | `a5ef4646d9168ff460589bc7058425a1666485e26b142adb53be8c91ad2756b5` |
| `extended/ext/sparse.lani` | `e7adc62eee158635d202b090c25d5ed8c6faa144db373aa97e35863d33f2cc9d` |
| `extended/ext/sparse_matrix.lani` | `9fdae36cfe679cc5fb175ad268978bbfd2921b31c1ca3e30fd490dc729b9e207` |
| `extended/ext/sparse_ops.lani` | `fa34680de882eb094559f52b43251cd96bb456a0108067c04712df896d400d6d` |

The first pure run trapped on an incorrect fixture expectation that fixed i32
storage had negative stride. Executable measurements established `+4` for both
i32 constructions and `-8` for both f64 constructions; correcting that assertion
required no pure-library change. An ambiguous unqualified model error-kind
spelling was corrected with fully qualified names before the accepted model
run. A real sparse-ops admission-order defect was also fixed before these
receipts: complete vector scan work must be admitted before accessing vector
elements, even for a zero-row matrix.

The registered scale gate passed in 9.10 seconds in
`target/stdlib-work/sparse-scale-first.log`. Its one analytic `scale.lani` case
uses 65,536 rows and columns with 196,606 stored entries, representing
4,294,967,296 implicit dense cells. Assembly, transpose, sparse products, dense
admission assertions and cleanup execute over the actual owners. The reported
1,365.553 ms native lifecycle includes construction, all operations, assertions,
cleanup and harness overhead; it is neither isolated kernel throughput nor a
speed ratio. This brings the accepted distinct library gates to six across the
separate commands recorded here.

The [graph-walk program](../../../../docs/extended-graph-walk.md) also passed all
four registered gates in 16.31 seconds in
`target/stdlib-work/graph-walk-runtime-module-import.log`: 32 independent-model
cases, 33 invalid-input/numerical rejection cases, 38 CLI/help cases and ten
actual I/O/allocation-denial cases, totaling 113 cases. These exercise CSV
input, canonical CSR assembly, outgoing normalization, dangling-node handling,
transpose, repeated matvec and staged CSV output in the real program. They are
additional application gates, not extra library model cases.

This evidence covers finite Linux x86-64 CPU execution and single allocation
denials at the observed sites for these inputs. It does not establish arbitrary
failure schedules, a uniform numerical accuracy bound, other targets,
user-program GPU execution or formal correctness.
