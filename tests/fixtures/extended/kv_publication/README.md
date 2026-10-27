# KV command routing and atomic publication

Application-only controls for the actual `kv_tool.lani` executable. The command
hierarchy/generated-help migration compiles and passes all three direct oracle
groups with full syscall observation: 130 group cases with overlapping
setup/baselines. The earlier
atomic-publication source passed 33 round trips
and 31 publication cases; those historical receipts remain below. The full
library goal remains open.

## Current hierarchy campaign

The source is frozen at SHA-256
`f07fd52f980f6442d4a5ba001d08d656ccda2a8bc227be2254150ff19019112b`.
The application uses root plus six leaf commands, inherited `-h`/`--help`, one
caller Spec scratch slot and a 4,096-byte logical help view backed by a fixed
stack array. Help permits 64
at-most-1,024-byte write attempts. Checked startup SIGPIPE ignore precedes
owners/output; setup failure returns 3 without writing. Argument snapshots
admit eight tokens and 262,144 bytes. The [app guide](../../../../docs/extended-kv.md)
defines full-parse/help/arity policy and the intentional `--` escape for dashed
DB names. Database and atomic-publication operations retain their code.

Root owns compiler/native execution. Existing `roundtrips` and `publication`
pass on the new source; `hierarchy` adds root and six child help goldens,
late errors even with help, exact count/byte admission, unknown/case-sensitive
commands, raw/dashed/command-looking DB names and unchanged binary snapshots.
Help and rejected command/arity/hex paths require no database/parent opens,
metadata, fd duplication, entropy, reads, truncation, unlink, rename or sync,
with the sentinel/tree unchanged. Argument allocation and output are allowed.

Help I/O cases bind the successful baseline's fd 1 write IP/request/bytes for
EIO/EINTR. Exactly 64 reached stdout EINTRs exhaust help's budget; the finite
injection ends before the existing diagnostic writer. A real pipe whose read
end is closed, with `restore_signals=True`, must produce uninjected EPIPE,
status 3, the I/O diagnostic and explicit owner release. Failed signal setup
must perform no write, allocation or filesystem operation. No synthetic close
failure is added.

The app-only `source_ledger.py` composes the unchanged verified raw allocator
and full-width source-map authority with fd-generation accounting. It admits
actual verified 0x22/0x62 profiles and parses signal calls explicitly; it has
no named fallback or process-exit cleanup shortcut. Every actual source
allocation must precede the publication rename, with complete original event
indices. All syscalls are traced. Exactly one successful first execve must
launch the resolved expected executable from outside the raw image; exactly
one final exit/exit_group must originate inside it and match the actual native
process status. Only these endpoints are normalized. Every remaining call
must be in the admitted set and originate in the verified image; unlisted
host calls reject. Source frees and physical fd closes must occur before the
validated native exit. The historical AtomicFile ledger remains unchanged.

The registered filters are the two listed below plus:

- `native_cli_hierarchy_help_and_raw_path_routing_have_no_premature_file_effects`

Each may be run through `tests/extended_kv_execution.rs`; the oracle can reuse
an admitted ELF without recompilation:

```sh
timeout --kill-after=2s 80s python3 -B tests/fixtures/extended/kv_publication/oracle.py /ABSOLUTE/ELF hierarchy
```

Groups are `roundtrips`, `publication`, `hierarchy`; each native child is bounded
at eight seconds. CPU-only controls run with `oracle.py controls` (24 PASS)
and `controls.py` (11 PASS), separately from the helper's 48 CPU controls and
native execution.

### Current direct receipts: full syscall observation

All three groups pass against the same retained executable with every syscall
observed and launch/native-exit endpoints validated:

| Log under `target/stdlib-work/` | Current result |
| --- | --- |
| `cli-commands-kv-admission-first.log` | Compile exit 0 |
| `cli-commands-kv-hierarchy-all-syscalls.log` | 66 process group cases |
| `cli-commands-kv-roundtrips-all-syscalls.log` | 33 process group cases |
| `cli-commands-kv-publication-all-syscalls.log` | 31 process group cases, all 13 reached source OOMs and 15 I/O controls |

Total: 130 group cases, with overlapping setup/baselines. The first
`cli-commands-kv-{hierarchy,roundtrips,publication}-first.log` runs used a
selected-syscall filter. Independent review
found that the trace filter omitted calls such as `unlink` and `socket`;
unlisted host work could be invisible despite the selected-call and final-tree
checks. The full-trace correction described above passes all three reruns on
the unchanged ELF. Those first 130 partially observed cases are repeated
coverage and are not added to the current 130. No app or library implementation
defect was identified from this observation gap. The helper's 48 current CPU
controls supersede its earlier 24; neither count is a native case count.

These are separate direct Python invocations; no three-passing-libtest receipt
is claimed. The registered driver separately builds with `--no-run` in 51.67
seconds (`cli-commands-kv-driver-build-first.log`), producing
`extended_kv_execution-3b7e887700dd7ba6`. That build adds no native case. The
earlier 64-case source below is not added to 130.

| Current identity | SHA-256 |
| --- | --- |
| `kv-tool-command-help.elf` | `46770678b28f9d5eed7e820c2e23313a85df309fe2af0d15119362325b889245` |
| Compiler CLI | `e8ad0014f4eb54595da04c1e98521cd0bf4e18db273538203416e1fd2f20e5b9` |
| `ext::cli` | `9f11981f1292bea61c3c571ff86b0fcdba52259c8e626886e4e6b322557a17cd` |
| `ext::cli_commands` | `6eb4db7ad6f63768a3fe96c6aee6dec55560f8d098efe7a5dbbbfff5e7cb536f` |
| `ext::cli_help` | `a7198a2a18f6dcac549fb08c5735af538689b76f53b0be4e942798227ec9f60a` |
| `oracle.py` | `b3ec740f44e78d73f58452b4d0e844b736f0db0e1d62188dd579e28cad0f2232` |
| `source_ledger.py` | `f7adcfca8bf50401e3ebdc70de65c839a4b5c7992b549ef0199b0a8674ec39f7` |

The target is native Linux x86_64 CPU code emitted by the GPU compiler on the
selected local ext4 profile. No user GPU-kernel, broader-host or universal
filesystem/crash-durability guarantee follows. Initial oracle composition
review was separate from helper authorship. The later independent observation
finding led to full tracing; a separate read-only review cleared the corrected
endpoint normalization, source-provenance and fd-generation checks.

## Historical atomic-publication receipts

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
