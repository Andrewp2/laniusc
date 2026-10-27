# Owned key-value snapshots

`ext::kv` stores arbitrary byte keys and values in owned memory, supports checked
mutations and lookup, and reads and writes a versioned binary snapshot. The
`kv-tool` program now delegates snapshot publication to
[`std::atomic_file`](stdlib-atomic-files.md), using the shared TempFile owner.
Bounded response-file preprocessing compiles and passes its focused 55-case
direct native group. Earlier hierarchy/publication receipts retain their
source-specific scope below. Production code is Lanius; Python is only an
independent test oracle. The
[application receipts](#current-application-receipts) separate those source revisions.

## Storage and ownership

A `Store` owns one packed byte arena and one sorted index of scalar offsets and
lengths. Key identity is exact byte equality. Empty keys and values, NUL bytes,
and non-UTF-8 bytes are valid. Keys sort lexicographically by unsigned byte value,
with a shorter prefix before its extension. There is no text normalization.

```text
new() -> Store
default_limits() -> Limits
Store.borrow() -> &Store
Store.len() / Store.byte_len() -> i32
Store.is_empty() -> bool
Store.entry(index: i32) -> Result<Entry, Error>
Store.get(key: View<u8>, max_work: u64) -> Result<Option<View<u8>>, Error>
Store.put(key: View<u8>, value: View<u8>, limits: Limits) -> Result<Put, Error>
Store.remove(key: View<u8>, max_work: u64) -> Result<bool, Error>
Store.destroy()

Entry { key: View<u8>, value: View<u8> }
Put = Inserted | Replaced
encode(store: &Store, max_output: i32, max_work: u64) -> Result<Vec<u8>, Error>
decode(input: View<u8>, limits: Limits) -> Result<Store, Error>
```

`entry(0)` through `entry(len()-1)` provide checked iteration in sorted key order.
`get` distinguishes an absent key (`None`) from an empty stored value (`Some`
with length zero). `put` reports insertion or replacement; the store retains no
old version. `remove` reports whether a key existed. Removing an absent key
does not allocate or change the store.

Lookup uses binary search. Mutations build a complete compact replacement arena
and index, then swap owners only after every allocation and copy succeeds. A
failed mutation preserves contents, allocation addresses, and existing borrowed
views. Successful mutation invalidates all views, including an identical-value
replacement. A supplied key or value may borrow the current store: old storage
stays alive until copying finishes. Each successful mutation takes linear time
in the resulting live bytes and entry count, in addition to lookup, and can
temporarily hold both complete stores. This is a bounded whole-store design;
it has no append log, page cache, tombstones, or hidden obsolete-value growth.

Copies of `Store` alias ownership. Keep one active owner and destroy it once.
Entry and value views borrow the owner and must not be modified or retained
across successful mutation or destruction. Public record fields are an
implementation detail. Logical input view metadata is checked; callers must
provide real physical backing and keep it live and unchanged during calls.

## Limits and work

`Limits` contains these fields:

| Field | Default | Meaning |
| --- | ---: | --- |
| `max_entries: i32` | 65,536 | Final entry count for put; declared count for decode |
| `max_key: i32` | 65,536 | Supplied put key or each decoded key |
| `max_value: i32` | 16,777,216 | Supplied put value or each decoded value |
| `max_bytes: i32` | 67,108,864 | Sum of live key and value bytes |
| `max_snapshot: i32` | 68,157,440 | Complete input snapshot byte count for decode |
| `max_work: u64` | 536,870,912 | Budget for one operation |

Negative signed limits or invalid/overflowing view ranges return `Bounds`.
Exact fits succeed. `put` applies key/value limits to the supplied replacement,
and entry/byte limits to the resulting store; it does not revalidate unrelated
entries against newly lowered per-item limits. `max_snapshot` applies to decode;
encoding takes its own complete-output bound. Limits are passed per call and
are not stored in the owner. Backing index size must also fit the vector's
signed allocation byte range, otherwise `SizeOverflow` is returned.

Work units are abstract operation charges, not machine instructions or literal
memory-read counts. A key comparison charges one unit plus one per compared
byte pair. A mutation additionally reserves two units per resulting arena byte
(initialization and copying) and one per resulting index entry before allocating.
Encode reserves three units per complete snapshot byte and one per entry.
Decode reserves three units per input byte, then charges adjacent key comparisons
and one per entry. These rules bound scanning and copying with a fixed constant
factor; each CRC byte uses the existing bounded CRC-32 primitive. Lookup charges
only visited comparisons. An empty-store lookup can therefore succeed with zero
work units. No hash collision behavior affects these bounds.

Errors are `Bounds`, `EntryLimit`, `KeyLimit`, `ValueLimit`, `ByteLimit`,
`SnapshotLimit`, `WorkLimit`, `AllocationFailed`, `SizeOverflow`, `Truncated`,
`Signature`, `Version`, `Header`, `Checksum`, `Order`, `DuplicateKey`, and
`TrailingData`. All error paths release newly allocated intermediate owners.

## Snapshot version 1

All integers are unsigned 32-bit little endian. Sizes must also fit the signed
Lanius limits above. The format is defined here, rather than inherited from a
host database. The 24-byte header is:

| Byte offset | Field |
| --- | --- |
| 0 | Eight magic bytes: `4c 41 4e 49 4b 56 0d 0a` (`LANIKV\r\n`) |
| 8 | Version, exactly 1 |
| 12 | Number of entries |
| 16 | Payload byte length |
| 20 | Reserved field, exactly zero |

The payload has exactly the declared number of records. Each record contains
`key_length`, `value_length`, then that many key bytes and value bytes. Keys must
be strictly increasing in the byte order described above. Duplicate and unsorted
keys are errors. A four-byte CRC-32/ISO-HDLC follows the payload and covers the
entire header and payload, excluding the CRC field. The CRC is stored little
endian. Thus an empty snapshot contains 28 bytes. CRC detects accidental
corruption; it provides no authentication or encryption.

Encode always produces this canonical order. Decode validates magic, version,
reserved bits, declared size/counts, checksum, every record extent, key ordering,
and limits before allocating index or byte storage. Extra records, payload bytes,
or bytes after the checksum are rejected. The result owns independent copies;
the input can be released after decode returns. Future versions are rejected
explicitly rather than guessed. There are no compatible legacy formats.

## Native file CLI

Compile with:

```sh
target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended sample_programs/library/kv_tool.lani -o target/stdlib-work/kv-tool
```

Commands are:

```text
kv-tool init DB
kv-tool put DB KEY_HEX VALUE_HEX
kv-tool remove DB KEY_HEX
kv-tool get DB KEY_HEX
kv-tool list DB
kv-tool check DB
kv-tool --help
kv-tool put --help
```

Command names match exactly. Root-global `-h`/`--help` is inherited by every
command, and generated help describes the selected command. The root accepts
options before command selection; leaves use OptionsFirst, so their first DB
operand ends option recognition. Put help before DB, for example
`kv-tool put --help` or `kv-tool -h put`. Parse the complete expanded command
line before help or database access: unknown commands/options and extra operands reject even
with help; missing required operands are waived only for help. Without help,
the application checks each command's exact operand count.

An actual `--` ends both option recognition and command routing. A dashed DB
name therefore uses `kv-tool init -- --help` or
`kv-tool put -- -db.kv 00 ff`; DB bytes remain unchanged. This is an intentional
parsing change from the earlier positional-only CLI, which treated `--help`
and `--` in the DB position as ordinary names. A terminator before a command
leaves no selected command and fails. At a selected leaf, a DB named `list` or
another command remains an operand. No path normalization or UTF-8 conversion
is introduced.

Help renders through `ext::cli_help` into a 4,096-byte logical view backed by a
fixed caller stack array,
then permits at most 64 write attempts, each at most 1,024 bytes, including
EINTR and short progress. Help failure returns 3 and may expose a confirmed
stdout prefix. A checked SIGPIPE-ignore policy runs before argument ownership
or any output; failed installation returns 3 without writing. This policy
allows explicit owner cleanup after a real closed-reader write failure.
Other data-output operations retain their existing I/O contracts.

### Response files

`@path` splices response-file arguments before command parsing, including after
`--`. For example, `kv-tool @update.rsp` can read
`put 'db name.kv' 00ff 80ff00`. ASCII space/TAB/CR/LF separate tokens; matching
quotes group bytes and adjacent pieces concatenate. Backslash quotes the next
byte. Empty quoted arguments, non-UTF-8 bytes and literal `#`, `$`, `*` and `~`
are preserved. NUL, an unfinished quote or a trailing backslash reject.
There is no shell expansion or comment syntax. Original host argv is already
tokenized and is not reparsed as quoted text.

`@` alone is literal; `@@text` emits literal `@text` without expanding again.
Thus a DB named `@db.kv` uses `kv-tool init @@db.kv`, also after a parser `--`.
This is an intentional change to ordinary argv containing leading `@`/`@@`.
Quoting inside a response file does not disable expansion. `@-` reads a file
named `-`, not stdin. All relative nested references use the process's stable
cwd, not the including file's parent. Absolute paths retain native semantics.
The single-threaded app never changes cwd; the provider borrows AT_FDCWD.
It rejects a final symlink and nonregular input, using read-only, CLOEXEC,
NONBLOCK and NOCTTY flags. Ancestor symlinks and absolute paths are ordinary
host lookup; no directory confinement or atomic file snapshot is promised.

The complete schema is admitted before provider use. Complete preprocessing
then precedes command parsing, help and every database operation. Explicit
response files can therefore be read even when expanded CLI syntax rejects
or requests help. Ordinary arguments without directives add no file access.
Expansion owns stable copies, source bytes and final argument views until the
database outcome returns, then releases them on success or failure. Store,
path splitting and atomic-publication code are unchanged.

| Expansion limit | Value |
| --- | ---: |
| Raw argv count / aggregate bytes | 8 / 262,144 |
| Final arguments / aggregate output bytes | 8 / 262,144 |
| One argument / one response file bytes | 262,144 / 262,144 |
| All source bytes, including original argv | 1,048,576 |
| Tokens, including directives and initial argv | 256 |
| File loads / nested file depth | 16 / 8 |
| One response path bytes | 4,095 |
| Expansion work units | 8,388,608 |
| Native provider calls, including close/EINTR | 4,096 |

Repeated loads count again; cycles stop at a finite limit. Exact file-byte caps
require actual EOF, with at most one excess byte consumed to reject oversize
input. These limits bound retained library owners and work; they are not an
exact heap/RSS cap or filesystem wall-time deadline. See the
[response-file contract](library-response-files-plan.md).

Syntax, resource and nonregular-file failures return 2; ordinary provider I/O
returns 3; allocation failure returns 4. Primary close or simultaneous cleanup
failure returns existing status 8 while preserving the primary diagnostic.
No failed preprocessing reaches database operations or publishes partial argv.

### Database operands

Keys and values in arguments use even-length hexadecimal, accepting either
letter case. An empty shell argument represents empty bytes. `get` writes the
exact value bytes without a newline. `list` writes lowercase key hex, a tab,
value hex, and LF for each entry in sorted order. `check` validates the complete
snapshot and writes nothing. Mutation commands write nothing on success.
`init` uses atomic NoReplace publication; it does not check existence before a
replacing rename. An existing destination is a conflict, including a dangling
symlink, and a concurrent creator cannot be silently overwritten. For example:

```sh
kv-tool init ./example.kv
kv-tool put ./example.kv 00ff 68656c6c6f00
kv-tool get ./example.kv 00ff
```

### Anchored publication and cleanup

Mutating commands split DB at its last raw slash, keeping the parent bytes and
one final component. They reject empty paths, paths longer than 4,095 bytes,
empty or over-255-byte final components, `.` and `..`. A trailing slash or `/.`
is rejected rather than normalized to a different destination. A bare filename
uses `.` as its parent; `/name` uses `/`. Non-UTF-8 path bytes are preserved.
The parent is resolved and opened once as a directory with CLOEXEC. Updates
load DB with open_at against that anchor, and publication uses the same anchor
and raw final component. The read-only commands keep their existing pathname
behavior. Initial parent symlinks are resolved by that one open, not repeatedly
looked up during publication.

The caller must hold exclusive or cooperative mutation authority over this
parent namespace throughout the operation. Directory anchoring fixes parent
identity, including after a parent rename; it cannot protect temporary child
names against hostile directory writers. The tool does not lock the database
or prevent concurrent read/modify/write lost updates. Existing open readers and
other hard links can retain the previous inode. An update reads an existing DB
symlink normally, then Replace acts on that destination entry itself, leaving
its former target unchanged. The separate [SQLite adapter](extended-sqlite.md)
provides native database transactions.

Keys/values are validated, the complete old snapshot is decoded, and the
mutation and canonical encoding finish before any temporary file is created.
The app then calls AtomicFile create_in, bounded write_all and commit. It has no
caller SCRATCH argument, compatibility form, custom name generator, open/truncate
publication or duplicated rename/sync workflow. Init selects NoReplace; put and
successful remove select Replace. Removing an absent key does not create or
publish a temporary file.

AtomicFile uses exclusive no-follow creation of a fresh `.tmp-` name from OS
entropy in the anchored directory, requesting private `0600` permissions. It
syncs the complete file, closes it once, renames once, records publication before
further fallible calls, and syncs the directory. Prior ownership, mode, ACLs and
timestamps are not preserved. Sync guarantees depend on the selected local
filesystem and device; these operations do not establish survival of every
power loss. See the [atomic publication contract](stdlib-atomic-files.md) for
namespace authority, platform limits and native acceptance status.

Confirmed NotPublished errors preserve the old destination. An ambiguous rename
failure remains visibility-unconfirmed: the app does not retry rename, infer
rollback or claim the old DB survived. If rename succeeded but directory sync
failed, the app reports that the snapshot was published with directory sync
unconfirmed. It closes the retained anchor without retrying sync or upgrading
that durability result. Published destinations are never unlinked as cleanup.

Every acquired input file and parent descriptor is closed once. Atomic cleanup
errors are checked independently of the primary failure and preserve publication
facts. If temporary removal remains unconfirmed, the app writes
`kv-tool: retained temporary name in database directory: ` followed by the live
37-byte name and LF before its final diagnostic. It then explicitly keeps that
named residue and cleans up the remaining descriptors/backing, without a second
unlink. The caller must arrange later recovery of that reported name. Successful
later cleanup cannot erase the earlier failure or make an uncertain publication
durable. There is no automatic cleanup on process death or crash scavenger.

The CLI caps input snapshot bytes at 9 MiB, live bytes at 8 MiB, entries at 4,096,
each key at 64 KiB, each value at 4 MiB, and work at 128 Mi units. It caps captured
arguments at eight and their combined bytes at 256 KiB. Hex arguments are also
subject to the host's argument-size limit. A listing can contain at most 18 MiB.
Publication permits at most 9 MiB confirmed bytes and 1,048,576 write attempts,
including short-write and EINTR attempts, with at most 1,024 bytes per attempt.
It retains TempFile's 32 candidate and 128 entropy-call defaults and permits one
directory-sync attempt. These are finite attempt/work bounds, not deadlines:
kernel opens, writes and syncs can block.

| Exit status | Meaning |
| --- | --- |
| 0 | Success |
| 2 | Invalid arguments, malformed snapshot, existing DB on init, or resource limit |
| 3 | Ordinary file/stream operation or output failed |
| 4 | Allocation failed |
| 5 | Absent key on get or remove; no diagnostic |
| 6 | Snapshot published, directory sync unconfirmed |
| 7 | Publication visibility unconfirmed |
| 8 | Cleanup failed, preserving any earlier failure and publication diagnostic |

When stderr is writable, init conflict emits
`kv-tool: database already exists` plus LF. Status 6 emits
`kv-tool: snapshot published; directory sync unconfirmed` plus LF; status 7 emits
`kv-tool: publication visibility unconfirmed` plus LF. A combined primary and
cleanup failure preserves its primary diagnostic, appends
`kv-tool: cleanup failed` plus LF, and returns 8. A cleanup-only failure after
fully synced publication emits `kv-tool: snapshot published; cleanup failed`
plus LF. Failed stderr delivery preserves an already nonzero status, including
6, 7 or 8, so it cannot hide publication or cleanup facts. An output failure
without an earlier failure returns 3. Malformed input/resource, ordinary I/O and
allocation diagnostics retain their existing wording.
Read-only `get`/`list` output can contain a prefix on stdout I/O failure.

## Verification

`tests/extended_kv_execution.rs` executes GPU-compiled x86_64 Linux Lanius. Tests
compare deterministic operation sequences to a Rust `BTreeMap` model, compare
canonical snapshots to a Python `struct`/CRC oracle, load independent snapshots,
exercise arbitrary bytes and empty keys/values, verify native selected views
and input independence, and cover exact limits and bounded work. Corruption
cases include truncation, CRC damage, lengths/counts, version/reserved fields,
duplicate and unsorted keys, and trailing bytes. Allocation denial checks each
observed store allocation and frees all owners. These portable Store and binary
snapshot contracts are unchanged by this application migration.

### Current application receipts

The response-file application is frozen at SHA-256 `789143f6...`. Compile exit
0 is recorded in `target/stdlib-work/response-kv-compile-first.log`; its ELF is
SHA-256 `00889c44...`. The focused `responses` group passes **55 process group
cases** in `response-kv-native-artifact-retry.log`, including all 18 allocation
denials derived from the successful nested-help baseline. Those 18 cover that
baseline's argv/expansion/source-file owners, not every allocation path in the
whole application. A separate post-database-open allocation failure is also
included in the 55, alongside the published/unsynced status 6 case.

The group checks ordinary no-file-access behavior, response-backed complete Store
operations, fixed-cwd nesting, quotes/raw/escaped paths, expansion after `--`,
malformed/nonregular input, depth/file/count/EOF limits, dynamically reached
response-owner OOMs, I/O recovery, real EPIPE, and preserved database failure
outcomes while the expansion owner remains live. All syscalls are observed;
expected response-path/fd generations close before database effects and all
source mappings/fds release before the validated native exit. Ten response-effect
and eleven artifact-name CPU controls pass separately.

The first group attempt (`response-kv-native-first.log`) ran ten cases, then
failed in Python artifact naming before launching case11: `@sub/start.rsp`
became part of an artifact path. The corrected oracle uses a stable counter
and validated label, never argv. No compiler/runtime or application change
was required; the unchanged ELF passed the full retry. Those first ten partial
cases are not added to 55. Oracle SHA-256 is `057bb27a...`; the fixture guide
records full identities and the independently reviewed scope.

These are direct Python process cases with baselines/overlap, not a passing
Rust libtest. The registered KV driver separately built with `--no-run` alongside
the native response-resource driver in 2.09 seconds combined
(`response-resource-kv-drivers-build-first.log`), producing
`extended_kv_execution-3b7e887700dd7ba6`. That is shared build time, not a
per-driver measurement, and adds no native cases.
The earlier 130-case hierarchy and 64-case atomic campaigns were not rerun on this source
and are not added to 55. This is finite native Linux x86_64 CPU execution emitted
by the GPU compiler on local ext4, not user GPU-kernel or broader-host support.

### Historical hierarchy application receipts

The earlier hierarchy application is frozen at SHA-256 `f07fd52f...`. Its command
collection and generated help reuse
the [frozen command hierarchy contract](library-cli-commands-plan.md). The
database operations, snapshot encoding and AtomicFile workflow retain their
previous code and outcome contracts. That campaign used the unchanged
verified raw allocator authority
with full-width source/fd accounting and explicit signal-event admission.
Twenty-four hierarchy CPU controls and eleven existing read/open binding controls
pass separately, as do 48 helper CPU controls; these are not native cases.

That source compiled and passed all three direct Python groups with
full syscall observation. Logs under `target/stdlib-work/` record:

| Gate | Receipt for that source |
| --- | --- |
| Compile | `cli-commands-kv-admission-first.log`, exit 0 |
| Hierarchy | `cli-commands-kv-hierarchy-all-syscalls.log`, 66 process group cases |
| Round trips | `cli-commands-kv-roundtrips-all-syscalls.log`, 33 process group cases |
| Publication | `cli-commands-kv-publication-all-syscalls.log`, 31 process group cases including all 13 reached source OOM positions and 15 I/O controls |

These total 130 group cases with overlapping setup/baselines, not independent
properties or three passing Rust libtests. The helper observes every syscall,
validates exactly one successful launch of the expected executable and one
final exit from the raw image with the captured process status, and rejects
all other calls outside the admitted application set. Source mappings must
be explicitly released and acquired fd generations closed by observed calls
before that exit; process death cannot satisfy cleanup. Help and CLI-syntax,
arity or hexadecimal rejection admit only signal policy, argument ownership
and output calls between those endpoints.

The first `cli-commands-kv-{hierarchy,roundtrips,publication}-first.log` runs
used a selected-call trace filter. Independent review found that unlisted
calls such as `unlink` or `socket` could be invisible. The corrected helper and
oracle reran all three groups against the unchanged ELF; those earlier 130
partial-observation cases are repeated coverage and are not added to 130.
This was an oracle observation gap; no application/library defect was found.

The registered tests were not executed through libtest for this receipt.
Its registered driver built successfully with `--no-run` in 51.67 seconds
(`cli-commands-kv-driver-build-first.log`); this is separate build admission,
with no additional native cases.
That campaign's oracle/helper hashes are `b3ec740f...`/`f7adcfca...`; ELF SHA-256 is
`46770678...`; flat parser `ext::cli` is `9f11981f...`, hierarchy `6eb4db7a...` and
help `a7198a2a...`. The fixture guide records full identities. The 66-case group
accepts root and six child help goldens, exact/over snapshot limits, complete
parse/help policy, no filesystem calls on help/rejected CLI input, real EPIPE and
escaped raw/command-looking DB paths. The other two groups preserve complete
snapshot equality and publication/error/cleanup outcomes on that source.

This is finite native Linux x86_64 CPU execution emitted by the GPU compiler;
it does not establish user GPU-kernel or broader-host support. The earlier
64-case source revision below remains historical and is not added to 130.

### Historical atomic-publication application receipts

The earlier `kv_tool.lani` compiled to a native x86_64 Linux executable
and passed both focused application groups against that reused ELF on the
selected local ext4 profile. The receipts under `target/stdlib-work/` are:

| Gate | Result | Receipt |
| --- | --- | --- |
| Application syntax retry | Compile exit 0 | `kv-tool-atomic-syntax-retry-compile.log` |
| Round trips | 33 process invocations | `kv-tool-atomic-roundtrips-first.log` |
| Publication | 31 process invocations, including 13 reached source ENOMEM and 15 I/O controls | `kv-tool-atomic-publication-first.log` |

The two runtime groups total **64 process invocations**; compilation is not an
additional runtime case. Their Python logs report counts without durations.
The accepted source SHA-256 is
`9de65a6cf8b42e923dd39d8374b26ed1216da63430a04359c76fb19e990e6cbe`.
The [application fixture guide](../tests/fixtures/extended/kv_publication/README.md)
records exact test filters, fault binding and evidence boundaries.

Round trips compare complete canonical snapshot bytes with an independent
struct/CRC oracle. They cover binary and empty keys/values, replacement,
sorted list/get/check/remove, absent keys, corrupt snapshots, application
bounds, raw non-UTF-8 names and rejection of the old SCRATCH argument form.

Publication derives every reached source allocation in its successful Replace
baseline and binds injected ENOMEM to the actual instruction, requested size,
flags and preceding allocation prefix. Bound I/O controls cover opens, reads,
writes, EINTR retries, file sync, ambiguous rename, directory sync, combined
write/unlink failure and an undeliverable publication diagnostic. The cases
independently observe old or complete new target bytes, exact statuses/messages,
the actual retained recovery name, and explicit source/descriptor release.
In particular, directory-sync failure leaves the complete new snapshot and
status 6; failure to deliver its stderr diagnostic still leaves status 6.
The injected skipped-rename EIO case observes the old target, while correctly
retaining visibility-unconfirmed status 7 rather than claiming rollback.

The NoReplace race creates a distinct complete destination winner after init
has acquired its private candidate. Actual EEXIST, status 2, unchanged winner
and cleanup of only the owned candidate are checked. It does not alter the
temporary name or use a timing ratio as the correctness oracle.

The first application compile, recorded in
`target/stdlib-work/kv-tool-atomic-first-compile.log`, stopped before native
execution with `LNC0016` at `kv_tool.lani:121:52`: this source grammar does not
accept block arms in match expressions. The application now matches scalar
tags and uses if branches in `atomic_failure` and `report`; output and outcome
contracts are unchanged. This was an application syntax correction, with no
compiler changes. The AtomicFile library smoke had already compiled and run.

The five portable Store/contract/model/snapshot/limit/allocation tests were not
changed by the application migration. Earlier caller-scratch CLI receipts remain
historical, separate from these accepted replacement gates. This finite native
coverage is not GPU-kernel execution, a universal power-loss durability test,
a network-filesystem guarantee, locking or concurrent database transactions.
Synthetic close-failure injection is excluded from this application campaign:
the host tracer skips the real close, and the CLI has no fixture-only repair
hook. Additional filesystem/platform, input-size and fault schedules need their
own evidence.
