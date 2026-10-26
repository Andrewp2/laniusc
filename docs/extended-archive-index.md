# Persistent indexed ZIP snapshots

`ext::archive_index` combines [ZIP](extended-zip.md) and
[native SQLite](extended-sqlite.md). It saves an exact ZIP snapshot and an
ordinal catalog in one database transaction. The `archive-index` application
imports binary stdin, lists binary names safely, retrieves an entry by ordinal,
and exports the saved archive. It never extracts a pathname onto the filesystem.

All seven focused runtime groups pass on **Linux x86_64/glibc**, compiling the
actual Lanius application on the GPU and executing its linked native ELF with
the system SQLite library. Other platforms and GPU-kernel execution have not
been established. There is no Rust, Python, alternate ZIP engine, or database
engine in production: Lanius calls the existing ZIP module and SQLite wrapper.

## Command line

```text
archive-index DB import KEY               # ZIP stdin; no stdout
archive-index DB count KEY                # decimal entry count + LF
archive-index DB list KEY                 # ordinal metadata, hex names
archive-index DB get KEY ORDINAL          # raw decoded entry stdout
archive-index DB export KEY               # exact saved ZIP stdout
```

Import replaces the whole selected archive key. The original archive file can
be changed or deleted afterward: every read uses the bytes saved in SQLite.
An empty archive is valid. Keys are counted BLOBs, including empty keys. Unix
arguments can contain arbitrary bytes except NUL; library callers can supply
NUL in a key. Use `--` before operands for keys beginning with `-`.

Ordinals are zero based and follow central-directory order. Duplicate names
remain distinct entries. Names retain their bytes, including NUL, high bytes,
slashes, backslashes, drive syntax and `..`. The application does no path
resolution or encoding conversion. `list` writes seven tab-separated columns:

```text
ordinal  method  flags  crc32  compressed_size  decoded_size  raw_name_hex
```

The first six columns are unsigned decimal. Method is `0` for stored and `8`
for DEFLATE. The last column contains lowercase hexadecimal, two digits per
name byte; an empty name has an empty last column. Each record ends with LF.
This encoding preserves names containing tabs and newlines without ambiguity.

The database path must be nonempty UTF-8, at most 4,096 bytes. Both application
and library reject exact `:memory:` and a leading `file:`. This avoids SQLite's
configurable URI interpretation selecting an in-memory or alternate database.
Read commands open `ReadOnly` and never create a missing file. Import opens
`Create`. Symlinks, device files, filesystem permissions and durability follow
the linked SQLite library and operating system.

## Library API and ownership

```text
Limits { zip: ext::zip::Limits, key_bytes: i32 }
default_limits() -> Limits
open(path: View<u8>, mode: ext::sqlite::Mode, limits: Limits)
    -> Result<Store, Error>

Store.borrow() -> &Store
Store.is_open() -> bool
Store.is_poisoned() -> bool
Store.replace(key: View<u8>, bytes: View<u8>) -> Result<i32, Error>
Store.load(key: View<u8>) -> Result<Snapshot, Error>
Store.close() -> Result<i32, Error>

Snapshot.borrow() -> &Snapshot
Snapshot.is_open() -> bool
Snapshot.len() -> i32
Snapshot.cursor() -> Result<ext::zip::Cursor, Error>
Snapshot.get(ordinal: i32) -> Result<alloc::vec::Vec<u8>, Error>
Snapshot.bytes() -> Result<View<u8>, Error>
Snapshot.verify() -> Result<i32, Error>
Snapshot.destroy()
```

`replace` returns the entry count. It borrows key and ZIP bytes for the call;
successful SQLite bindings copy their values. The caller keeps those views
unchanged until return. `load` creates an independent owned ZIP snapshot,
validates its complete structure, and compares every selected catalog row to
that directory. The snapshot remains usable after closing the store. `get`
allocates an independent decoded payload and checks its length and CRC.
`verify` extracts and checks all entries, releasing each decoded owner before
continuing; it returns the entry count.

`bytes` exposes the exact stored ZIP as a borrowed view. It does **not** perform
CRC verification. `cursor` exposes borrowed directory records; count and list
therefore validate structure and index consistency without decompressing every
payload. The CLI calls `verify` before exporting any bytes. Corruption of an
unselected payload is detected by `verify` or its own later `get`, rather than
inferred from its directory checksum.

Keep one active owner for each store, snapshot and returned vector. Descriptor
copies alias that owner. End every snapshot view, entry and cursor before
`destroy`; keep its bytes unchanged during their lifetimes. Destroy returned
vectors once. Closing a store and destroying a snapshot are idempotent on the
actual owner. A destroyed snapshot reports length zero and rejects access.
There is no automatic destruction, ownership checker or thread safety promise.
Do not modify public storage fields or use inactive owner copies.

## Schema and consistency

The database is dedicated to this format. It admits exactly three user schema
objects, with the exact versioned SQL emitted by the module and no triggers or
views. A singleton metadata row identifies format version 1. Unexpected schema
objects, differently declared tables and missing or different versions fail
explicitly. There is no migration, arbitrary SQL interface or compatibility
fallback.

