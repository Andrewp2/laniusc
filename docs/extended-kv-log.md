# Append-only key/value log

`ext::kv_log` is an embedded on-disk key/value store in the style of Bitcask. Every put and delete appends a CRC-checked record to one log file. An in-memory hash index maps each live key to the file offset of its newest value. Keys are kept in memory; values stay on disk and are read back on demand. `sync()` is the commit point, `open()` replays the log and cuts off a torn or corrupt tail, and `compact()` rewrites the live records into a new file that replaces the old one by rename.

It is a different module from [`ext::kv`](extended-kv.md). That module holds a sorted in-memory map and publishes whole snapshots. `ext::kv_log` writes only the change, so a put costs a record append rather than a snapshot rewrite.

## API

```text
ext::kv_log::open(path: View<u8>, options: Options) -> Result<Store, Error>
ext::kv_log::default_options() -> Options
Options { max_key: i32, max_value: i32, buffer: i32, sync_every: bool, auto_compact: i64 }
Store.put(key: View<u8>, value: View<u8>) -> Result<i32, Error>
Store.delete(key) -> Result<bool, Error>        // Ok(false): absent, nothing written
Store.get(key, out: &Vec<u8>) -> Result<bool, Error>   // Ok(false): absent
Store.contains(key) -> bool, Store.len() -> i32
Store.first() -> i32, Store.next(position) -> i32      // -1 at the end
Store.key(position) -> View<u8>, Store.value(position, out) -> Result<i32, Error>
Store.flush(), Store.sync(), Store.compact() -> Result<i32, Error>
Store.recovery() -> Recovery { records: i64, truncated: i64 }
Store.file_bytes(), live_bytes(), dead_bytes(), synced_bytes() -> i64
Store.close() -> Result<i32, Error>   // sync, then release
Store.destroy()                       // release without flushing
ext::kv_log::kind_name(kind: ErrorKind) -> View<u8>
Error { kind: Io | NotKvLog | KeyLimit | ValueLimit | AllocationFailed | Closed, host: i32 }
```

The defaults are a 64 KiB key limit, a 64 MiB value limit, a 1 MiB write buffer, no per-operation fsync, and auto compaction at 64 MiB of dead bytes. `host` carries the errno of an `Io` error when one is known.

`key()` borrows the store's key arena. The view stays valid until the next put of a new key or the next compaction.

## File format

The file starts with the 8-byte header `LKVLOG01`. Each record that follows has this layout:

| Field | Bytes | Meaning |
| --- | --- | --- |
| crc | 4 | CRC-32 (IEEE, the same as `zlib.crc32`) of every byte after this field |
| kind | 1 | 1 put, 2 delete |
| key length | 4 | little-endian u32 |
| value length | 4 | little-endian u32, 0 for a delete |
| key, value | n | raw bytes |

The index stores each value's absolute file offset. CRC-32 uses slicing-by-8 tables when the bytes are packed.

## Durability

- **Writes.** A put or delete is encoded into the write buffer and applied to the index at once. Later gets see it, and serve it from the buffer until it is written. The buffer is written with one positional write when it reaches `buffer` bytes, and on `flush`, `sync`, `compact` and `close`.
- **Commits.** `sync()` flushes, then calls `fdatasync`. Everything put or deleted before a successful `sync()` survives a crash or power loss, provided the disk honours fsync. Records that were written but not yet synced survive a process crash, because they are already in the page cache, but they are not guaranteed to survive power loss. `sync_every` syncs after every put and delete.
- **Recovery.** `open()` checks each record in turn: it must be complete, have a known kind and lengths within the format limits (1 MiB keys, 1 GiB values), and match its CRC. At the first record that fails, the file is truncated to the end of the last good record and synced. `recovery()` reports how many records were replayed and how many bytes were cut. A file shorter than the header whose bytes are a prefix of `LKVLOG01` is treated as a new log; any other header is `NotKvLog`. The format limits do not depend on `Options`, so a store opened with smaller limits never discards records written under larger ones.

Recovery therefore always yields a prefix of the operations in the log, and every committed operation is part of that prefix.

## Compaction

`compact()` writes the live records, in iteration order, to `PATH.compact` and fsyncs that file. It then renames it over `PATH`, fsyncs the parent directory, and switches the store to the new file and offsets. A crash at any point leaves either the old log or the new one at `PATH`. `open()` deletes a leftover `PATH.compact`.

