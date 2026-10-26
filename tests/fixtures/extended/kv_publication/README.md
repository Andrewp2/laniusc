# KV application atomic publication

Application-only migration controls for the actual `kv_tool.lani` executable.
The actual current executable passed both groups: 33 round trips and 31
publication cases, for 64 native process cases. Eleven CPU-only binding controls
passed separately. These are finite application receipts on native Linux
x86_64, not universal filesystem or crash-durability guarantees.

## Accepted receipts

Root GPU-compiled the corrected application source
`9de65a6cf8b42e923dd39d8374b26ed1216da63430a04359c76fb19e990e6cbe`
to `target/stdlib-work/kv-tool-atomic`, then ran these exact oracles directly
against that executable:

| Receipt under `target/stdlib-work/` | Accepted evidence |
| --- | --- |
| `kv-tool-atomic-syntax-retry-compile.log` | Corrected application compiled successfully. |
| `kv-tool-atomic-roundtrips-first.log` | `kv-application-roundtrips cases=33` |
| `kv-tool-atomic-publication-first.log` | `kv-application-publication cases=31 source-oom=13 io-faults=15` |

The first application compilation stopped before native execution with
unsupported block match-arm syntax. Its receipt is
`target/stdlib-work/kv-tool-atomic-first-compile.log`. Rewriting those branches
to supported expression syntax changed no product semantics, diagnostics or
test assertions. The successful compile/native receipts above are authoritative.
Rust integration-driver build admission is a separate step; these receipts do
not claim that libtest executed the wrapper filters.

The exact filters in `tests/extended_kv_execution.rs` are:

- `native_file_cli_round_trips_binary_values_and_replaces_only_validated_complete_snapshots`
- `native_cli_atomic_publication_races_faults_and_reached_allocations_report_visibility`

The five pure Store/contract/model/snapshot/limit/allocation tests are unchanged.
Their complete file prefix retains SHA-256
`7c50374a633ee7df9b9588931eb2de656a8f6ebc1a7a2091fe826e9f7da56e9c`.
Internal callers migrate directly to the new arity; no external human dependency
was identified that would justify a legacy SCRATCH compatibility branch.

The `roundtrips` group uses the guarded existing Python snapshot oracle for
canonical byte equality and independent structural decoding. It preserves
binary/empty values and keys, replacement, sorted list/get/check/remove,
missing-key statuses, corrupted snapshots, application limits and no-SCRATCH
argument rejection. Raw non-UTF-8 final components are included.

The `publication` group starts from a successful Replace update and derives
every reached verified source allocation rather than assuming a fixed count.
Injected ENOMEM binds the exact source IP, requested size/flags and full prior
mmap request prefix. Reached I/O faults bind baseline call sites and descriptor
roles. File-sync failure preserves the old target. Directory-sync failure must
return status 6 and the exact published/unsynced diagnostic while the full new
snapshot exists. An injected ambiguous rename error must report status 7;
observing the unchanged old target in that host-side skipped-call experiment
does not justify a production rollback claim.
One reached write-plus-unlink failure requires status 8, the original I/O
diagnostic, explicit cleanup failure and the actual retained temporary name.
Its real remaining file must match the reported name; keep releases its source
and descriptor owners without pretending that cleanup removed it.
One additional reached fd2 write fault binds the published/unsynced diagnostic
from its own baseline. The undelivered message must leave status 6 and the full
new target intact, preserving publication information in the process status.

The NoReplace init race observes the acquired private candidate, creates a
distinct complete final-name winner during bounded publication delay, then
requires actual EEXIST, exact conflict status/diagnostic, unchanged winner and
cleanup of only the owned candidate. It never modifies another process's temp
leaf or substitutes a time ratio for namespace observations.

All CLI runs use the trusted AtomicFile/TempFile ELF/source/fd ledger with
phase markers disabled. Synthetic close errors are excluded: strace skips the
kernel close and the real CLI has no fixture-only raw repair hook. Final native
and source owners must be released by observed calls before process exit;
there is no allocation-count constant or OS-exit cleanup shortcut.

Eleven CPU-only controls currently pass for the application-specific read/open
fault bindings. They reject incorrect source IP, descriptor, requested count,
creation flags and non-temporary path substitutions; they are not native
application acceptance cases.
