# Owned delimiter resources, scale and physical boundaries

All three registered resource gates passed compiler/native acceptance on their
first attempts through separate commands. The parent agent ran all compiler,
Cargo and native commands; the author ran only bounded CPU
reference controls and static audits. These three narrow gates complement the direct and state
model tests for [owned record input](../../../../docs/library-owned-delimited-plan.md).

The accepted large-record gate passed one test in 8.38 seconds after a
1.84-second Rust build, recorded in
`target/stdlib-work/owned-delimited-resources-first.log`. All four modes passed:
multichunk binary, valid text and malformed terminal text each made 2048
fill/consume calls and matched thirteen mappings to thirteen exact releases;
the large single-fill mode made two calls and matched three mappings/releases.
Exact 1 MiB byte outputs, pending `NEXT\n`, observed String ownership transfers
and historical fields after destruction all passed.

The allocation-failure gate passed one test in 8.33 seconds, recorded in
`target/stdlib-work/owned-delimited-allocation-failures-first.log`. All seven
selected reservation failures were reached; their pending chunks remained
unconsumed, exact retained prefixes and recovery outputs matched, and every
successful mapping had its exact release. The guard gate separately passed
one test in 6.16 seconds, recorded in
`target/stdlib-work/owned-delimited-guards-first.log`: all nine observations,
the pure metadata phase and protected input passed, with nine successful
mappings matched to nine exact releases. No fixture or driver code changed
between these receipts and its recorded frozen identity.

## Materialized large records and pending bytes

`records.lani` creates one actual 1,048,581-byte Vec backing before collection.
Its first 1 MiB is one LF-terminated record; the five bytes `NEXT\n` follow it.
The provider implements the canonical BufRead protocol directly. It returns
real initialized slices into that packed byte storage, never fabricated strides
or successful counts without backing. Position advances only on exact consume.
The complete input backing remains live and unchanged through all collections.
This is a buffered protocol workload, not a host read-ahead or I/O timing test.

| Mode | Record | Visible fill size | First-record result |
| --- | --- | --- | --- |
| 0 | Binary with NUL/high bytes, LF only at its end | At most 1024 | Complete owned bytes |
| 1 | Valid UTF-8 with split two-byte sequences and NUL | At most 1024 | Adopted String |
| 2 | Same text shape with first invalid sequence at offset 1300 | At most 1024 | Text failure retaining the entire terminal raw record |
| 3 | Binary | Entire 1 MiB plus following record in one fill | Complete owned bytes, with all five later bytes still pending |

Multichunk cases require 2048 actual fill/consume calls for the first record;
single-fill mode requires two. The first delimiter must terminate collection
immediately, without an extra fill or any consume of `NEXT\n`. The next public
call returns precisely those five bytes in two calls. A final zero-byte-cap
call observes one actual empty EOF and allocates nothing.

Each returned observation is a 48-byte little-endian header followed by all its
raw bytes. The independent Rust oracle checks cause, length, calls, confirmed
consumption, ending, provider position, cumulative fills/consumes, capacity,
UTF-8 error offset and every returned byte. A successful exit alone is not a
receipt. Total output per large lifecycle is approximately 1 MiB, including
headers and the following short record; repaired text is not emitted twice.

The reserved-capacity sequence for a 1 MiB multichunk record is
1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576.
Single-fill mode reserves the selected complete 1 MiB append once. The full
trace requires exactly those requests, proving the finite workload does not
allocate per byte or per buffered chunk. With the input backing and the next
five-byte record, genuine multichunk modes have thirteen matched mappings and
releases; single-fill mode has three. There is no wall-clock performance claim.

## Seven reached reservation failures and recovery

The input backing is the first mmap. A selected later mmap returns one actual
ENOMEM; the driver requires the scheduled injected call to be reached exactly
once. There is no injected successful allocation return, consume result or
allocation-fault campaign.

| Mode | Collector reservation ordinal | Retained/confirmed prefix | Calls on failure |
| --- | --- | --- | --- |
| 0 | 1 | 0 | 1 |
| 0 | 2 | 1024 | 3 |
| 0 | 5 | 8192 | 17 |
| 0 | 11 | 524288 | 1025 |
| 1 | 5 | 8192 | 17 |
| 2 | 5 | 8192 | 17 |
| 3 | 1 | 0 | 1 |

The failed reservation follows a successful fill but precedes copying and
consume of that chunk. Storage must retain the original Vec AllocationFailed,
the exact earlier bytes and calls, confirmed consumed prefix, and absent ending.
The mode 2 failure already contains malformed UTF-8 in its prefix: incomplete
storage failure must still precede any terminal text validation.

After reporting the original error-owned prefix, the caller resumes the same
provider with the remaining byte allowance through binary read_until. The
original owner remains live and unchanged until recovery succeeds. The oracle
requires the original and recovered bytes to concatenate to exactly the first
record, then checks that the next record is still pending. These selected
Storage failures have no unacknowledged copied suffix. This does not authorize
concatenating arbitrary failures whose consume was rejected or malformed;
those separate cases can retain bytes that were not acknowledged consumed.

