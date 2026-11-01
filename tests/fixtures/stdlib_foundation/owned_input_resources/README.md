# Owned input resources

Both registered resource gates passed compiler/native acceptance with the
amended fixture. The parent agent ran all compiler, Cargo and native commands.
This fixture checks allocation lifecycle and error
ownership around the [bounded owned-input contract](../../../../docs/library-owned-input-plan.md).
It complements the direct protocol/state-model tests and the separate String
transfer contract; it is not an exhaustive allocation-fault campaign.

The first resource gate stopped before native execution with fixture diagnostic
LNC0016 at `collection.lani:40:47`: block match arms are not accepted by the
current grammar. The fixture was corrected to expression arms and ordinary
helper functions, with its other match arms audited for the same syntax.
The second attempt also stopped before native execution: LNC0006 at
`collection.lani:97` rejected an i32 count passed to raw `write_stdout`, whose
count parameter is usize. The parent applied the explicit `count as usize`
conversion. All four raw I/O call sites were then audited against their actual
`std::io` signatures: pointer arguments are ptr, counts are usize literals or
the explicit cast, and operation results are i32. The variable count is positive
and at most 262147 before conversion; partial-write progress stays in i32.
No further fixture type issue was found by that static audit. No production,
driver or compiler change was made. Neither authoring stop establishes a
runtime result. Diagnostics are recorded in
`target/stdlib-work/owned-input-resources-first.log` and
`target/stdlib-work/owned-input-resources-retry.log`.

The amended growth/adoption gate passed one test with one filtered in 6.86
seconds, recorded in `target/stdlib-work/owned-input-resources-amended.log`.
All four modes passed. Each 262147-byte case made 258 actual calls and matched
ten successful mappings to ten exact releases; valid and invalid text each
completed one pure transfer phase. The one-byte case made two calls and
matched two mappings/releases. The allocation-failure gate then passed one
test with one filtered in 7.44 seconds, recorded in
`target/stdlib-work/owned-input-allocation-failures-first.log`. All seven
selected mmap failures were reached; the expected retained prefixes and exact
call counts passed, every same-reader recovery succeeded, and every successful
mapping had its matching complete release. Production and Rust driver behavior
were unchanged throughout these fixture corrections and accepted runs.

## Scripted input, actual owners

`collection.lani` reads one configuration byte from stdin, then provides its
payload through an actual `core::io::Read` implementation. The provider writes
valid private scratch storage, advances its position only for confirmed bytes,
and records every delegation. It performs no host read for payload data.

| Mode | Input and limits | Terminal observation without injection |
| --- | --- | --- |
| 0 | 262,147 binary bytes, exact byte cap | Complete Vec after 258 actual calls |
| 1 | 262,147 valid UTF-8 bytes, exact byte cap | String adopted after 258 calls |
| 2 | Same text pattern with invalid byte 255 at offset 1300 | Text failure after EOF, retaining all raw bytes |
| 3 | One binary byte with a 2048-byte cap | Complete Vec after two calls and a reservation before the second call |

The binary pattern includes NUL and arbitrary high bytes. The text pattern
includes NUL and valid two-byte sequences split across ordinary 1024-byte
requests. Its final extent ends on a scalar boundary. Mode 2's malformed byte
is the first invalid UTF-8 sequence, independently checked by Python's UTF-8
decoder. After reporting the original raw error-owned bytes, the fixture repairs
that one byte, adopts the existing Vec into String and transfers it back.

Every observation writes a fixed 48-byte little-endian header followed by the
complete observed raw bytes. The registered Rust driver independently computes
the expected payload. It checks cause, retained length, per-invocation calls,
provider position, cumulative provider calls, capacity, absent extra byte,
UTF-8 error offset, input length and mode. It compares every emitted byte;
an exit code alone is insufficient. Repaired bytes are also compared in full.

## Finite allocation-failure schedules

One real mmap call returns ENOMEM through strace injection in each schedule.
Every injected failure must actually be reached exactly once. Later allocation
calls succeed, so the same reader can be resumed through the public collector.

