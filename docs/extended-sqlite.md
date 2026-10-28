# SQLite databases and prepared statements

`ext::sqlite` wraps SQLite's native connection and prepared-statement APIs.
Lanius owns the interface, staging buffers and lifecycle checks. The system
`libsqlite3` performs SQL compilation, execution, storage, transactions and value
conversion. Production calls use direct `extern "C"` symbols, including
`sqlite3_bind_double` and `sqlite3_column_double`; no C adapter, JSON transport,
subprocess bridge or Rust/Python database implementation is involved.

This module targets the [Linux x86_64/glibc native C profile](library-native-c.md).
The audited host has SQLite 3.45.1. The library and its
[persistent binary key/value application](extended-sqlite-kv.md) pass focused
native execution gates on that profile. Other operating systems, libc profiles,
Wasm and user GPU kernels have no execution claim from these results.

## Opening and ownership

`open(path, mode, limits)` returns `Result<Database,Error>`. The path is a
`core::slice::View<u8>` containing nonempty UTF-8 without NUL. The wrapper
validates its logical range and byte limit before native access, copies the
bytes into aligned packed storage, appends NUL, and calls `sqlite3_open_v2`.
`memory(limits)` opens a separate `:memory:` database.

| Mode | Behavior |
| --- | --- |
| `ReadOnly` | Open an existing database for reading. |
| `ReadWrite` | Open an existing database for reading and writing. |
| `Create` | Open for reading/writing and create the database if needed. |

SQLite can fall back to a read-only connection for a requested writable open.
The wrapper checks `sqlite3_db_readonly` for `main` and rejects that fallback
with `Cause::ReadOnly`, phase `Open`, code 8. Filenames follow the linked
SQLite's default VFS and configuration. URI parsing can be globally enabled
even without an explicit URI open flag, so a `file:` filename can select URI
behavior, including memory databases. `open()` does not enforce a persisted-file
policy or restrict URI filenames; `memory()` explicitly supplies `:memory:`.
Applications promising file persistence must impose their own filename policy.
Extended native result codes are enabled. If open or configuration fails, the
wrapper closes any connection already allocated.

Keep one active owner and pass `database.borrow()` to helpers. Copies alias the
same native connection and must remain inactive; fields are not for application
mutation. `is_open()` reports this owner's state. `close()` returns `Ok(0)` on
success and clears its handle. Repeated close through that owner succeeds.

Close uses `sqlite3_close`, which reports `SQLITE_BUSY` while prepared statements
exist and keeps the database live. A failed close preserves the owner's handle
and existing statements. Finalize those statements and retry. The wrapper does
not use `sqlite3_close_v2` or invalidate their parent implicitly. No automatic
destruction, concurrent use, callbacks or foreign thread entry is provided.

## Preparing one statement

`database.prepare(sql)` takes a UTF-8 `View<u8>` and returns an owned
`Statement`. SQL is bounded and NUL-free. The wrapper passes its explicit byte
count to `sqlite3_prepare_v3`, reads the statement and tail through aligned
pointer cells, and checks the unused tail before returning the owner.

Exactly one statement is accepted. The unused suffix may contain only ASCII
space, tab, carriage return and newline. A second statement, extra semicolon
or trailing comment is rejected as `TrailingSql`; empty/comment-only SQL gives
`EmptySql`. Comments consumed by SQLite as part of the first statement remain
valid. A rejected compiled statement is finalized before the staging buffer is
released. This validation prevents a second statement from being stepped; it
does not sandbox SQL or promise that native preparation has no effects.

The statement starts in `State::Ready`. `parameter_count()` reports SQLite's
highest parameter index, including any holes from `?NNN`. `column_count()`
reports the result-column count and refreshes it after successful stepping to
account for SQLite's schema reprepare behavior. Both are cached metadata.

## Binding values

Bindings use one-based indexes. Bind only while the statement is `Ready`.
Each successful bind returns `Ok(0)`:

| Method | SQLite value |
| --- | --- |
| `bind_null(index)` | SQL NULL |
| `bind_i64(index,value)` | Signed 64-bit INTEGER |
| `bind_f64(index,value)` | REAL through native C double |
| `bind_text(index,bytes)` | Counted UTF-8 TEXT |
| `bind_blob(index,bytes)` | Counted arbitrary-byte BLOB |

