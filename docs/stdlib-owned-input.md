# Bounded owned input

The [alloc::io implementation](../stdlib/alloc/io.lani) collects a borrowed
`core::io::Read` into an owned byte vector or UTF-8 String. The [increment contract](library-owned-input-plan.md) fixes byte
and call limits, retained failures and explicit cleanup. All six new library
tests, all 111 application cases and the selected old stream/String regressions
pass on native Linux x86_64. This increment is accepted; the full library goal
stays open.

## API

```text
ReadLimits { max_bytes:i32, max_calls:u64 }
ReadError = InvalidLimits | CallLimit | ByteLimit | Io(core::io::Error)
          | Storage(alloc::vec::Error) | Text(alloc::string::Error)
ReadFailure { cause:ReadError, bytes:Vec<u8>, calls:u64, extra:Option<u8> }
default_read_limits() -> ReadLimits
read_to_end<R:Read>(&R, ReadLimits) -> Result<Vec<u8>,ReadFailure>
read_to_string<R:Read>(&R, ReadLimits) -> Result<String,ReadFailure>
ReadFailure::borrow(&self) -> &ReadFailure
ReadFailure::destroy(&self)
```

The default is 16 MiB / 65,536 calls. Only Read is required; there is no Seek,
Write, File or descriptor bound. Collection does not seek, flush, close or own
the reader. It preserves the provider's canonical byte/count/error contract.
A provider may perform its own allocation or host work; the collector introduces
no new host service.

## Limits and EOF

A negative max_bytes returns InvalidLimits before allocation or delegation.
Zero max_calls is valid and immediately returns CallLimit, even for empty input
or a zero byte cap. Every actual Read call spends one allowance **before**
delegation: successful short reads, Interrupted, EOF and the cap probe all count.
Checking the quota before incrementing prevents u64 overflow. There is no retry
reset or unbounded Interrupted loop. These limits count local bytes and provider
calls, not provider duration, internal host calls or a wall-clock timeout.

Each ordinary request has min(1024, remaining byte allowance) bytes in private
scratch. Success needs actual Ok(0) on a nonempty request; a short positive read
is not EOF. Interrupted retries within the same total allowance. No read occurs
after a terminal result.

At the exact byte cap, collection makes a one-byte read into separate private
storage. EOF succeeds; a confirmed extra byte returns ByteLimit and stores that
byte in failure.extra. A zero-byte cap therefore still needs a real probe, but
no vector allocation. The probe can itself fail or exhaust the call allowance.
Reaching a limit never invents EOF or rewinds consumed input.

## Retained failure progress

Every ReadFailure owns the confirmed admitted prefix in bytes. calls counts
actual delegated calls. extra is Some only for a confirmed over-cap byte, and
None for call, I/O, storage and text failures. Before altering the retained owner,
confirmed consumption from a conforming provider equals bytes.len() plus the
optional extra byte; widen the length
before adding, since a byte cap may be i32::MAX. Recover or replay that retained
probe byte explicitly when resuming another operation.

Err from a conforming Read transfers no bytes for that call. A negative or
excessive successful count becomes Io(InvalidCount), without appending scratch.
Earlier confirmed bytes remain. A broken provider's actual consumption cannot
be reconstructed from an invalid count, and failure never rolls back the reader.
Original I/O and Vec errors remain typed payloads rather than collapsed statuses.

Keep one cleanup owner: destroy the failure, or take cleanup authority for its
bytes. destroy empties its byte owner and may be called again on that emptied
owner; cause/calls/extra retain their historical facts. Copies of failures and
vectors are shallow aliases; they are not extra
cleanup rights. No automatic move/drop or borrow enforcement is implied.

## Reserve before reading

Before each ordinary read, reserve enough vector capacity for the entire
request. Growth is geometric with checked arithmetic and a max_bytes cap.
Storage failure retains the original Vec error and prefix, without consuming
additional input. Reservation can fail before the next call that would have
reported EOF; even an empty stream with a positive byte limit may require an
initial allocation. Quota rejection precedes reservation; it does not substitute
an EOF result.

Only the confirmed scratch prefix is appended after reservation, without another
allocation. No uninitialized spare capacity is exposed, and collector code does
not mutate Vec owner fields. Success returns exactly those confirmed bytes,
without a terminator or normalization. Existing [stream](stdlib-streams.md) and
[Vec](stdlib-vec.md) contracts still govern providers and backing owners.

## UTF-8 ownership transfer

The [String implementation](../stdlib/alloc/string.lani) adds two general
operations:

```text
alloc::string::from_utf8_vec(bytes:&Vec<u8>) -> Result<String,alloc::string::Error>
String::into_bytes(&self) -> Vec<u8>
```

