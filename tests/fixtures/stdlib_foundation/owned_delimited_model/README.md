# Owned delimiter and line state model

This fixture executes `alloc::io::read_until` and `read_line` against an
independent finite provider and record reference. Production remains Lanius;
Python and binary framing are test infrastructure only. The oracle does not
model allocation growth, capacity choices or the production scan implementation.

## State and observations

The provider tracks bytes acquired by fill separately from consumption confirmed
by an exact consume success. Filling preserves an existing pending chunk, and
scripted zero fills can report a transient EOF followed by later input. Each
fill/consume delegation records its kind, scripted event, prior cursor, prior
fetched position and requested consumption. Errors and malformed consume counts
deterministically leave the fixture's pending bytes unchanged. That last policy
is specific to this test provider; it is not a public rollback guarantee for
nonconforming providers.

Two calls run on the same provider in every case. Each may select binary or LF
text mode with its own byte and call limits. The reference selects records from
materialized byte prefixes using delimiter partitioning. Host strict UTF-8
validation runs only after a terminal delimiter or observed EOF. Expected values
include every raw byte, success/error variant and payload, ending, exact calls,
confirmed consumption, cursor, fetched position and cumulative event transcript.
This checks resumed input and unconsumed buffered suffixes, including duplicate
unacknowledged bytes after a rejected consume. A staged suffix is never treated
as confirmed consumption.

Both actual source representations execute: a native byte stack slice with
negative stride and a packed byte slice with stride +1. The native stride's
magnitude is deliberately unspecified. Provider Views start at backing index
`2 + cursor`; literal start/length metadata is used, without `view_range` or
`subview`. All 40 source cells, including surrounding guards, are checked after
each call. Returned Vec/String owners and retained failure owners are explicitly
released after observation.

## Finite corpus and CPU controls

There are **15,724 distinct cases / 31,448 invocations**, seed
`0xd3110261104`, with payloads of at most 32 bytes. The corpus crosses all short
fill histories of length 0..2 over seven events with successful, interrupted,
failed and malformed consume schedules and call quotas. It also covers:

- Every provider error and malformed metadata/count category at entry and after
  progress; metadata at the final fill quota and at zero byte room.
- Zero/negative/exact byte caps, delimiter at the cap, observed empty EOF,
  exact-fit unterminated EOF, pending bytes beyond the cap, and a final nonempty
  fill that leaves no quota for consume.
- NUL, LF and high-bit delimiters; consecutive records; CR/LF and NUL retention.
- Valid multibyte UTF-8 and malformed/overlong/surrogate/out-of-range/truncated
  text split at every byte boundary; terminal errors retain the entire record,
  while incomplete-prefix I/O, byte and call failures take precedence.
- Seeded binary payloads, partial chunks, both text/binary recovery directions,
  fill Interrupted retries and consume Interrupted without retry.

CPU expectations classify the 31,448 invocations as 14,080 successes, 96 invalid
limits, 2,810 call limits, 3,260 byte limits, 8,116 I/O failures and 3,086 terminal
text failures. There are 5,368 delimiter endings and 11,798 EOF endings; 14,282
failures have no terminal ending. These are reference corpus counts, not
separately traced production coverage counters. Storage failures are not
injected by this model and have a separate focused gate.

Literal controls independently pin exact delegation counts, delimiter inclusion,
EOF before byte-cap rejection, metadata precedence, copy-before-consume failure,
resumption, fill retries, exact-cap EOF versus pending input, terminal UTF-8
indices and source-error precedence. Eight deliberately corrupted serialized
outputs check that the verifier rejects altered progress, endings, retained
bytes, guards, stride, I/O identity and text indices. Those are verifier controls,
not production mutants or a proof of the library.

## Protocol and acceptance

Requests contain eleven little-endian u64 words: both mode selectors, source
layout, delimiter, source/script lengths and two byte/call limits, followed by
source bytes and fill/consume events as u64 words. Signed fields preserve their
bit patterns. Each response includes an explicit typed result, complete record
bytes, provider state, source backing and the cumulative event transcript.
Framing, full outputs and exact error identity are checked with complete
case/invocation/seed diagnostics.

The registered native test **passed on its first run**: one test in
**7.63 seconds**, with **15,724 cases / 31,448 invocations / two layouts**, seed
`0xd3110261104`. The receipt is
`target/stdlib-work/owned-delimited-model-first.log` (driver build 1.74 seconds).
The registered test is
`independent_owned_delimited_models_match_records_progress_resumption_and_utf8`
in `stdlib_owned_delimited_model_execution`. It checks executable ELF admission
and shared strict x86 jumps, then uses one batched native process with a
75-second child timeout and 90-second outer timeout. Accepted scope is finite
native Linux x86_64 CPU output produced by the GPU compiler. Large records,
allocation failures, physical access traps, sample/app behavior and destruction
history have separate gates. No GPU-device, other-target, automatic ownership,
unbounded-work or formal verification claim is made.

Independent static review found no blocker in the provider/oracle transport or
the frozen production change's arithmetic bounds, reservation order, ownership
transfer and terminal UTF-8 handling. This supplements the finite execution
receipt; it is not formal verification. Producer, oracle and production code
did not require an amendment for acceptance.

Tested SHA256 identities:

| Source | SHA256 |
| --- | --- |
| `stdlib/alloc/io.lani` | `9eeb63f40cc582d192afa43e5b2e65ffa209bbfc63d6893a3f0af155377b7392` |
| `stdlib/alloc/string.lani` | `2196e427ba4091eafc7de4c13ae66c640027fa1f3ad1b5c63b2c53b2348d6282` |
| `model.lani` | `bba9d281a9566fb11f0117fe949bcfcbb69f2dff1157b6186eae6bdcb24a676a` |
| `oracle.py` | `708bfea43bb0cf1bbd394d909490177802e82bd457f42b8b7f5e42f1da05594a` |

```sh
python3 -B tests/fixtures/stdlib_foundation/owned_delimited_model/oracle.py controls
cargo test --test stdlib_owned_delimited_model_execution independent_owned_delimited_models_match_records_progress_resumption_and_utf8 -- --nocapture
```