Text and BLOB input are length-bearing views. The wrapper checks ranges and
caps, validates text UTF-8, packs the complete value, and binds using
`SQLITE_TRANSIENT`. SQLite copies the value before the native call returns;
the wrapper then frees staging. The caller can reuse or release the original
input immediately after the bind. An empty value still passes a non-null
staging pointer with count zero, so empty TEXT/BLOB remain distinct from NULL.

The destructor argument carries only SQLite's documented all-ones
`SQLITE_TRANSIENT` sentinel on this platform. It never carries a Lanius callback.
Local bounds/type/UTF-8/cap errors make no bind call. A native bind failure
does not promise to retain the previous bound value; clear and rebind or
finalize before relying on it.

Counted TEXT can contain embedded NUL and is copied without truncation.
SQLite does not define general SQL expression behavior for strings containing
embedded NUL. Use BLOB for fully general binary storage and processing.

SQLite converts NaN to SQL NULL. The wrapper instead rejects NaN locally with
`Cause::NotANumber` in phase `Bind`, code zero. Infinities are accepted. Direct
bound values, SQL expressions, column affinity and persisted storage follow
SQLite's REAL semantics; signed zero need not survive storage. This is not a
NaN payload or universal binary64 bit-round-trip contract.

## Stepping and resetting

`statement.step()` returns `Result<Step,Error>`:

| Current state | Operation and next state |
| --- | --- |
| `Ready` / `Row` | Step once; native `SQLITE_ROW` returns `Step::Row` and state `Row`. |
| `Ready` / `Row` | Native `SQLITE_DONE` returns `Step::Done` and state `Done`. |
| `Ready` / `Row` | A native error returns its code and state `Failed`. |
| `Done` / `Failed` | Further step returns `InvalidState` until reset. |
| `Finalized` | Further use returns `Closed`. |