from_utf8_vec validates initialized bytes before adoption. Invalid UTF-8 reports
the existing first malformed-sequence offset and preserves all bytes, length,
capacity and the original Vec owner. Success transfers the existing backing and
capacity without allocation or byte copying, leaving the Vec empty and reusable.
Validation is O(n); the subsequent ownership transfer is O(1).
into_bytes reverses that transfer and leaves an empty reusable String. Both use
the existing Vec owning-cursor transfer operations. The copying from_utf8 API
remains a distinct operation; no compatibility wrapper changes its behavior.

read_to_string uses the same collection engine, observes EOF, then adopts via
from_utf8_vec. Invalid UTF-8 returns Text(error) and **all raw bytes** with the
actual call count. I/O, byte, call and storage failures precede text validation.
Multibyte sequences may cross reads; no replacement, newline normalization or
incremental text rejection occurs.

The separate [borrowed JSON encoding increment](extended-json-streaming.md)
uses this existing collector for owned `encode`, with the exact preflighted
length and `ceil(length/1024)+1` calls including the EOF probe. The migrated
[normalizer](extended-json-normalize.md) uses the same collector for bounded
input, then publishes through a borrowed encoder. Its four groups/100 native
cases pass with separate receipts; that acceptance does not follow from the
historical collector receipts below. Standalone build/examples also pass,
without adding application cases.

End every borrowed view and keep shallow aliases inactive before transfer or
destruction. The result assumes sole cleanup authority. Allocation/capacity
identity does not establish compiler-native layout, automatic lifetimes or a
formal ownership proof; see [String contracts](stdlib-string.md).

## Program, evidence and targets

The [input_stats program](stdlib-input-stats.md) uses the public helpers
with 1 MiB / 8192 calls. It stages fixed ASCII statistics after collection,
retiring input and closing an owned file before output. Its separate guide owns
CLI, raw byte paths, primary-error preservation and output/diagnostic limits;
all four application tests pass 111 native cases. The documented standalone
build and exact byte/text/file examples also pass
(owned-input-stats-build-command.log); these overlap existing cases and add no count.

Frozen sources are alloc::io 2ed4586e and String 2196e427. Receipts below
are separate registered commands under target/stdlib-work.

| Receipt | Accepted scope |
| --- | --- |
| owned-input-admission-first.log | 1 test / 7.26s: generic bytes, split UTF-8, exact-cap EOF and manual cleanup |
| owned-input-direct-first.log | 1 test / 6.98s, admission filtered: five scripted scenarios, exact requests/progress/quotas, retained probe, invalid counts and EOF-before-text precedence |
| owned-input-string-transfer-first.log | 1 test / 6.77s: eight valid/twelve malformed cases, pointer/capacity identity, reuse, 42 phases and 37 matched allocations/releases |
| owned-input-model-retry.log | 1 test / 7.87s: 17,542 cases / 35,084 bytes/text invocations, two layouts; seed 0xa11c0261103 |
| owned-input-resources-amended.log | 1 test / 6.86s: four modes, 262,147-byte growth profiles with 258 calls/ten matched mappings, valid and retained-invalid text transfers |
| owned-input-allocation-failures-first.log | 1 test / 7.44s: seven reached mmap failures, exact retained prefixes/calls, no read at failed reserve, same-reader recovery and matched cleanup |
| owned-input-stats-first.log | 4 tests / 8.88s: model38/rejection24/I/O27/CLI22 = 111 distinct application cases |
| owned-input-string-regression.log | 1 selected existing test / 14.26s, two filtered: three existing String fixtures, separate from new transfer acceptance |
| owned-input-stream-regression.log | 1 selected existing test / 12.43s, three filtered: core_io and alloc_io fixtures under current imports |

Admission uses strict ELF/jump checks and full tracing with only entry/exit
and matched memory owners. The String test's selected memory/write filter
observes no allocation, release or write inside validation/transfer phases;
it is not an all-host-call observation. The model/resource fixtures needed
grammar/type corrections before execution, without compiler/production changes.
The [direct](../tests/fixtures/stdlib_foundation/owned_input/README.md),
[model](../tests/fixtures/stdlib_foundation/owned_input_model/README.md) and
[resource](../tests/fixtures/stdlib_foundation/owned_input_resources/README.md)
guides retain exact retry/source scopes, including failure before an unobserved
EOF reservation. Old stream/String
receipts retain their original source/API scope; they do not establish the new
collector. Existing regressions remain separate from new API acceptance.

The accepted profile is native Linux x86_64 CPU output from the GPU
compiler, with existing allocator/provider target limits. Other backends and
user-GPU execution need separate evidence. No compiler, ABI, extractor, proof
or host-service change belongs here; broader library and lifetime work remains.

## Focused targets

Run targets separately; fixture guides retain exact accepted filters.

```sh
cargo test --test stdlib_owned_input_execution
cargo test --test stdlib_string_byte_transfer_execution
cargo test --test stdlib_owned_input_model_execution
cargo test --test stdlib_owned_input_resource_execution
cargo test --test stdlib_input_stats_execution
```