| Table | Contents |
| --- | --- |
| `archive_index_meta` | singleton `id = 1`, `version = 1` |
| `archive_index_archives` | BLOB primary key, exact snapshot BLOB, entry count |
| `archive_index_entries` | composite primary key `(key, ordinal)`, raw name BLOB, method, flags, CRC, sizes, local span |

Both keyed tables use `WITHOUT ROWID`. Entry names are metadata rather than
keys. Queries bind binary keys and use the composite primary key; no key,
filename or archive name is interpolated into SQL. Metadata insertion reuses
one prepared statement with reset and rebinding.

Import first parses the entire ZIP and extracts **every** entry to check CRC,
decoded length and DEFLATE completion. A corrupt later entry therefore cannot
replace an earlier committed archive. Only after this pass does it begin
`BEGIN IMMEDIATE`, check schema and version again, delete the selected old
catalog, upsert its snapshot, insert the complete new catalog and commit.
The schema for a new empty database is initialized in its own transaction at
open. Failed input validation can leave that empty format database behind.

Load uses a `DEFERRED` read transaction covering schema/version checks, snapshot
copying and the complete ordered metadata comparison. It rejects missing,
extra, reordered or mismatched rows, bad scalar types and invalid ZIP structure.
Concurrent committed replacement cannot mix an old snapshot with a new index.
Validation concerns the selected archive; it does not scan other keys for
orphaned or corrupted rows. A valid import may repair the selected old snapshot
and catalog by replacing them.

## Errors and transaction outcomes

```text
Cause = Bounds | Limit | AllocationFailed | NotFound | Ordinal | Corrupt
      | Closed | Poisoned | ReadOnly | Database | Archive
Outcome = Unchanged | Uncertain
Error { cause, database: Option<ext::sqlite::Error>,
        archive: Option<ext::zip::Error>, rollback: Option<ext::sqlite::Error>,
        outcome }
```

The original error is captured before cleanup. Statements are finalized before
rollback or close; every partial Lanius allocation is released. Database errors
retain the SQLite wrapper's native code and phase. Malformed stored types can
be reported as a strict SQLite column error; ZIP errors retain their original
reason. Local key/owner failures have neither nested error.

Errors before replacement or after established rollback report `Unchanged`.
SQLite can automatically end a failed transaction. A COMMIT error after
autocommit is already restored cannot establish which durable version survived;
it reports `Uncertain`. Failure to roll back or inspect transaction state also
reports `Uncertain` and preserves a separate recovery error when available.
The store is then poisoned and permits only close; reopen and inspect the
database before deciding whether to retry. A successful native commit is not
undone because a later CLI stdout or close operation fails.

