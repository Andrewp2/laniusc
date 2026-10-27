# KV command routing and atomic publication

Application-only controls for the actual `kv_tool.lani` executable. Bounded
response-file preprocessing compiles and passes its focused 55-case native
group. The earlier hierarchy source passed 130 group cases with full
syscall observation. The earlier
atomic-publication source passed 33 round trips
and 31 publication cases; those historical receipts remain below. The full
library goal remains open.

## Current response-file campaign

Application source SHA-256:
`789143f6157aee2da0719f926427a04f35af0ca143748e440aa6611da57c688b`.
Accepted oracle SHA-256:
`057bb27ae5cb8315ebfd50bedc54de6ca8c3c64bb9c6474a60fbee6324ae875a`;
registered driver SHA-256:
`46cba2976585014adc48e9634037d6a933c35af58548b5d0a9cb6b7b0053f665`.
The app validates its complete schema, admits a no-follow Files provider at AT_FDCWD, and prepares
one owned Expansion before hierarchy parsing/help or database operations.
The process is single-threaded with stable cwd. Expansion remains live through
the database outcome and releases on both success and failure. Store, target,
load/mutate/publish/report helpers retain their previous bodies.

Limits are explicit in the [application guide](../../../../docs/extended-kv.md#response-files):
raw/final args8, raw/final output bytes262144, argument/file bytes262144,
aggregate source bytes1048576, tokens256, files16, depth8, path4095,
work8388608 and native calls4096. The app deliberately applies expansion
after `--`; `@@` emits a literal leading `@`, and nested paths use fixed cwd.

The focused new registered filter is:

- `native_cli_response_files_preflight_raw_arguments_and_release_all_expansion_owners`

Root can reuse one compiled executable for the new group:

```sh
timeout --kill-after=2s 80s python3 -B tests/fixtures/extended/kv_publication/oracle.py /ABSOLUTE/ELF responses
```

The group preserves ordinary no-provider behavior, independently checks full
snapshot bytes through init/put/get/list/check/remove from quoted command
files, and distinguishes fixed-cwd nesting from including-directory lookup.
It checks raw filenames/DB bytes, `@@`, `@-`, expansion after `--`, quote/NUL/
escape errors, no-follow/nonregular admission, cycles, file/argument counts
and exact/one-over file-byte limits with actual EOF/byte observations.

Complete all-syscall traces use the unchanged source/fd helper below. Before
database effects, every response open must name the expected file, request
read-only/CLOEXEC/NONBLOCK/NOCTTY/NOFOLLOW, and complete metadata/read/close
against that actual fd generation. It closes before opening a child. Rejected
preprocessing or expanded CLI may access only those declared response files;
the complete fixture tree is unchanged. Source memory is verified independently
and all acquired fds/source mappings release before the validated native exit.

A successful nested-help baseline derives every actual source allocation;
each reached ENOMEM binds its instruction/request and complete prior allocation
prefix. This covers argv/expansion/source-file owners without an old allocation
floor. Response open/read I/O failures, read EINTR and a real closed-reader help
pipe check owner cleanup. A separate response-backed mutation baseline checks
a reached allocation failure after database open and published/unsynced status 6
after directory-sync EIO while Expansion is still owned. Synthetic skipped
close errors remain excluded; the actual app has no raw fd repair hook.

Ten response-effect CPU controls pass with `oracle.py response-controls`;
these check path, flags, live fd generation, descriptor metadata, no file write
and response-close boundary witnesses. Eleven `artifact-controls` separately
reject unsafe labels and verify counter uniqueness. They are not native cases.
The previous 130-case hierarchy and 64-case atomic-publication receipts remain
historical; adding preprocessing changes argv allocation schedules. Existing
groups remain available without claiming they ran on this new source.

### Current response-file receipts

| Log under `target/stdlib-work/` | Accepted scope |
| --- | --- |
| `response-kv-compile-first.log` | Compile exit 0 |
| `response-kv-native-artifact-retry.log` | 55 direct process group cases; all 18 reached source OOMs from the nested-help baseline |

The 18 denials cover every observed allocation in that baseline, including
argv, expansion and response-file owners. They are not all allocation paths
of every database command. The 55 cases separately include one reached
post-database-open allocation denial and the published/unsynced directory-sync
failure. Baselines overlap behavior; these are not 55 independent properties.

The initial `response-kv-native-first.log` ran ten cases, then Python artifact
naming failed before case11's native launch: `@sub/start.rsp` was incorporated
into `011-@sub/start.rsp.command.txt`. The fix uses a counter plus validated
ASCII label or `run`, with no argv-derived artifact filename. All native cases
and assertions were preserved. The full retry passed the unchanged source/ELF;
the first ten partial cases are not added to 55. This was a harness failure,
not a compiler/runtime or application bug. Read-only independent review found
no material issue in the app/oracle; the later fix changed only artifact naming.

| Current response identity | SHA-256 |
| --- | --- |
| `kv-tool-response.elf` | `00889c4433630e40e95c1b0777e8fe049697c5a46392ee2843f7f325ad90802c` |
| `ext::response` | `a997585cd691edf2d53781410568da8c72a65dfe4edb45b2502f8d7bdc6d05b7` |
| `ext::cli_response` | `35b6ee8391724450976aa765e279015cb2fab391bc80c608d1009a21f5895a09` |
| `ext::cli_response_files` | `461037b861323ce7d5a4955394e71c0e9839ebaa56198a9d0315fdf2abed06c7` |
| Unchanged all-syscall source/fd helper | `f7adcfca8bf50401e3ebdc70de65c839a4b5c7992b549ef0199b0a8674ec39f7` |

This is one direct Python group against retained native Linux x86_64 CPU code
emitted by the GPU compiler on local ext4. No Rust-libtest execution is claimed.
The registered KV driver built with `--no-run` alongside the native
response-resource driver in 2.09 seconds combined, recorded in
`response-resource-kv-drivers-build-first.log`; its executable is
`extended_kv_execution-3b7e887700dd7ba6`. This is shared build time, not a
per-driver measurement, and adds no native cases. Earlier hierarchy and atomic groups
were not rerun on this source and are not added to 55. Other host/filesystem,
fault and user GPU-kernel support need their own evidence.

## Historical hierarchy campaign

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
passed on that earlier source; `hierarchy` adds root and six child help goldens,
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

### Historical direct receipts: full syscall observation

All three groups pass against the same retained executable with every syscall
observed and launch/native-exit endpoints validated:

| Log under `target/stdlib-work/` | Result for that source |
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
coverage and are not added to the accepted 130 for that source. No app or library implementation
defect was identified from this observation gap. The helper's 48 current CPU
controls supersede its earlier 24; neither count is a native case count.

These are separate direct Python invocations; no three-passing-libtest receipt
is claimed. The registered driver separately builds with `--no-run` in 51.67
seconds (`cli-commands-kv-driver-build-first.log`), producing
`extended_kv_execution-3b7e887700dd7ba6`. That build adds no native case. The
earlier 64-case source below is not added to 130.

| Identity for that source | SHA-256 |
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
