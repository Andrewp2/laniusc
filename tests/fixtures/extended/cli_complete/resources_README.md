# KV completion query owners and failures

## Current status

Both direct Python-driven native resource groups passed on their first attempt
against the retained `target/stdlib-work/completion-kv.elf`. They cover **28 group
cases**, including overlapping query baselines, with **13 individually reached
source OOMs**. Exact receipts are below. The Rust wrapper has separate build
admission in `completion-bash-app-drivers-build-first.log`: three selected
drivers built together with `--no-run` in 3.56 seconds. These receipts do not
claim two registered Rust tests executed successfully.
The fixture author ran no compiler, Cargo, strace, native Lanius, Bash or PTY
execution.

The **27 CPU controls** pass separately. They validate expected frame modes and
reject forbidden host effects or nonstandard output descriptors; they establish
no native application acceptance. Existing source-ledger controls and older
semantic/shell receipts are not added to that count.

## Current direct native receipts

Both groups used unchanged application source `9a83795a`, oracle `31253db6`
and the retained ELF identified below. Root serialized both commands. Logs
under `target/stdlib-work/` report counts without elapsed times; none is inferred.

| Receipt | Group cases | Reached OOMs |
| --- | ---: | ---: |
| `completion-kv-query-allocations-first.log` | 16 | 13 |
| `completion-kv-query-output-first.log` | 12 | 0 |

The allocation group contains three successful mode baselines and thirteen
individually reached source allocation denials. The output group contains its
three successful baselines and nine output-failure/recovery controls. Its twelve
cases are the complete I/O group scope, rather than twelve failures. The total
**28 group cases** includes overlapping baselines and is not a unique-scenario
or cumulative execution count. The 27 CPU controls and earlier shell/semantic
receipts are separate.

Evidence directories:

```text
/tmp/kv-application-completion-allocations-h3e6xd4n
/tmp/kv-application-completion-output-ccnqunia
```

Independent read-only review cleared the whole-body effect guard, baseline IP
and request-prefix binding, and explicit source-release semantics. No live ACK
checkpoint or registered Rust-test runtime receipt is claimed.

## Entry and finite cases

The current reserved query arguments are:

```text
kv-tool --lanius-complete-bash END RAW_TRIM RAW_PREFIX COMPLETE_WORD...
```

These tests use END `1` and empty RAW_TRIM. The decoder, canonical context,
candidate generation and measured reply encoder are the real application path.
The three allocation profiles are:

| Profile | Raw prefix | Complete words | Owners reached |
| --- | --- | --- | --- |
| Root Candidates | `p` | none | Argument snapshots, one decoded byte, candidate backing and reply staging |
| Files | An opening single quote followed by `db space` | `put` | Argument snapshots, eleven decoded bytes and reply staging |
| None | empty | `@sentinel.rsp` | Argument snapshots, thirteen decoded bytes and reply staging; no response load |

Every baseline must match the complete independent frame exactly. The three
actual allocation-length schedules must differ. Required decoded, snapshot-byte,
reply and Candidates' 32,768-byte backing requests must occur. This is not a
unique role assignment when two owners happen to request the same size.

For each profile, the allocation group derives **every actual reached source
mmap position** from its successful baseline. It denies each position once,
requiring status 4, the exact allocation diagnostic, **empty stdout**, unchanged
fixture files and complete explicit source cleanup. Counts are derived at
runtime; there is no historical allocation-count floor. The group includes
three healthy baselines plus its individually reached denials, and stops rather
than silently truncating a schedule beyond its focused 32-position bound.

The output group has twelve cases. Candidates and None each run a baseline,
first-write EIO and first-write EINTR recovery. A Files query with a 1,200-byte
prefix adds a baseline, first-write EIO/EINTR, a second-write EIO after a real
1,024-byte successful stdout prefix, a finite 64-EINTR attempt-cap case and a
real closed-reader EPIPE. Error cases require status 3 and the exact I/O
diagnostic; interruption recovery must deliver the complete frame. The bounded
64-call injection ends before the diagnostic writer. The EPIPE case uses a real
pipe with its read end closed, restores inherited signal dispositions, observes
the application's explicit SIGPIPE policy and requires an uninjected EPIPE.
No synthetic short-write return is mistaken for actual published bytes.