Auto compaction runs after a write when the dead bytes are at least `auto_compact` and also exceed the live bytes. Dead bytes are overwritten values, deleted keys and delete records. Setting `auto_compact` to 0 turns it off.

## Iteration order

Iteration follows insertion order, as a Python `dict` does:
- overwriting a key keeps its place;
- deleting a key and putting it again moves it to the end.

Replaying the log rebuilds the same order, and compaction preserves it.

## Reads

Values are copied from a read-only shared mapping of the log's first 1 GiB. The mapping covers twice the flushed length, with a minimum of 1 MiB, and is redone as the file grows and after compaction. Pages past the end of the file are never touched. Offsets beyond the mapping, or a failed `mmap`, fall back to `pread`. A positional read costs about 1.8 µs per call on the test laptop, more than the rest of a lookup, which is why reads use the mapping.

The store assumes that it is the only writer. Another process that truncates the file while it is mapped can cause SIGBUS. There is no file locking.

## Application: kv

`sample_programs/library/kv.lani` is a command-line front end built on [`std::cli`](stdlib-cli.md):

```text
kv [-f FILE] [--sync] put KEY [VALUE]     # value from stdin when omitted
kv [-f FILE] get KEY                      # exit 1 when absent
kv [-f FILE] delete KEY                   # exit 1 when absent
kv [-f FILE] list [-k]                    # KEY<TAB>VALUE lines, insertion order
kv [-f FILE] compact | stats
kv [-f FILE] bench [-n N] [-s SIZE]       # N puts, one sync, N scattered gets
```

## Verification

`tests/fixtures/extended/kv_log/oracle.py` drives `batch.lani`, which runs a length-prefixed op script, and compares the results with a Python model.

**Model cases (300).** Each case runs random puts, deletes, gets, syncs, flushes, compactions, iterations and stats. The keys are drawn from a small pool and include the empty key. A few values are as large as 1.6 MB, which exercises recovery's chunk growth. Options are random across cases: buffer sizes from 0 to 1 MiB, `sync_every`, and auto compaction thresholds. The cases also include two kinds of reopen. A clean close and reopen is followed by a check of the exact file bytes. A simulated crash drops the store without flushing, so the reopen must recover exactly the records flushed so far. The model is a dict over the list of records. Every output line, every reported end offset and the final file bytes must match it.

**Crash cases (600).** Each case builds a random committed log and damages a copy in one of four ways:
- truncation at a random offset, including offsets inside the header;
- a single bit flip after the header;
- random garbage appended;
- a stale `PATH.compact` file left beside it.

The reopen must report exactly the number of records and the number of truncated bytes for the longest intact prefix. It must iterate to the dict state after those records and must have removed the stale file. A later put and reopen must then produce exactly the expected bytes.

**Header case (1).** A log with a wrong header is `NotKvLog`.

**CLI sessions (40).** With `--cli KV`, random put/get/delete/compact/list sessions of the `kv` program, with values given as arguments or on stdin, are checked against a dict: exit statuses and stdout must match.

All 901 library cases and the 40 CLI sessions pass. The run takes 10-32 s, depending on machine load.

## Benchmark

These figures come from `kv bench -n 1000000` (11-byte keys, 100-byte values), run on the ext4 laptop disk and alternated with `tests/fixtures/extended/kv_log/bench.py`. The Python side uses `sqlite3` with `synchronous=OFF`, one transaction, `executemany` for the puts and a `WITHOUT ROWID` table, and `dbm.dumb` with 100,000 operations. Both run the same scattered get order.

| Store | N | Puts per second | Gets per second |
| --- | --- | --- | --- |
| `ext::kv_log` | 1,000,000 | 503,568 / 682,376 / 588,326 | 851,465 / 1,064,158 / 788,766 |
| sqlite3, `synchronous=OFF` | 1,000,000 | 530,307 / 801,088 / 527,466 | 104,254 / 71,107 / 92,485 |
| `ext::kv_log` | 100,000 | 502,550 | 923,387 |
| dbm.dumb | 100,000 | 17,488 | 58,433 |

Each row lists three alternating rounds, run while other jobs loaded the machine (load average 24, 11 and 7). Puts are roughly level with SQLite's C `executemany` loop; the 124 MB written to disk is part of every kv round. Gets run 8-15 times faster than the Python SQLite queries, much of whose cost is per-call interpreter overhead, and about 15 times faster than dbm.dumb. On tmpfs, a put of an empty value costs about 1.4 µs and a get about 0.7 µs.
