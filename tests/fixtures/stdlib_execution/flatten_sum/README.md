# Flatten-sum real application checks

Status: all four application tests pass 219 process group cases across two
native commands, including overlapping setup/baselines. This is not 219
independent properties. The actual application is
`sample_programs/library/flatten_sum.lani`; the
[semantic guide](../../../../docs/stdlib-flatten-sum.md) defines its input,
output, limits and manual-owner contracts. Production uses real public
TryFlatMap/InnerRetirement/TryScan and owning Vec cursors.

Root serializes each compile/native gate; every command is bounded:

```sh
timeout --kill-after=2s 100s cargo test --test stdlib_flatten_sum_execution flatten_sum_prefix_totals_match_independent_nested_rows_and_empty_owners -- --exact --nocapture
timeout --kill-after=2s 100s cargo test --test stdlib_flatten_sum_execution flatten_sum_input_argument_caps_and_arithmetic_failures_publish_nothing -- --exact --nocapture
timeout --kill-after=2s 100s cargo test --test stdlib_flatten_sum_execution flatten_sum_all_reached_ooms_release_partial_rows_and_every_owner -- --exact --nocapture
timeout --kill-after=2s 100s cargo test --test stdlib_flatten_sum_execution flatten_sum_output_and_read_faults_preserve_exact_prefix_and_cleanup -- --exact --nocapture
```

Each driver oracle has a 70-second bound and each native child a five-second
bound. A retained executable can be checked without recompilation:

```sh
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/flatten_sum/oracle.py models /ABSOLUTE/COMPILED/ELF
```

Groups: `models`, `bounds`, `allocations`, `faults`. Models include nine authored
inputs, 128 seeded cases (`0x39e41327`) and a physical-row storage witness.
Grammar is explicitly ASCII digits/signs, LF rows and five horizontal separators;
it does not inherit Python int/split's wider accepted syntax. Output models use
unbounded arithmetic and reject out-of-i64 inputs/running totals independently.

Bounds exercise all six option caps, exact EOF, empty rows, zero allowances,
malformed/binary input, argument admission and overflow/output quota with an
active inner plus remaining outer rows. The row witness observes a real
allocation for each physical row including empties and exact releases before
publication/error. Reached OOM positions come from the executable baseline,
without a historical floor or stage-count assumption. Faults include actual
closed-reader help/data EPIPE, invalid progress, finite EINTR budgets and real
1,024-byte stdout prefixes before quota/EIO. The second-output EIO binds a
successful multi-write baseline's exact instruction, fd 1 and requested count;
an injected stderr diagnostic cannot satisfy that case.

Source provenance is the unchanged raw-ELF verifier from
`tests/fixtures/extended/archive_source/ledger.py` and its trusted TempFile
dependency. The fixture copies no allocator scanner. It requires raw executable
ranges with no named fallback, full-width addresses, exact requested lengths,
source allocation sites and exact releases. Every rule must be reached and
matched; duplicate injection options reject. Every source mapping must be
released before a final traced `exit`/`exit_group`, not merely disappear when
the process exits. This app has no ACK or `/proc` pre-exit handshake; direct
adapter owners have separately scoped live checkpoints. No filesystem effect
is expected from the program.

CPU-only preparation:

```sh
timeout --kill-after=2s 100s python3 -B tests/fixtures/stdlib_execution/flatten_sum/oracle.py controls
```

## Current finite native receipts

Logs under `target/stdlib-work/`:

| Log | Result |
| --- | --- |
| `nested-flatten-sum-models-bounds-first.log` | PASS two tests in 8.51s: models 138 and bounds 54 process cases. |
| `nested-flatten-sum-allocations-faults-first.log` | PASS two tests in 8.23s: allocations 11 (baseline plus all ten reached source OOMs) and faults 16 process cases. |

All ten OOMs are independently present as exactly one injected mmap/ENOMEM
event per failure trace in `/tmp/lanius-flatten-sum-allocations-_d2m0iun`.
Their statuses are all 4; baseline status is 0. The oracle derives these ten
positions from verified executable allocation sites and requires exact
instruction/argument/prefix binding and explicit release; no old allocation
floor establishes this result.

| Accepted source | SHA-256 |
| --- | --- |
| `sample_programs/library/flatten_sum.lani` | `946043fe6f13dfcd76c8266cb5950e5b00dac381b63f98259e9bf4cac23a7fd1` |
| `stdlib/core/iter.lani` | `7256a39462db691ece403a6d9a409947f7fafa7919783be474d510f1bf63ce3c` |
| `tests/stdlib_flatten_sum_execution.rs` | `2f4ebf9d43577a3b6eb7c6da1652693c38470d7a92a6b19e24536ed8586ab739` |
| `oracle.py` | `444831c2770a1b9ca8ad98e594a665675ed0f4498b4dd0319affa6a9042ec563` |

These run as native Linux x86_64 CPU code emitted by the GPU compiler on
kernel `7.0.0-38-generic`, with local ext4 `/tmp` evidence. They make no other
host/user GPU-kernel or universal throughput claim. The earlier direct CLI
admission and three-row/four-value native smoke overlap this workflow; their
logs `nested-flatten-sum-admission-first.log` and
`nested-flatten-sum-admission-native-first.log` are not extra cases in 219.
The joint semantic/application Rust-driver build passed in 1.39s in
`nested-semantic-app-drivers-borrow-retry.log`, not an isolated app-build time.
Its initial E0308 (`nested-semantic-app-drivers-first-build.log`) was in the separate
`stdlib_nested_iteration_execution.rs` harness; it did not change this app,
oracle or accepted byte/ownership contracts.

Eighteen CPU controls separately pass byte grammar/overflow, source literal
lengths and injection reachability/result/site/prefix binding. Only this
dedicated Rust driver was formatted with `--config skip_children=true`.
The fixture author made no additional Cargo/GPU/native run while finalizing
these receipts. Direct adapters' live ACK owner checkpoints are separate from
this app's explicit-release-before-exit traces. The complete library goal
remains open.

## Separate scale observation

`nested-flatten-sum-scale-first.log` records one untraced execution reusing
accepted ELF SHA-256
`906488cc3febca5cf7577466bbed9ff526cd63e0e5ec4a5a64156a1bd0682d35`,
with unchanged app `946043fe...` and core `7256a394...`. It processes 3,072
physical rows (1,024 rows of 64 ones and 2,048 empty rows), 65,536 values and
133,120 input bytes. Output is 382,110 bytes; exact totals 1..65,536 were checked
outside the timer. Options were `--input-bytes 1048576 --rows 4096 --values
65536 --output-bytes 1376256`.

Wall time **0.157614975 seconds** includes launch, stdin transfer, parsing,
ownership traversal, formatting and stdout capture. Evidence remains at
`/tmp/flatten-sum-scale-c24v1gy5`. This is one process observation, with no scale
allocation-count, compiler/GPU benchmark or general speed-ratio claim. It adds
nothing to the four tests/219 process group cases or fault coverage.