## Provenance and ownership

The 155-line oracle imports the unchanged KV application runner/full-trace
ledger and existing shell frame oracle. It copies neither an ELF scanner nor a
native resource ledger. The current raw verifier admits exact source allocator
instruction sites, executable ranges and verified `0x22`/`0x62` flags, without a
named fallback. Full-width pointers and every requested allocation/free length
remain checked by the unchanged source ledger.

No runtime startup mapping is assumed to be the first or nth source allocation.
Only verified source sites supply denial positions; an unrecognized mapping
fails admission instead of becoming an owner by trace order. This fixture makes
no startup-allocation failure claim. Every injected position must be reached and
retain its baseline source IP, exact request arguments and complete preceding
mmap prefix. No extra unexplained injection is accepted.

All syscalls are observed. Only the validated initial launch and final
status-matched exit are normalized by the unchanged helper. The entire body is
then limited to source mmap/munmap, standard stdout/stderr writes and explicit
signal setup. Reads, opens, metadata, response-file/database accesses, transient
namespace changes, networking and subprocesses are rejected. Invalid sentinel
response/database files remain byte-identical. The completion query never
constructs a response provider or enters the database workflow.

All source owners must be released by successful observed munmap calls before
the validated terminal exit. This uses explicit release evidence, not operating
system cleanup on exit. No live `/proc` ACK checkpoint is claimed for this real
application. Allocation, decoded-word, candidate and staged-reply lifetimes
remain the application's manual ownership responsibility.

## Focused commands

Root may reuse the admitted executable:

```sh
timeout --kill-after=2s 100s python3 -B tests/fixtures/extended/cli_complete/resources_oracle.py target/stdlib-work/completion-kv.elf allocations
timeout --kill-after=2s 100s python3 -B tests/fixtures/extended/cli_complete/resources_oracle.py target/stdlib-work/completion-kv.elf output
```

Each child has an eight-second timeout, new child admission stops after the
70-second group budget, and the Rust wrapper allows 95 seconds. Evidence files
are retained in the reported temporary directory. Each group prints one finite
receipt; repeated baselines are not unique scenarios or cumulative acceptance
counts. The two registered filters in
`tests/extended_cli_completion_resources_execution.rs` are:

```text
completion_query_each_reached_source_allocation_fails_without_partial_reply_or_file_access
completion_query_output_failures_release_decoded_candidate_and_reply_owners
```

CPU-only controls:

```sh
python3 -B tests/fixtures/extended/cli_complete/resources_oracle.py controls
```

The accepted finite target is native Linux x86_64 CPU code emitted by the GPU
compiler. Requirements include Python 3, strace with bounded injection and
`--kill-on-exit`, and objdump for the unchanged verifier. There is no user-program
GPU, general shell, arbitrary workload or performance claim.

## Frozen inputs

| Input | SHA-256 |
| --- | --- |
| `resources_oracle.py` | `31253db6fb082703491b4fd30835ff02a6f9ddd2e876bd8c444e09113f60bc78` |
| Rust driver | `f6e27b2f1892c559566cd7679d037e8478d13a9285c10358d830b02625d1a4b6` |
| Application source | `9a83795a50c4b5a8ea6e11edcb4835d7b15e7735c92166864d15eb2edecec0d8` |
| Retained `completion-kv.elf` | `bcd80b7c400d26cd5cc67f6760aa81c4775bd59376a048061b23be273a3f413f` |
| Unchanged KV full-trace helper | `f7adcfca8bf50401e3ebdc70de65c839a4b5c7992b549ef0199b0a8674ec39f7` |
