# Portable positional-I/O schedule model

This fixture models `core::io::read_exact_at`, `write_all_at`, `valid_range`
and `valid_position` against the fixed
[positional-I/O contract](../../../../docs/library-positional-io-plan.md).
Production behavior is implemented in Lanius. The Python reference and binary
adapter are test infrastructure; no native files or host positional services
are involved in this gate.

## Finite corpus

There are **11,012 cases**, with seed `0xa71020261030`. Every dataset runs as
both a read and a write, using both a native descending-byte array and a packed
ascending-byte array. The request uses a nonzero array offset where applicable;
the full 32-byte backing is observed after each operation.

| Dataset family | Cases |
| --- | ---: |
| All 585 scripts of length zero through three over eight outcomes, each with budgets 0, 1 and 4, in all operation/layout combinations | 7,020 |
| Twelve array-range shapes, eight positional boundaries and four budgets, in all combinations | 1,536 |
| Fourteen long/budget-boundary schedules in all combinations | 56 |
| 600 seeded mixed schedules in all combinations | 2,400 |

Scripted outcomes include full/short/zero success, Interrupted, WouldBlock,
other public errors, Host payloads `5`, `0`, `-123` and `i32::MAX`, and malformed
counts `-1`, `i32::MIN`, `i32::MAX` or one beyond the requested remainder.
Scripts may contain outcomes after completion; those must remain unconsumed.
After a script ends, its provider returns zero. Malformed-count provider
controls deliberately publish no bytes; this does not assert that a helper
can roll back arbitrary provider effects.

The independent reference uses a finite attempt schedule and a sequence of
confirmed byte chunks. It derives later offsets, positions, remaining counts
and completed progress from that sequence, then checks the entire emitted
provider transcript. Read bytes depend on the full position, including high
bits, and write captures contain the actual source bytes. The reference also
checks every destination/source byte and unselected sentinel, exact failure
kind, signed Host payload, returned progress and both validation predicates.

Positions cover zero, above 4 GiB, random values below `2^48`, the exclusive
end `i64::MAX`, the last valid spans, one beyond the supported domain and
`u64::MAX`. Array metadata includes negative offsets/counts, logical addition
overflow and valid empty ranges at `i32::MAX`. Every logically valid nonempty
array range in the corpus is physically backed. Budgets cover `-1..=8`, with
explicit eight-interruption exhaustion, eight short transfers, completion on
the final attempt and late WouldBlock/invalid-count failure after progress.

The CPU reference classifies 1,204 successes and 9,808 failures, including
652 failures after confirmed progress. Expected provider call counts range
from zero to eight, totaling 6,836 calls. Final error-code counts are:

| Result | Cases |
| --- | ---: |
| Success | 1,204 |
| InvalidInput | 2,500 |
| UnexpectedEof | 498 |
| WriteZero | 510 |
| InvalidCount | 1,556 |
| CountOverflow | 48 |
| LimitExceeded | 3,188 |
| WouldBlock | 700 |
| AllocationFailed | 32 |
| Host | 776 |

Interrupted appears in provider transcripts and is retried within the budget;
it is never the final helper failure. No exact/all helper may call again after
completion or a non-retryable failure.

## Protocol and acceptance

Each case starts with eight little-endian `u64` words:
`operation, layout, offset, count, position, budget, script_length, identity`,
followed by the signed script words. Signed values use two's complement.
The producer accepts at most eight script outcomes and bounds its observation
arrays. The oracle generates only the documented finite domain.

Output starts with operation, layout, success/error tag, error kind, Host
payload, completed bytes, provider calls, captured-write length, valid-range
flag and valid-position flag. All 32 buffer bytes follow, then captured write
bytes and call tuples `(array_offset, count, position, script_event)`. The
oracle compares every word and rejects truncated or extra output. Diagnostics
include the full case and seed.

CPU controls pass, including manually checked short/interrupted completion,
invalid-count partial progress, exhausted interruption budget, an invalid
terminal position and a negative Host payload. Five deliberate corruptions
(completed count, sentinel byte, high positional bits, captured write byte and
Host payload) are rejected.

The registered Rust gate is
`independent_positional_schedules_match_calls_bytes_errors_and_confirmed_progress`
in `stdlib_positional_io_model_execution`. It uses shared strict x86 ELF checks
and one batched native process, with an 85-second outer timeout and a 70-second
child timeout. Intended executable target: native Linux x86_64 CPU output
from the GPU compiler. Host pread/pwrite, cursor preservation and staging are
covered by separate native contract fixtures. This gate makes no direct GPU
execution, atomicity, crash-durability or formal verification claim.

The first registered runtime run passed: **one test and all 11,012 cases in
4.38 seconds**, with both operations, both layouts and seed `0xa71020261030`.
The log is `target/stdlib-work/positional-io-model-first.log`; its exact summary
is `positional-io cases=11012 operations=2 layouts=2 seed=0xa71020261030`.
The accepted executable target is native Linux x86_64 output from the GPU
compiler. This finite result checks the listed portable-provider observations
for this corpus and does not substitute for native descriptor acceptance.

Tested SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/io.lani` | `cd9edded4e607a9e85b97c5bcae8243bcbe0660a59af4411ada24c3d04fb8ee1` |
| `model.lani` | `66620fd0e98d0ddd28683adb389e9a9f38a1e17a709d9f5aa7ef883350edbb89` |
| `oracle.py` | `049cd156087a255fa1a4e47a91ce4d5e924bb64bc346477e1bb67244caf6cdfc` |

```sh
python3 -B tests/fixtures/stdlib_foundation/positional_io_model/oracle.py controls
python3 -B tests/fixtures/stdlib_foundation/positional_io_model/oracle.py /path/to/model
```
