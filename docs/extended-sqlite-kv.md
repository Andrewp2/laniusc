# Persisted binary key/value storage

[`sample_programs/library/sqlite_kv.lani`](../sample_programs/library/sqlite_kv.lani)
uses [`ext::sqlite`](extended-sqlite.md) prepared statements to store byte keys
and binary values in a SQLite database file.

```text
sqlite-kv DB put KEY
sqlite-kv DB get KEY
sqlite-kv DB delete KEY
sqlite-kv DB count

Options: --max-input N --max-output N --max-io-calls N
```

`put` reads the value from binary stdin and inserts or replaces that key's
value. `get` writes the exact stored value to stdout without adding a newline.
`delete` removes the key. A successful `put` or `delete` produces no stdout.
`count` prints the number of keys as a decimal line. Each invocation opens the
same persisted database; the key/value table is created by the first `put`.
Reads and counts open the database read-only. Delete requires an existing
writable database. Reads, counts and deletes never create a missing file.

Keys come from the process argument bytes. They may be empty or contain
non-UTF-8 bytes, quotes, spaces or newlines. Unix arguments cannot contain NUL;
values read from stdin can contain every byte, including NUL. Both keys and
values use BLOB bindings. Key or value contents never enter SQL text, and
empty BLOBs remain distinct from SQL NULL. Use `--` before the operands when
a key begins with `-`, for example `sqlite-kv -- notes.db get -draft`.

The database path must be nonempty UTF-8, at most 4,096 bytes. The CLI rejects
`:memory:` and paths beginning with `file:` so SQLite URI parsing cannot select
an in-memory or differently configured database. Keys are bounded to 4,096
bytes. The application owns a `kv` table with this schema:

```sql
CREATE TABLE IF NOT EXISTS kv (
    key BLOB PRIMARY KEY NOT NULL,
    value BLOB NOT NULL
) WITHOUT ROWID
```

Each put uses one parameterized `INSERT ... ON CONFLICT ... DO UPDATE`
statement, so replacing a value is atomic. The application does not expose
arbitrary SQL or a batch mode. An existing database with an incompatible table
or a non-BLOB value produces an explicit database error.

## Build and use

The executable uses the Linux x86_64 native C linking profile, libc startup,
and the system SQLite 3 library. From the repository root:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --native-link --native-library sqlite3 \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/sqlite_kv.lani -o /tmp/sqlite-kv

printf 'saved value\n' > /tmp/kv-value
timeout --kill-after=2s 20s /tmp/sqlite-kv /tmp/notes.db put draft < /tmp/kv-value
timeout --kill-after=2s 20s /tmp/sqlite-kv /tmp/notes.db get draft > /tmp/kv-restored
cmp /tmp/kv-value /tmp/kv-restored
timeout --kill-after=2s 20s /tmp/sqlite-kv /tmp/notes.db count
timeout --kill-after=2s 20s /tmp/sqlite-kv /tmp/notes.db delete draft
```

The application links SQLite directly through the checked C ABI. Its production
path contains no C adapter, Python process, OpenSSL dependency or custom storage
engine.

## Bounds and output

`--max-input` and `--max-output` default to 1 MiB and accept unsigned decimal
values through 16 MiB, including zero. Input is read in chunks of at most
1,024 bytes. At an exact input limit, one additional byte is requested to
distinguish EOF from excess input. An input-limit failure can consume that one
extra byte. The complete bounded input is captured before opening the database,
so input errors and input-limit errors preserve an existing value and do not
create a new database.

For `get`, the stored BLOB length is checked before allocating the result.
The value is copied into owned Lanius bytes, and the statement and connection
are finalized and closed before stdout starts. Output limits also apply to the
decimal line from `count`. A successful empty value needs no stdout attempt.
Once output starts, a later I/O error or call-limit failure can leave a prefix.

`--max-io-calls` defaults to 65,536 and accepts values through `i32::MAX`.
It bounds combined stdin/stdout attempts, including short transfers, EINTR
retries and the EOF probe. Short writes resume at the first unwritten byte.
EAGAIN, invalid transfer counts, host failures and zero-progress writes are
I/O errors. SQLite has a zero-millisecond busy timeout, so a locked database
reports an error instead of entering a retry loop. The I/O call budget does
not bound time spent inside a blocking descriptor call or SQLite operation.
The wrapper's default SQL, column, value and compilation limits also apply.
Byte limits bound application payloads; SQLite manages its own page cache and
row storage, so they are not a process-memory quota.

Argument capture permits 16 arguments and 16,384 total bytes. Options can
precede or follow operands, with separate or `=` values. Repeated limit options
use the last value. Unknown options, missing values, signs, overflow, extra
operands and limits above their ceilings are errors. `--help` / `-h` validates
the supplied syntax before printing usage.

## Errors and ownership

| Exit | Meaning |
| --- | --- |
| 0 | Operation or help completed |
| 2 | Invalid arguments, input/output byte limit or I/O call limit |
| 3 | Argument capture, stdin or stdout I/O failure |
| 4 | SQLite operation or allocation failure |
| 5 | Key absent during get or delete |

Diagnostics distinguish busy/locked databases, read-only databases, constraint
failures, absent keys, allocation failures, input/output failures and each
application limit. Other SQLite failures report a database operation error.
Diagnostics have a separate eight-attempt stderr budget and preserve the
original exit status if stderr also fails.

All prepared statements are finalized before closing their database, including
after bind, step and column errors. The input, output and argument owners are
released on every completed success and error path. The first operation error
is preserved if statement finalization also reports that error. A single put
or delete may have committed before a later finalization or close error is
reported; the exit status is not a promise that a failed command changed no
database state.

## Focused executable checks

[`tests/extended_sqlite_program_execution.rs`](../tests/extended_sqlite_program_execution.rs)
compiles the application through native linking, validates generated function
boundaries in the linked ELF, and checks the direct SQLite dependency. The
driver uses Python's standard `sqlite3` library as an independent database
reader and writer. Cases cover:

- Persisted upserts, reads, deletes and counts; empty/binary values; non-UTF-8
  keys; quotes and SQL-looking keys; chunk boundaries and larger values.
- Exact input/output/call limits, argument validation, missing keys and files,
  read-only files, exclusive locks, constraint failures and incompatible data.
- Real input/output/diagnostic failures and preservation of the previous value
  when input capture or an atomic update fails.
- The actual sample helpers with scripted partial reads/writes, EINTR, EAGAIN,
  invalid counts, zero progress, bounded retries and exact EOF probes.
- A test-only native observer that forwards calls to system SQLite and checks
  connection and statement ownership is balanced before each child exits.

Rust, Python and the small observer provide orchestration, the independent
database oracle and lifecycle observation. Production CLI, bounds, ownership
and stream behavior are Lanius code.

All five groups passed on Linux x86_64 in 17.54 seconds: 27 persisted-data
cases, 53 argument/limit cases, 15 database-error cases and four descriptor-error
cases, plus the scripted tests of the actual stream helpers. The checked
application includes the persisted-path guard that rejects both `:memory:` and
`file:` URI names. The linked ELF validation and SQLite dependency checks also
passed. The local receipt is
`target/stdlib-work/sqlite-program-execution-current.log`.

These results cover native CPU execution through the system SQLite library.
Other operating systems and GPU-kernel execution have not been verified.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_sqlite_program_execution -- --nocapture
```
