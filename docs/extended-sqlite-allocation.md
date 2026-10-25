# SQLite staging allocation failures

The focused gate in
[`extended_sqlite_allocation_execution.rs`](../tests/extended_sqlite_allocation_execution.rs)
checks failures in the Lanius allocations that stage paths, SQL, text and blobs
for `ext::sqlite`. It complements the SQLite library error cases in
[`extended_sqlite_execution.rs`](../tests/extended_sqlite_execution.rs).

The executable imports the production wrapper from
[`extended/ext/sqlite.lani`](../extended/ext/sqlite.lani) and links the installed
SQLite library. All application behavior, error checks and retry logic are
Lanius source. Python drives `strace`; a test-only C observer forwards native
calls to SQLite and records ownership events.

## Cases and recovery

The gate compiles one
[`staging.lani`](../tests/fixtures/extended/sqlite_allocation/staging.lani)
executable, runs a baseline, then injects `ENOMEM` at each of the four reached
Lanius `mmap` requests. The wrapper allocates one extra byte for a trailing NUL.

| Staged input | Input bytes | Allocation bytes | Required error phase |
| --- | ---: | ---: | --- |
| Database path | 96 | 97 | `Open` |
| Prepared SQL | 208 | 209 | `Prepare` |
| Text binding | 312 | 313 | `Bind` |
| Blob binding | 520 | 521 | `Bind` |

Every injected run must observe `Cause::AllocationFailed`, the listed phase
and native code zero, then complete a successful retry. A prepare failure keeps
the database open. Both bind failures keep the statement in `Ready` and retain
its earlier bindings: text failure preserves two seeded integers; blob failure
preserves the completed text binding and the other seeded integer.

After retry, the fixture copies and checks every text and blob byte, checks the
destination guard bytes, resets the statement and reads both values again.
The blob includes NUL and non-UTF-8 bytes. The source views have nonzero offsets
and unchanged guard bytes. The fixture explicitly finalizes its statement and
closes its database; repeated cleanup calls succeed without another native
cleanup call.

## Trace ownership

The baseline identifies the four requests by their distinct sizes, anonymous
`MAP_32BIT` flags and shared allocator instruction address. It counts all
`mmap` calls to obtain the actual injection ordinal. The injected trace must
show exactly one failed request at that ordinal, size and instruction address,
followed by the successful retry.

The release ledger covers only these Lanius staging mappings. Loader, libc and
CRT process-context mappings remain outside that ledger. Every successful
staging request must have one successful `munmap` with the same address and
requested length. Each failed request has no mapping to release.

The observer must record `OPTBFC` in every run: one native database open,
one native statement prepare, one native text bind, one native blob bind,
statement finalize and database close. A local allocation failure must not add
a native operation. The baseline and every injected run must leave no database
journal or sidecar file.

## Run the gate

Requirements are Linux x86_64, the native GPU compiler prerequisites, the
SQLite development library, `cc`, `python3`, `readelf`, `objdump` and `strace`
with syscall injection support.

```sh
timeout --kill-after=2s 110s cargo test \
  --test extended_sqlite_allocation_execution -- --nocapture
```

The gate covers the four staging sites in this bounded workload. SQLite's own
allocation failures, large input caps and other wrapper errors have separate
tests. It does not claim that libc or SQLite release every process-global
allocation before process exit.

The focused group passed on Linux x86_64/glibc in **8.60 seconds**. Its five
`strace` runs cover the baseline and all four reached allocation failures,
including retained bindings, retries, native ownership traces and the mapping
release ledger. The local receipt is
`target/stdlib-work/sqlite-staging-allocation-execution.log`.