These rules are one transition function, `ext::sqlite_statement::transition`,
and `Statement` changes its state nowhere else. Its Lean translation proves
that `Column` needs `Row` and that nothing leaves `Finalized`
([state machines, M0](state-machines-design.md#m0-result)).

There is no implicit reset, execution retry or row loop. BUSY is a native error,
not a successful empty result. `is_busy(error)` recognizes primary code 5;
`primary_code(error)` exposes the low-byte native code. LOCKED is code 6 and
remains distinct. Transaction error handling must respect SQLite's transaction
state; inspect `autocommit()` and roll back when appropriate.

`reset()` always changes a live statement to `Ready`, even if SQLite returns an
error from the previous evaluation. It retains all bindings. `clear_bindings()`
requires `Ready` and sets every parameter to NULL. Neither operation runs the
statement. Their successful result is `Ok(0)`.

`finalize()` clears this owner's handle and sets `Finalized` before calling
SQLite. SQLite deletes the statement even when finalize reports a prior
evaluation error, so never retry that native handle. Repeated finalize through
the same owner succeeds without another native call. The parent database stays
owned separately.

## Reading a row

Column indexes are zero-based. Accessors require `State::Row` and an index below
`column_count()`. `column_type(index)` returns `Null`, `Integer`, `Real`, `Text`
or `Blob`. All value access is strict: the wrapper does not turn an INTEGER into
a REAL, a BLOB into TEXT, or NULL into a zero/empty value.

| Method | Result |
| --- | --- |
| `column_i64(index)` | `Result<i64,Error>` for INTEGER only |
| `column_f64(index)` | `Result<f64,Error>` for REAL only |
| `column_text_len(index)` / `column_blob_len(index)` | Counted bytes after the type and column-cap checks |
| `column_text_copy(index,output)` / `column_blob_copy(index,output)` | Copy into caller `View<u8>` and return the copied byte count |

Text access requests SQLite's UTF-8 representation, reads its byte count, and
validates the result. TEXT created by casting invalid binary data can therefore
return `Utf8`. Embedded NUL remains part of the counted result. Copying never
adds a terminator. A short output view returns `OutputTooSmall`; every local or
native error leaves caller output untouched. A successful copy writes only the
returned prefix, preserving any remaining bytes.

SQLite owns row storage. The wrapper obtains the requested representation
before its count and copies it within the same accessor call; it exports no
borrowed native pointer. A suspicious null pointer or zero-byte result is
followed immediately by `sqlite3_errcode` before any other SQLite call, to
distinguish conversion OOM from empty data. Conversion OOM changes the wrapper
state to `Failed`, requiring reset or finalize; SQLite may have poisoned or
changed its native row value. Local type, UTF-8 and capacity errors preserve
`Row`. Row memory must never be passed to the Lanius allocator. Column-cap
checks bound copied data; SQLite may already have materialized the native
result before that check.

## Transactions and connection metadata

`begin(Transaction::{Deferred,Immediate,Exclusive})`, `commit()` and `rollback()`
prepare fixed SQL, step it once and finalize it. Each returns `Ok(0)` on
success. If execution fails, cleanup preserves the original error. They do not
implicitly nest, retry, roll back other failures, or consume outstanding rows.
Failed COMMIT can leave a transaction active, so inspect `autocommit()` before
deciding how to recover.

`changes()` and `last_insert_rowid()` return signed 64-bit native values.
`autocommit()` returns a Boolean. Their meaning follows the latest native
connection operations, including SQLite's trigger and rollback rules; they are
not wrapper-maintained transaction counters.

## Limits and errors

`default_limits()` returns:

| Field | Default |
| --- | --- |
| `path_bytes` | 4,096 |
| `sql_bytes` | 65,536 |
| `value_bytes` | 33,554,432 |
| `column_bytes` | 16,777,216 |
| `variables` | 1,024 |
| `columns` | 256 |
| `expression_depth` | 64 |
| `compound_selects` | 32 |
| `vm_ops` | 100,000 compiled instructions |
| `busy_timeout_ms` | 0, immediate BUSY |

Path, SQL, value and compile limits must be positive; byte caps leave room for
one staging terminator. `column_bytes` may be zero and must not exceed
`value_bytes`. Busy timeout must lie in 0..60,000 milliseconds.

The wrapper installs SQLite's LENGTH, SQL_LENGTH, COLUMN, EXPR_DEPTH,
COMPOUND_SELECT, VDBE_OP and VARIABLE_NUMBER limits. SQLite's build can impose
smaller hard limits. LENGTH also limits complete row representations: an
individual bound value at the exact cap can fail when record overhead is
included. It can also reject a generated result-column name during preparation;
a short alias can keep that name inside a very small LENGTH cap. The per-column
cap is checked before copying caller output.

The busy timeout bounds SQLite's configured lock-wait sleeping policy. It is
not a deadline for a native call. `vm_ops` caps compiled instruction allocation,
not executed instructions, result rows, CPU work, memory for an entire query or
wall-clock time. One `sqlite3_step` can do arbitrarily much work within those
compile limits. No callback-based progress handler is available. Callers must
control SQL and apply external process/resource limits where required; this
API is not a SQL sandbox, and SQL can change SQLite configuration.

`Error` contains `cause`, `phase` and `code`. Local failures have code zero;
native failures retain the returned SQLite result or extended result code
before cleanup. Phases identify open/configuration, preparation, binding,
stepping, reset, binding clear, columns, finalize, close or transaction policy.
Native error-message pointers do not escape. Bounds checks validate logical
metadata; callers must still physically back every supplied view and keep its
storage alive without overlapping the active owners.

## Build and verification

Use the native profile with `--native-library sqlite3`, ordinary stdlib/extended
roots, and a rebuilt compiler. From the repository root:

```sh
export CARGO_TARGET_DIR="$PWD/target/stdlib-build"
timeout --kill-after=2s 100s "$CARGO_TARGET_DIR/debug/laniusc" \
  --native-link --native-library sqlite3 \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/sqlite_kv.lani -o /tmp/sqlite-kv
```

## Execution evidence

The focused gates compile the production Lanius module through native linking,
validate the linked ELF and its SQLite dependency, and execute it on Linux
x86_64/glibc:

| Gate | Result | Local receipt |
| --- | --- | --- |
| [`extended_sqlite_execution`](../tests/extended_sqlite_execution.rs), ordinary cases | 4 groups pass in 14.92 s | `target/stdlib-work/sqlite-library-execution-current.log` |
| Same driver, injected native failures | 1 group passes all 21 modes in 9.03 s | `target/stdlib-work/sqlite-native-fault-execution.log` |
| [`extended_sqlite_program_execution`](../tests/extended_sqlite_program_execution.rs) | 5 groups pass in 17.54 s: 99 oracle cases plus scripted stream helpers | `target/stdlib-work/sqlite-program-execution-current.log` |
| [`extended_sqlite_allocation_execution`](../tests/extended_sqlite_allocation_execution.rs) | 1 group passes in 8.60 s: baseline plus four injected staging allocation failures | `target/stdlib-work/sqlite-staging-allocation-execution.log` |

The library gate covers:

- 558 bound-value cases: 62 REAL encodings across all nine combinations of
  stack, packed and Vec input/output layouts, with varying offsets. The
  INTEGER corpus includes both signed 64-bit endpoints and values beyond
  binary64's exact-integer range. Counted UTF-8 TEXT, embedded NUL, arbitrary
  binary BLOBs, empty values distinct from NULL and input mutation after binding
  are checked against Python's independent SQLite connection.
- 640 deterministic insert, update, delete, query and transaction commands.
  An independent dictionary model checks Python SQLite's rows before its
  outputs are compared with the Lanius executable. Commit, rollback, changes
  and last-insert metadata follow actual SQLite operations.
- All ten limit fields, including 23 rejected limit configurations; exact path,
  SQL and value caps; zero/exact/short column caps; native variable, column,
  expression-depth, compound-select and compiled-VM limits; and the busy-timeout
  endpoints. The VM cap remains a compilation limit.
- Local metadata, index, type, encoding and output-capacity errors, retained
  bindings across reset, explicit binding clear, invalid statement states,
  close BUSY recovery, repeated cleanup and real constraint errors returned by
  reset and finalize.
- Actual database files, commit and rollback across process invocations,
  read-only rejection, a native write lock and successful write recovery after
  lock release. Bound signed zero and persisted REAL affinity are compared
  separately; NaN is rejected locally.

The 21 fault modes forward successful calls to system SQLite and inject open,
configuration, prepare, bind, clear, reset, step, column, finalize and close
failures. Exact call/release traces check partial acquisition and one release
per native owner. Both column-pointer NULL and column-byte-count zero capture
NOMEM immediately, preserve caller output, enter `Failed`, and require explicit
reset before reading another row. Local UTF-8 failure preserves `Row`.

The bounded storage workload performs 32,768 parameterized inserts in one
transaction and 32,768 indexed selects using reset/rebind. Independent row
count, sum, key/value product sum and indexed-lookup checksums match. Its
observed run took **51.798074 ms**, excluding GPU compilation, and
`sqlite3_memory_highwater` reported **545,848 bytes**. That metric covers SQLite's
allocator, not Lanius staging mappings or process-wide memory, and this is one
bounded workload on the audited host.

The [staging allocation failure gate](extended-sqlite-allocation.md) passes a
baseline and ENOMEM injection at each reached path, SQL, text and blob staging
allocation: 97, 209, 313 and 521 bytes. Five `strace` runs verify retained
bindings, successful retries, native call traces and exact mapping cleanup.
Rust, Python, the Python SQLite oracle and small native observers provide test
infrastructure. Production SQL, binding, lifecycle and stream behavior remain
Lanius over direct SQLite C calls.

```sh
timeout --kill-after=2s 110s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_sqlite_execution -- --nocapture --test-threads=1
```

The primary contracts are SQLite's [open](https://www.sqlite.org/c3ref/open.html),
[prepare](https://www.sqlite.org/c3ref/prepare.html),
[binding](https://www.sqlite.org/c3ref/bind_blob.html),
[column](https://www.sqlite.org/c3ref/column_blob.html),
[step](https://www.sqlite.org/c3ref/step.html),
[reset](https://www.sqlite.org/c3ref/reset.html),
[finalize](https://www.sqlite.org/c3ref/finalize.html),
[close](https://www.sqlite.org/c3ref/close.html) and
[runtime-limit](https://www.sqlite.org/c3ref/limit.html) documentation.
The audited declarations come from the installed `/usr/include/sqlite3.h`.