## Terminal UTF-8 adoption and historical fields

Provider markers expose actual delegation: `B` fill, `U` consume, `L` a confirmed
consume ending at LF, and `E` an actual empty fill. `C`/`V` delimit the public
collector. The trace requires no host work or further delegation after failed
reservation or terminal provider acknowledgement before the public return.
For read_line, that terminal interval includes UTF-8 validation and adoption.

Absence of allocation alone is not treated as pointer identity. On valid text,
the fixture observes the returned String's actual backing pointer/capacity,
transfers it through into_bytes, and checks the returned Vec's identical
pointer/capacity and the emptied String. On malformed terminal text it first
reports the complete raw failure bytes including LF, then repairs byte 1300
and adopts/back-transfers the retained buffer. Pointer/capacity identity, empty
former owners and every repaired byte are asserted. These transfers run in
`P`/`p` phases that forbid every syscall.

ReadBytes, ReadLine and BufferedReadFailure are explicitly destroyed after
their byte cleanup authority is transferred. Calls, consumed and ending fields
must retain their historical values after repeated destruction of the emptied
record. Real returned byte owners are released exactly once; inactive shallow
aliases are never independently destroyed. The fixture does not claim enforced
move/lifetime semantics.

## Guarded fills, no-access admission and byte-cap recovery

`guards.lani` maps two 4096-byte pages and protects the second with PROT_NONE.
Every positive raw view honestly covers one leading sentinel plus a selected
payload of 0, 1, 4 or 5 bytes, ending exactly before that page. Its nonzero
View start refers to real live bytes; no inaccessible storage is overclaimed.

Nine observations check empty EOF, a one-byte final unterminated record, a
one-byte LF record, a delimiter at the final accessible byte, exact-cap EOF,
a delimiter in the first byte with later bytes left pending, and a capped
`abc\nZ` view. At cap 3, `abc` is retained/consumed, LF/Z remain pending, and the
next calls recover LF then final unterminated Z with exact fill/consume counts.
Every initialized source byte and leading sentinel must remain unchanged.
The host compares each complete small record and all reported progress fields.

One P/p metadata phase supplies null backing only where prior logical checks
require no payload access. It covers negative start/length and overflowing
sums before exhausted consume quota or a zero byte cap, valid nonempty null
views rejected by ByteLimit/CallLimit without a scan, zero calls/negative limits
without any provider call, and a valid empty view at start i32::MAX accepted as
EOF. These cases must not allocate or reach any host service. Logical metadata
cannot prove backing, lifetime or arbitrary-pointer safety; native physical
traps have no rollback guarantee.

## Resource ledger, scope and frozen identities

The Rust driver requires genuine x86_64 ELF with the existing strict jump gate.
It traces all syscalls, accepting only declared setup allocation/protection,
record reservations/releases, optional one-byte configuration, explicit provider
and phase markers, completed observations and process entry/exit. Every actual
successful mmap address and requested length must have one matching successful
munmap; unknown/double releases and live owners at D are rejected. The original
provider/guard backing must be released last. The guard gate expects one page
protection and nine successful mappings/releases total, including eight record
buffers; its metadata phase has no allocation.

Four genuine large-record and seven selected-fault lifecycles each have a
15-second native bound. The guarded gate is one additional finite lifecycle.
Run the three registered selectors separately under the parent command cap.
Accepted evidence is finite Linux x86_64 CPU execution produced by the GPU
compiler, current packed byte storage and a 4096-byte base-page profile.
GPU-device execution, other targets and formal verification remain unclaimed.

CPU reference controls checked all four large modes, all seven reservation/
recovery schedules, every first delimiter position, pending `NEXT\n`, valid
split UTF-8, invalid offset 1300, its repair, and all four honest guarded extent
calculations. These are arithmetic/oracle checks, not native receipts. Static
audits checked expression-only match arms, range start/count semantics, ptr/
usize raw I/O arguments and bounded i32 operation results before freezing.

| Executed source | SHA-256 |
| --- | --- |
| `records.lani` | `c29e8856f3610096b592c54de44e6c46b74c6d5195989fad0f74b19973fd2c0e` |
| `guards.lani` | `bd3f23dfbc380f51fb2f97ec9711b9bd6196ff7b9e76721cd3eb38850d3c3ea4` |
| Rust driver/oracle, tested before formatting | `aab5ae4e6ddcc75c89047e4f461247497c2f2499425972cf68e62dc96965274c` |

```text
cargo test --test stdlib_owned_delimited_resource_execution owned_delimited_megabyte_records_grow_geometrically_and_transfer_text_without_allocation -- --exact --nocapture
cargo test --test stdlib_owned_delimited_resource_execution owned_delimited_selected_reservation_failures_retain_prefix_without_consuming_pending_chunk -- --exact --nocapture
cargo test --test stdlib_owned_delimited_resource_execution owned_delimited_guarded_fill_extents_stop_at_delimiters_and_leave_capped_data_pending -- --exact --nocapture
```
