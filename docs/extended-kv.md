# Owned key-value snapshots

`ext::kv` stores arbitrary byte keys and values in owned memory, supports checked
mutations and lookup, and reads and writes a versioned binary snapshot. The
`kv-tool` program uses real native file operations to replace a snapshot through
an explicitly supplied scratch path. Production code is Lanius; Python is only
an independent test oracle.

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
kv-tool init DB SCRATCH
kv-tool put DB SCRATCH KEY_HEX VALUE_HEX
kv-tool remove DB SCRATCH KEY_HEX
kv-tool get DB KEY_HEX
kv-tool list DB
kv-tool check DB
kv-tool --help
```

Keys and values in arguments use even-length hexadecimal, accepting either
letter case. An empty shell argument represents empty bytes. `get` writes the
exact value bytes without a newline. `list` writes lowercase key hex, a tab,
value hex, and LF for each entry in sorted order. `check` validates the complete
snapshot and writes nothing. Mutation commands write nothing on success.
`init` requires a missing DB and refuses an existing readable file. For example:

```sh
kv-tool init ./example.kv ./example.scratch
kv-tool put ./example.kv ./example.scratch 00ff 68656c6c6f00
kv-tool get ./example.kv 00ff
```

DB and SCRATCH must have matching lexical parent paths and distinct normal
filenames. SCRATCH is a caller-owned disposable path: opening it creates or
truncates it. The caller must ensure it is not a symlink or hard link to DB or
another file that must be preserved, and that other processes do not use either
path during the operation. Lexical checks cannot establish filesystem identity
or prevent path races. No generated or fixed temporary filename is used.

The CLI fully reads, decodes, mutates, and encodes before opening scratch. It
writes the complete snapshot with checked short-write/EINTR handling, closes
the scratch owner once, and then performs one checked native rename. The old DB
bytes are unchanged on errors before a successful rename. A failed write, close,
or rename attempts to unlink scratch; if cleanup itself fails, a disposable
scratch file may remain. A successful rename is the replacement commit point.
`remove` of an absent key does not touch either file.

This provides checked file replacement during ordinary process execution.
It does not call `fsync`, lock files, obtain exclusive creation, or provide
concurrent database transactions or crash durability. Those services are not
available in the current bindings. Renaming replaces the destination file inode
with the scratch inode; new-file permissions follow the host umask, and prior
ownership/ACL metadata is not preserved by this tool. SQLite and other durable
database services remain separate host dependencies.

The CLI caps input snapshot bytes at 9 MiB, live bytes at 8 MiB, entries at 4,096,
each key at 64 KiB, each value at 4 MiB, and work at 128 Mi units. It caps captured
arguments at five and their combined bytes at 256 KiB. Hex arguments are also
subject to the host's argument-size limit. A listing can contain at most 18 MiB.

| Exit status | Meaning |
| --- | --- |
| 0 | Success |
| 2 | Invalid arguments, malformed snapshot, existing DB on init, or resource limit |
| 3 | File/stream operation or diagnostic write failed |
| 4 | Allocation failed |
| 5 | Absent key on get or remove; no diagnostic |

Other failures emit one short diagnostic when stderr is writable. No snapshot
prefix is published to DB on a parsing, mutation, encoding, or pre-rename I/O
failure. Read-only `get`/`list` output can contain a prefix on stdout I/O failure.

## Verification

`tests/extended_kv_execution.rs` executes GPU-compiled x86_64 Linux Lanius. Tests
compare deterministic operation sequences to a Rust `BTreeMap` model, compare
canonical snapshots to a Python `struct`/CRC oracle, load independent snapshots,
exercise arbitrary bytes and empty keys/values, verify native selected views
and input independence, and cover exact limits and bounded work. Corruption
cases include truncation, CRC damage, lengths/counts, version/reserved fields,
duplicate and unsorted keys, and trailing bytes. Allocation denial checks each
observed store and CLI allocation and frees all owners; native file faults check
DB preservation before rename, scratch cleanup, and interrupted I/O retries.
