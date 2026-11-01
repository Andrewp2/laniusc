# Borrowed reader adapter model

The finite model checks `core::io::Take` and `Chain` across **1,576 cases and
14,544 mixed operations**, using seed `0x10ada0261106`. Each case runs a sequence
against one of four real Lanius compositions:

- `Take<Provider>`.
- `Chain<Provider,Provider>`.
- `Take<Chain<Provider,Provider>>`.
- `Chain<Take<Provider>,Take<Provider>>`.

The producer constructs all five adapter objects without invoking a source,
then operates only the selected composition and requested quota setters.
Unused objects retain observable inert state. A setter may update a nested Take
between operations; no buffered view remains live across that update. There
are no source owners, host data reads or allocations in this fixture's modeled
providers. Stdin/stdout exist only for the test protocol. Actual buffered owners
and allocation failures belong to the separate composition/resource tests.

## Reference and state space

The Python reference interprets a graph of provider, quota and selection states
against byte-provider events. It does not import the production implementation.
It records complete event history, and checks conservation/monotonicity laws
separately from output serialization: quota changes equal acknowledged progress,
faults and handoffs cannot reverse, source cursors stay inside fetched data,
source bytes never change, zero requests and setters invoke no source, and a
faulted outer adapter invokes no source. Literal controls check complete stream
prefix reconstruction for all four compositions, quota reopening after EOF,
committed handoff after a second-provider error, and inner-fault propagation
without falsely faulting a healthy outer adapter.

The corpus combines explicit boundary sequences with 192 seeded mixed sequences.
It includes all error variants with exact Host payloads, ordinary
`Err(InvalidCount)`, malformed successful counts, negative/overflowing fill
metadata, mismatched consume acknowledgements, valid empty fills at extreme
starts, quota exhaustion and reopening, transient EOF, second-provider recovery,
short reads, reads mixed with fill/consume, local bounds precedence, full
`u64::MAX` quotas, and values above the signed 32/64-bit boundaries. Nested
compositions expose both outer and inner state; reopening an inner first quota
cannot reverse a Chain's earlier handoff.

Provider schedules intentionally include broken successful responses. These
fixtures retain their cursor on such responses; that is fixture behavior, not a
library rollback guarantee. Honest reads copy at most the requested amount,
fills reveal existing unread bytes or fetch a bounded new chunk, and normal
consume rejects requests beyond the provider's current unread bytes. EOF is an
observation rather than provider retirement. Every nonempty destination that can
reach an honest provider has actual backing; overflowing/negative descriptors
must reject before access.

There are eight actual combinations of source A, source B and destination
storage. Each uses either a native u8 array (byte stride -8 on the accepted
native compiler profile) or packed raw u8 storage (stride +1). The output records
all three original strides. Returned fill metadata and stride must preserve the
selected source, except Take's exhausted-quota view, whose null raw slice has
stride +1 and length zero. Every fill byte is observed immediately before any
further operation.

## Complete observations

Every operation reports its success/error, exact payload or count, fill
start/length/stride/bytes, all adapter quotas/handoff/fault flags, both provider
cursors/fetched positions and call counts, all 32 destination bytes, all 32 bytes
of each source, and the exact ordered provider calls with original offset,
admitted count, scheduled event and pre-call cursor/fetched state. This includes
all guards and prior destination effects; short reads cannot silently fill the
remainder. Input bytes use distinct high-bit patterns and embedded low bytes.

All state is compared after every action. These are finite model cases, not an
exhaustive statement about arbitrary programs or provider behavior. No automatic
ownership, borrow checking or recovery from a broken provider is claimed.

## Protocol and gate

One native process receives the full batch. Input starts each case with eight
little-endian u64 words: composition, layout, both source lengths, three quotas
and action count. Each action adds six words: operation, offset/setter target,
count, replacement quota and both provider events. Signed values use their
signed u64 representation. Output is raw little-endian u64 words. Expected
lengths come from the complete operation sequence and contract; extra or
truncated output, nonzero exit and stderr all reject. Mismatches report the
seed, case and first differing word. No JSON or production transport is added.

Test selector:

```text
independent_reader_adapters_match_mixed_protocol_events_quotas_faults_and_compositions
```

The Rust driver requires a native Linux x86_64 ELF and the shared executable
writer's jump containment checks. The host oracle has a 90-second timeout and
its native subprocess a 75-second timeout. Root owns compiler/native execution
under the repository's serial compiler lock.

## Evidence

Host-only controls passed all 1,576 encoded references and the independent
literal sequence laws. Nine corruptions were rejected: original stride,
reported count, quota, source position, destination byte, source guard, forwarded
offset, truncated output and extra output. These controls are not native library
cases. The source distribution is 392 cases for each of the first three
compositions and 400 for the fourth.

The native model passed **1,576 cases / 14,544 actions**, covering all four
compositions and eight layouts with seed `0x10ada0261106`. The focused test
passed in **8.02 seconds**, after a separate 0.27-second warm Rust build. The
local receipt is `target/stdlib-work/io-adapters-model-second.log`. Accepted
producer SHA-256:
`76d9af55c6c19841146dfbff504828e0986520aaa1ef7c1bd90b8f9d78a8e430`.

The first attempt stopped during compilation because this fixture used
unsupported negative integer match patterns. Changing those patterns to a
positive discriminant fixed fixture syntax; that attempt executed no native
program and required no production or compiler change. The oracle and corpus
were unchanged.

This receipt establishes finite runtime behavior on **native Linux x86_64 CPU
output from the GPU compiler**. User GPU execution, other platforms and formal
verification require separate evidence.
