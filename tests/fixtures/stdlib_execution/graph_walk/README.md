# Graph walk application fixture

The model independently materializes a small dense transition matrix. It
coalesces parsed binary64 inputs in original order, checks ordinary binary64
row sums and rounds exact weight/row-sum ratios to the stored binary64 profile.
Subsequent steps use exact Fraction dense products rather than production CSR
indexing or its iterative floating accumulator. Bound cases with many nodes
use explicit, independently known unit-mass results.

Every output is checked for exact node order/count, finite nonnegative mass,
fully quoted CRLF CSV and the exact `node,mass` header. Specified single-step
and deterministic cases require exact binary64 equality, including minimum
subnormal mass. Other masses allow the larger of relative `2e-12` or 32 ULPs;
expected zero must equal zero exactly. This finite tolerance admits ordinary
rounding and exposes orientation, normalization, duplicate and source errors.

| Group | Cases | Coverage |
| --- | ---: | --- |
| model | 32 | Dangling nodes/arrivals, weighted splits, duplicate coordinates, directed/reversed edges, self-loops, cycles, zero/1000 steps, zero weights, subnormal/large finite values, probability underflow, quoted fields, 4096 nodes, 65536 raw edges, exact 4 MiB input and ten seeded dense models |
| rejection | 33 | CLI-independent schema/CSV/UTF-8/endpoint/weight/field/edge/input rejections, invalid later edges, zero-step full validation, coalescing overflow and row-sum overflow |
| cli | 38 | Required/bounded nodes, steps/source bounds and grammar, duplicates/aliases/clusters, unknown operands/options, argument caps, help validation/input bypass, short attached values and long equals forms |
| io | 10 | Actual directory stdin error, closed data/help stdout, a traced native baseline, three reached allocation denials, read/write EINTR retries and SIGPIPE setup failure |

The I/O baseline uses a small three-node graph with two steps. Three selected
mmap ordinals sample early construction, middle processing and late staging.
Each injected ENOMEM must be reached at exactly that ordinal with the same
mmap arguments as the baseline, return status 4 and publish no output. This
is a modest finite allocation-failure check, without an owner ledger,
exhaustive denial campaign or leak proof. Faulted read/write calls are also
required to be reached; successful retries must match the same independent
mass model. No positive byte-transfer result is fabricated.

```sh
python3 -B tests/fixtures/stdlib_execution/graph_walk/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/graph_walk/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/graph_walk/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/graph_walk/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/graph_walk/oracle.py io PATH_TO_ELF
```

Each native child is limited to 25 seconds and each registered group to 85
seconds. Input, command, stdout, stderr and exit evidence are retained for
each case; traced cases additionally retain syscall logs. Nine CPU-only
controls cover hand-computed walks, orientation, subnormals, canonical output,
exact-cap input construction, literal lengths and the non-I/O case counts.
They are separate from native acceptance.

## Acceptance

The registered Rust driver compiled the final application through the GPU
compiler, passed the shared strict ELF checker and passed all four tests on
2026-10-28. These are 113 finite native Linux x86_64 cases: model 32, rejection
33, CLI 38 and I/O 10. Runtime took 16.31 seconds. Receipt:
`target/stdlib-work/graph-walk-runtime-module-import.log`.

Accepted evidence directories:

- Model: `/tmp/graph-walk-model-79k_i3xy`.
- Rejection: `/tmp/graph-walk-rejection-t_tbsk3p`.
- CLI: `/tmp/graph-walk-cli-mxbirxd3`.
- I/O: `/tmp/graph-walk-io-lqpbkfer`.

Reproduce with a warm local build and configured GPU:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock env CARGO_TARGET_DIR=target/stdlib-build cargo test --test extended_graph_walk_execution -- --nocapture --test-threads=1
```

The emitted program computes on the CPU and uses native stdin/stdout. This
receipt covers finite application behavior and selected reached faults;
device-side GPU execution, formal verification, leak freedom and exhaustive
allocation denial are outside its scope.

Executed source SHA-256:
`a5ef4646d9168ff460589bc7058425a1666485e26b142adb53be8c91ad2756b5`.
Oracle SHA-256:
`cb68606dccfda6bf8a988963728c46bf1108fb8d8f0b6be8ad215ea9baa4131d`.
Root-formatted driver SHA-256:
`4cf8e8e07978239f6808a96175ebd6643adc9dbae45f9bf53264a90d2c47adef`.

Earlier compile attempts exposed an item-import priority limitation: the
application's selective slice `view` call reported `LNC0027`, and the narrow
explicitly typed reduction reports `LNC0006`. The accepted source uses fully
qualified slice calls plus the required `import core::slice;`. The
[item-import priority fixture](../../stdlib_compiler_state/item_import_priority/README.md)
retains the reduction and a compiled, executed qualified control. No compiler,
ABI or proof code was changed for this application; compiler repair remains
a separate dependency.
