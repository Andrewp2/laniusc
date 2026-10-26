# Regex Workspace execution fixtures

These fixtures target the fixed-capacity `ext::regex::Workspace` and owned
`Search` cursor contract. All three focused gates passed GPU compilation followed
by native Linux x86_64 execution in the separate receipts below. No other
user-program target is accepted by this evidence.

`protocol.lani` keeps one Workspace across 839 semantic cases. The independent
Python `re` search oracle and existing full-context endpoint oracle check full
captures and span-only results, both packed and actual native strided Text at
nonzero backing offsets, scalar-boundary starts, work failure/reuse, flags and
nullable/capture-priority controls. Known Pike nullable-cycle results remain
explicit canonical tables rather than substituting Python's capture policy.

`contracts.lani` checks fixed state/group capacity failures, smaller reuse after
rejection, capture reset, full/span/full transitions, exact repeat work reset,
independent owned Match lifetime and interleaved Search owners. The final empty
EOF match remains inspectable until next/destroy; terminal cursors fuse and
retain their last attempted work count. The first two real stdout/ACK
checkpoints surround explicit Workspace probes and permit neither mmap nor
munmap. Cursor creation and terminal cleanup run outside that phase. The final
checkpoint requires all source maps released before process exit.

`allocation.lani` rejects six invalid constructor capacities before allocation,
then reserves a valid Workspace. Its baseline has nine source allocation sites;
every actually reached mmap is separately denied ENOMEM. Both failure and
success paths stop at ACK checkpoints so the test verifies partial cleanup or
live requested bytes, then explicit release, before allowing process exit.

`oracle.py` directly reuses the existing archive-source live-prefix ledger and
its TempFile raw-ELF opcode/instruction verifier. Per-site flag authority accepts
the exact 0x22/full-width or historical 0x62 allocator profile; it does not infer
source ownership from low addresses. Injected syscall instruction, full args,
ordinal and baseline request prefix must agree. Actual stdout bytes bind each
trace checkpoint; `/proc` verifies live mappings and fd0/1/2 before the ACK.

The three exact Rust filters in `tests/extended_regex_workspace_execution.rs`:

- `workspace_reuse_and_span_searches_match_independent_models`
- `workspace_capacity_reset_cursor_lifetimes_and_zero_allocation_reuse_execute`
- `all_nine_workspace_constructor_ooms_release_partial_owners_before_exit`

Run each root-controlled test command with an external timeout below two
minutes. Individual traced processes have seven-second deadlines; groups have
75 seconds and the Rust oracle wrapper has 85 seconds. This is finite semantic
and allocation evidence, not a throughput benchmark or another supported target.

## Accepted receipts

Root ran these commands serially. Logs are under `target/stdlib-work/`; elapsed
times describe their complete invocations, not isolated matching throughput.

| Scope | Result | Invocation time | Log |
| --- | --- | ---: | --- |
| Strict contracts, zero-allocation explicit reuse and pre-exit release | One native fixture passed. | 6.12 s | `regex-workspace-contracts-first.log` |
| Constructor allocation campaign | Baseline plus all nine reached ENOMEM positions passed: ten native processes. The model in this same invocation failed before native execution. | 9.19 s, mixed invocation | `regex-workspace-model-and-oom-first.log` |
| Independent semantic reuse model | All 839 cases passed in one native process. | 6.99 s | `regex-workspace-model-exhaustive-offset-retry.log` |

The initial model admission failed with `LNC0005` at the wildcard offset arm in
`protocol.lani`. Explicit `i32` result types and distinct payload binders did
not resolve it: the model-only typed retry failed before native execution in
3.70 seconds (`regex-workspace-model-typed-bindings-retry.log`). Replacing that
wildcard with the eight exhaustive error arms already used by `regex_input.lani`
then admitted and executed the complete unchanged model. This was a supported
fixture source-shape workaround; no production matcher or compiler repair is
claimed. The already accepted contracts and OOM gates were not rerun.

The 24 CPU controls passed separately: 17 reused live-map/trace controls and
seven independent semantic controls. They do not count as native cases. The
base regex two-test regression also passes in 10.50 seconds
(`regex-workspace-existing-regressions-first.log`). It is separate from these
new Workspace receipts; its original allocation probe uses legacy accounting.

These gates explore fixed-capacity construction and reuse, including deliberate
rejection of larger programs followed by valid smaller searches. There is no
reserve/growth API. The allocation campaign covers one injected fault at each
successful-baseline constructor allocation, not simultaneous faults or arbitrary
host failures. Capture borrows are inspected only within their documented
lifetime; manual owner copies are not independent cleanup authorities.

## Checkpoint hashes

SHA-256 values identify the accepted source checkpoint, based on dirty
`aab5c5f278499235717f1ef041df784e08092dd6`. The source and oracle were frozen
during the accepted native gates, apart from the model fixture admission fixes
described above.

| Source | SHA-256 |
| --- | --- |
| `extended/ext/regex.lani` | `4520d1fc663432af975dd774d07da0f3b747f2164c2465b8e62ff4b6b08e1659` |
| `tests/extended_regex_workspace_execution.rs` | `04af05a38d987db605e913ef8a9c3d40bb69fbdf2f6946f7897e4b493dc1e072` |
| `protocol.lani` | `43b2b89e9eeb21423544f091a00d15df72ab40be84324028434c5dc75abdc7ed` |
| `contracts.lani` | `1916309de6a73052a93b97e18d6e82f795d8dd17c3f831c2f81e0f771c1bd215` |
| `allocation.lani` | `c718fe0107a543c81eabf38bf5662cbab41a7bf0e94f15b67a4e2c7be47ae0dc` |
| `oracle.py` | `d98311eedcf74348dc3d3e5450f577a10387843abe4f9306cd664ad4cfa25870` |
| Existing `extended_library/regex_input.lani` error encoding | `c316f787934c152956832d1ba7fff4de1e0d0dece80761fe7c48ed6096c021fa` |

Retained ELF artifacts were hashed without executing them again:

| Artifact | SHA-256 |
| --- | --- |
| `/tmp/laniusc_regex_workspace_contracts_lani_374894_0` | `b55afe6bf4d357ac8adc2a5b4106306ea8f1f59c8bcc44a878be00b8efc39159` |
| `/tmp/laniusc_regex_workspace_allocation_lani_375166_0` | `6adb5f9f976882704054a48d371c7348974e35980f12198baa53d764435ea91f` |
| `/tmp/laniusc_regex_workspace_protocol_lani_377323_0` | `f7465e0ab0fb26d449f1a24e8a79d9f855bee6070db249f79346f9fec917780f` |
