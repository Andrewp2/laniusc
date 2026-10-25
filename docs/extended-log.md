# Structured logging

`ext::log` provides severity filters, typed borrowed records, bounded JSON
encoding and explicit preparation outcomes. It uses `core::fmt`, makes no
allocations and does not read a clock or select an output stream. Callers deliver
prepared bytes through the existing `core::io::Write` contract.

The supported execution target is **x86_64 Linux using the GPU compiler**.
GPU execution of user programs and other hosts have not been verified. The
module requires the optional `extended` source root.

## Records and filtering

`Level` contains Trace, Debug, Info, Warn and Error, in increasing severity.
`Filter::Off` disables all levels; `Filter::AtLeast(level)` enables that level and
every higher one. `enabled(filter, level)` lets callers avoid constructing an
expensive record in the first place.

`level_name(level)` returns borrowed static Text. `parse_level(Text)` recognizes
exact lowercase `trace`, `debug`, `info`, `warn` and `error`; `parse_filter(Text)`
also accepts `off`. Both parsers return Option. They do not trim whitespace,
fold case or recognize aliases such as `warning`.

A `Record` contains a level, target Text, message Text and `View<Field>`. Each
Field has a Text key and a `Value`: Text, Bool, Signed(i64), Unsigned(u64) or Null.
Keep every backing buffer and field alive and unchanged during a preparation
call. Values do not own or prolong their sources' lifetimes. Use `record.borrow()`
to pass the record. Input ranges must not overlap the output buffer.

The encoded representation is one compact UTF-8 JSON object followed by LF:

```json
{"level":"info","target":"checksum","message":"input_complete","fields":{"input":0,"status":0}}
```

The outer member order is level, target, message, fields. Field order follows the
supplied view. Fields live in a nested object, so their names cannot overwrite
outer metadata. Empty keys, NUL and arbitrary valid UTF-8 are supported. Duplicate
keys are rejected by exact Text equality without normalization. Integers remain
exact decimal integers in the output; consumers that store all numbers in f64
may round large values. No floating-point or nested-container field values are
currently advertised.

String quoting follows the [formatter's JSON contract](stdlib-formatting.md).
Input CR/LF and other C0 control bytes are escaped, so a message cannot create
another physical LF-delimited record. Unicode line/paragraph separator scalars
remain UTF-8 data. This schema is a Lanius logging convention, not a syslog format.

## Preparation and delivery

| API | Contract |
| --- | --- |
| `encoded_len(&Record)` | Validate duplicate keys and measure complete byte length, including LF |
| `encode(&Record, bytes, offset, capacity)` | Encode the entire record or leave the destination unchanged on validation/capacity error |
| `prepare(filter, &Record, scratch, capacity)` | Return `Filtered` or `Encoded(byte_count)` inside Result |

`prepare` tests the filter first. A filtered record does not inspect fields,
validate scratch capacity, touch scratch bytes or perform I/O. An enabled record
is fully measured before any bytes change. It returns `Outcome::Encoded(n)` only
after the complete record is in scratch `[0,n)`. This outcome **does not mean the
record has been written to an external sink**.

Errors are `DuplicateKey(later_field_index)` and `Format(core::fmt::Error)`.
Invalid offset/capacity fails before measuring. Size and capacity errors report
the formatter's cause; BufferTooSmall carries the complete encoded record size.
The caller must physically back the claimed destination range and source views.

For Encoded(n), call `core::io::write_all(writer, scratch, 0, n)` and handle its
Result. It retries Interrupted, handles short writes, rejects invalid progress
and reports WriteZero. A failure carries `completed` bytes; some prefix may
already have reached the sink. Retrying the entire record after such a failure
would duplicate that prefix. Flush, close, synchronization, concurrent-writer
serialization and retry policy belong to the caller. Multiple writes do not
promise atomic delivery of a record to other processes.

The one-call generic preparation-and-write prototype encounters a compiler
failure and remains [outside the production source root](../tests/fixtures/stdlib_foundation/log_write_dependency/README.md).
The supported composition prepares a record and then calls write_all. Memory
writers, native stdout/stderr and application failure paths execute with this
composition. There is no global logger, implicit stderr, automatic timestamp,
background queue or destructor-driven flush.

Encoding is linear in encoded bytes plus duplicate checking. The current
duplicate check compares pairs of field names, so large field sets can take
quadratic comparisons. Working storage beyond the caller's record/output is
constant. Field-count and record-size policy belong to the application.

## Checksum application

`sample_programs/checksum.lani` accepts `-l LEVEL` / `--log-level LEVEL`, with
default `off`. Its configuration accepts `"log_level":"info"`. Every supplied
configuration source is validated; CLI settings override files regardless of
position, and the last CLI log-level option wins.

The program emits one Info completion or Error failure record per processed
input. Fields identify the zero-based input index and numeric exit status. No
operands means stdin at index zero. The checksum remains on stdout; records go
to stderr. Argument/configuration failures happen before input processing and
do not emit records through this per-input logger.

```sh
printf '123456789' | timeout 5s target/stdlib-work/checksum-log --log-level info
```

Data/file errors retain their status if reporting also fails. A logging write
failure after successful checksum processing returns status 3; the checksum may
already be present on stdout. Filtering performs no log writes. Help and the
existing configuration/argument error conventions remain documented in
[CLI](extended-cli.md) and [configuration](extended-config.md).

## Execution evidence

The logging groups in `tests/format_log_execution.rs` execute:

- Every severity threshold and exact parser spelling, all field value kinds,
  integer extremes, empty keys, Unicode/control bytes, duplicate rejection,
  negative/overflowing bounds and every insufficient capacity below one record.
- Buffer guards and unchanged bytes on failure/filtering, exact measured size,
  memory-writer partial progress and native output. Allocation-denied traces
  contain no allocation attempts during the contract fixture.
- Application config/CLI precedence, missing files, input limits and multiple
  inputs. Fault injection covers every observed allocation, open, read, write
  and close step, plus interrupted and zero-progress log writes.
- Repeated preparation with changing field values using fixed storage; see the
  batch fixture for the bounded workload. The 0-, 128- and 8,192-record cases
  execute with allocation denied, produce every expected record and make no
  allocation attempts.

On 2026-10-23, nine alternating native runs pinned to CPU 8 of the Ryzen 5950X,
writing to `/dev/null`, measured these median whole-program CPU times:

| Records | CPU time |
| --- | --- |
| 4,096 | 33.57 ms |
| 32,768 | 271.94 ms |

The larger case produces eight times as many records in approximately 8.1 times
the CPU time. These measurements include startup and one native delivery per
record; they do not measure compiler throughput, GPU execution or a buffered
logging sink. They establish the scale tested, not a portable timing guarantee.

The remaining logging work includes resolving the generic facade dependency,
timestamp conventions, composable sinks, rotation and explicitly bounded
asynchronous delivery once the required runtime/thread interfaces exist.