These distinctions follow SQLite's documented
[transaction error behavior](https://www.sqlite.org/lang_transaction.html) and
[autocommit state](https://www.sqlite.org/c3ref/get_autocommit.html). Atomicity,
locking, journal recovery and crash durability remain SQLite/VFS/filesystem
contracts. The module makes no stronger crash or failed-I/O guarantee. It does
not change journal, synchronization or global SQLite configuration. A damaged
SQLite file returns its native error; corruption need not be repairable.

## Budgets and stream behavior

| Option | Default | Accepted maximum |
| --- | --- | --- |
| `--max-input` | 8 MiB | 16 MiB |
| `--max-output` | 16 MiB | 64 MiB |
| `--max-entries` | 4,096 | 65,534 |
| `--max-entry` | 8 MiB decoded | 64 MiB |
| `--max-total` | 32 MiB decoded | `u64::MAX` |
| `--max-work` | 16,777,216 ZIP parser units | `u64::MAX` |
| `--max-key` | 1,024 bytes | 4,096 bytes |
| `--max-io-calls` | 65,536 | `i32::MAX` |

Unsigned decimal zero is admitted; exact bounds succeed when the underlying
format and SQLite hard limits permit. Repeated options use the last value.
`--max-input` also limits stored snapshots on read. The library admits ZIP
snapshots through 16 MiB and keys through 4,096 bytes. It uses SQLite's default
wrapper limits: 16 MiB columns and 32 MiB native values/whole rows. This leaves
room for record overhead at the snapshot maximum. SQLite build hard limits may
be smaller and then return explicit native errors.

The ZIP parser's work budget includes its quadratic overlap audit. Decoded
entry and total caps bound payload sizes; work units are not elapsed-time or
CPU-instruction guarantees. SQLite's compiled instruction cap does not bound
VM execution work or time. The fixed SQL and bounded archive entry count bound
the application's explicit loops; SQLite execution and blocking descriptors
still require an external process/deadline policy if elapsed time matters.

Input reads at most 1,024 bytes per attempt. One additional byte distinguishes
exact EOF from excess input and is never imported. Short transfers and EINTR
spend the shared read/write call budget; EAGAIN, invalid counts, host errors and
zero-progress writes fail. Every output is prepared and the store is closed
before the first stdout attempt. Input, integrity, lookup and output-size
failures publish no stdout. A later I/O failure or exhausted call budget can
leave an output prefix. Diagnostics have a separate eight-attempt budget and
preserve the original exit code even if stderr fails.

Memory includes the bounded input/snapshot, SQLite's transient binding copy and
native storage, a maximum decoded entry during validation, reusable name/schema
scratch and prepared output. Export currently copies the snapshot into its
output vector. The archive byte cap does not alone cap process memory; there
is no whole-process allocator quota. All allocation failures return errors.

| Exit | Meaning |
| --- | --- |
| 0 | Complete operation or help |
| 2 | Arguments, byte/entry/work limit or I/O attempt budget |
| 3 | Argument capture, stdin or stdout I/O failure |
| 4 | SQLite, allocation, closed or poisoned owner failure |
| 5 | Missing archive key or ordinal |
| 6 | ZIP integrity/format or stored catalog/schema inconsistency |
| 7 | Uncertain replacement outcome; reopen and inspect |

## Build and focused checks

From the repository root, using a rebuilt compiler in an absolute target path:

```sh
export CARGO_TARGET_DIR="$PWD/target/stdlib-build"
timeout --kill-after=2s 100s "$CARGO_TARGET_DIR/debug/laniusc" \
  --native-link --native-library sqlite3 \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/archive_index.lani -o /tmp/archive-index

timeout --kill-after=2s 20s /tmp/archive-index /tmp/catalog.db import backup < backup.zip
timeout --kill-after=2s 20s /tmp/archive-index /tmp/catalog.db list backup
timeout --kill-after=2s 20s /tmp/archive-index /tmp/catalog.db get backup 0 > first-entry
timeout --kill-after=2s 20s /tmp/archive-index /tmp/catalog.db export backup > saved.zip
cmp backup.zip saved.zip
```

`tests/extended_archive_index_execution.rs` has seven focused groups:

- Python `zipfile`/`zlib` and SQLite interoperability, duplicate/raw/UTF-8 names,
  binary keys, empty archives, replacement, exact export and independent owners.
- Exact and exceeded archive, entry, aggregate, work, key, output and I/O caps.
- CRC failure in a later entry before replacement; malformed snapshots,
  metadata, strict types, schema/version and unexpected trigger rejection.
- Test-only native faults after a catalog row was written, before and after
  native COMMIT, and during rollback; poisoned state, preserved first error,
  SQLite busy and actual descriptor failures.
- Every observed Lanius allocation position during import and selected reads,
  injected `ENOMEM`, old-content preservation and balanced direct mmap owners.
- A 1,024-entry workload with 8 MiB decoded data, mixed stored/DEFLATE payloads,
  duplicates and raw names. It reports import/query/export wall time, child CPU
  time and measured peak child RSS; these are observations, not guarantees.
- Actual sample helpers with scripted short reads/writes, EINTR, invalid counts,
  zero progress and bounded retry exhaustion.

The Rust driver, Python oracles and small C observer are test machinery.
Production behavior is entirely the Lanius module/sample and their existing
ZIP/SQLite dependencies. The accepted runtime receipts are:

| Receipt | Result |
| --- | --- |
| `target/stdlib-work/archive-index-matrix.log` | Matrix group passed in 8.27 s; 56 reported CLI cases plus the direct ownership contract |
| `target/stdlib-work/archive-index-failures-workload.log` | Remaining six groups passed in 17.16 s: corruption 30, allocation 31, limits 40, faults 9 and workload 11 reported CLI cases, plus scripted stream contracts |

The allocation group additionally injects failure at all 29 import and 23 read
allocation positions observed in its successful baseline runs. Each injected
run checks the committed snapshot and balances the Lanius allocator's direct
`MAP_32BIT` mappings. These positions exclude dynamic-loader, libc and CRT
setup mappings. The CLI case counters exclude direct ownership, native-fault,
scripted-stream and injected-allocation subprocess checks; they are not a
count of every assertion or every possible input.

### Measured workload

The accepted workload has 1,024 entries, 8,388,608 decoded bytes and a
8,005,812-byte ZIP snapshot. It mixes stored and DEFLATE entries, duplicate
names and raw binary names. After import, independent SQLite queries check
the saved snapshot and all catalog rows. The application then performs one
count, one complete list, seven ordinal gets and one verified exact export.

| Observation | Recorded value |
| --- | --- |
| Import wall time | 1.385475 s |
| Count/list/get/export wall time, combined | 4.422171 s |
| Child CPU time across those application processes | 5.766212 s |
| Peak child RSS reported by `getrusage(RUSAGE_CHILDREN)` | 55,868 KiB |

These are one host's measured process results for this fixed workload, not
throughput, memory or latency guarantees. Repeated read commands each load and
validate the saved snapshot and its complete catalog; this measurement does
not imply constant-time entry retrieval or a cache. The RSS observation is a
child-process high-water mark, not a whole-process memory quota or the sum of
all processes' allocations.

The passing gates establish the listed finite cases and failure positions.
They do not prove behavior for every corrupt database, SQLite VFS, concurrent
schedule, disk failure or power loss. Crash durability and recovery retain
the SQLite and filesystem limits described above.