| Mode | Failed mmap ordinal | Confirmed prefix | Calls before failure | Retained capacity |
| --- | --- | --- | --- | --- |
| 0 | 1 | 0 | 0 | 0 |
| 0 | 2 | 1024 | 1 | 1024 |
| 0 | 5 | 8192 | 8 | 8192 |
| 0 | 10 | 262144 | 256 | 262144 |
| 1 | 1 | 0 | 0 | 0 |
| 1 | 5 | 8192 | 8 | 8192 |
| 3 | 2 | 1 | 1 | 1024 |

The original Vec error must be AllocationFailed, extra must be absent, and
the error-owned prefix must be intact. The fixture transfers its cleanup
authority explicitly through `take_iter`/`take_remaining`, leaving the failure's
Vec empty. Destroying that empty failure twice must have no resource effect.
The original prefix remains live and unchanged through successful recovery.
The driver concatenates the full original and recovered byte observations and
requires exactly the original input, without loss, duplication or invention.
Recovery starts at the retained provider position; calls are counted anew for
the helper while the provider's cumulative count continues.

Mode 3 witnesses an allocation failure before a call that would have returned
EOF. After its one byte has been confirmed, reserving the next 1024-byte request
requires capacity 2048. Failing that reservation must preserve the byte and
report one call. Recovery with a zero-byte remaining cap makes one real EOF
probe and allocates nothing. The collector does not guess EOF from a short read.

## Observable growth and ownership transfer

The genuine large-input modes require the capacity request sequence
1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 262147.
This finite observation checks geometric growth, its capped last request and
the absence of one allocation per byte/read. The final one-byte cap probe must
not allocate. No wall-clock performance guarantee follows.

The provider emits `R` for every actual Read invocation and `E` only immediately
before returning a real Ok(0). `C`/`F` delimit each public collection call. The
full syscall trace requires no host work after an injected reservation failure
until collection returns, so there can be no later provider delegation. It also
requires no allocation or release between actual EOF and the helper return.
For text mode this interval includes UTF-8 validation and adoption of the
existing Vec backing into String.

`P`/`p` bracket subsequent ownership-only work: successful String `into_bytes`,
or invalid-text repair, Vec adoption and inverse transfer. Every syscall is
forbidden inside these phases. The fixture checks pointer/capacity identity,
source-owner emptying and exact bytes. Empty former owners are explicitly
destroyed within the phase, requiring no release. Real returned owners are
destroyed once outside it; repeated destruction of an emptied owner is inert.
All stale shallow aliases remain inactive after authority transfer.

The driver admits only actual x86_64 ELF through the existing strict jump gate.
With full syscall tracing, it requires every successful mmap address and exact
requested length to have one matching successful munmap, rejecting unknown or
duplicate releases and every leaked live owner. Growth releases and final
returned-owner cleanup share the same address/length ledger. No arbitrary
successful allocation or I/O return is injected. Outside explicit markers,
the only admitted host effects are process entry/exit, the single configuration
read, real allocation/release and completed-observation writes. `D` is allowed
only after the live owner ledger is empty.

There are four genuine native lifecycles and seven selected fault lifecycles.
Each is bounded to ten seconds; each registered selector is a separate narrow
gate. Accepted evidence is restricted to finite Linux x86_64 CPU execution from the GPU
compiler. User-program GPU execution, other targets, arbitrary provider
misbehavior, automatic lifetime enforcement and formal verification are not
claimed.

CPU-only controls independently checked all seven failure-prefix/recovery
schedules, the large UTF-8 pattern and split boundary, malformed offset 1300,
its repair, and the expected capacity requests. These are arithmetic and
oracle controls, not native receipts.

| Executed source | SHA-256 |
| --- | --- |
| `collection.lani` | `5ebd8e19b26b557faa9d6cca203d549045b2be3fb24df17f7b6142a05aad0fcf` |
| Rust driver/oracle, tested before formatting | `419e154a0186e6fb93b205c4514b68d13321a186f30a09346085de5fbcd04b80` |

```text
cargo test --test stdlib_owned_input_resource_execution owned_input_geometric_growth_and_text_adoption_release_actual_owners -- --exact --nocapture
cargo test --test stdlib_owned_input_resource_execution owned_input_reached_allocation_failures_precede_consumption_and_allow_recovery -- --exact --nocapture
```
