# Bounded owned-input independent state model

This fixture checks `alloc::io::read_to_end` and `read_to_string` against an
independent finite reader-effects model and Python's strict UTF-8 decoder.
Production remains Lanius. Python and binary framing are test infrastructure;
the oracle does not model the production allocation/growth implementation.

## Observable state

The generic Read-only provider transfers actual bytes from a finite source,
using scripted maximum chunk sizes. A short success advances the source only
by bytes actually copied; conforming errors advance nothing. Empty successes
are real observations, including scripted temporary EOF. Interrupted and every
other core I/O error, invalid returned counts and post-prefix failures are
reachable. Malformed-count controls deterministically publish/consume nothing
in this provider; no general rollback/position claim is made for broken readers.

Each case runs two collections on the same reader. The first selects bytes or
text; the second selects bytes, with its own limits. Results expose the exact
owned prefix, failure cause/detail/Host or UTF-8 index, public failure call
count, retained probe byte, actual call delta, cumulative calls, source position
and script index. Every cumulative request/event/source-position record is
compared. Requests follow the specified min(1024, remaining allowance), with
a separate one-byte cap probe. This observes call-budget admission before
delegation, last-call EOF/error/probe results and no calls after termination.

The recovery collection demonstrates that EOF is not cached and that a caller
can reconstruct consumed input with the first retained extra byte followed by
later bytes. Both native descending and packed ascending source storage are
used. Each returned Vec/String/failure owner is observed while live and then
destroyed once; allocator accounting and zero-copy adoption identity have
separate gates.

UTF-8 expectations use strict host decoding and the first malformed sequence's
byte offset. Validation occurs only after actual EOF. Earlier byte/call/I/O
errors therefore preserve raw bytes without becoming Text failures. Split
multibyte sequences, embedded NUL/CR/LF, overlong forms, surrogate encodings,
out-of-range scalars, bad continuations and truncated sequences are included.
Every Text failure returns the entire confirmed raw body, not only its valid
UTF-8 prefix. No lossy decoding, newline normalization or roundtrip-only check.

## Finite corpus

There are **17,542 distinct cases / 35,084 collection invocations**, seed
`0xa11c0261103`. The first invocation selects bytes in 6,578 cases and text in
10,964; the second always selects bytes. Complete input tuples are deduplicated.

The corpus crosses every script of length 0..3 over eight progress/error
events with several limits, all provider error/count controls before/after
progress, negative/zero/one/MAX limits, every single byte, every second byte
under six constrained UTF-8 lead classes, all split points of selected valid
and invalid sequences, and 300 seeded cases. Long sources at lengths 1023,
1024, 1025, 2047, 2048, 2049 and 2052 exercise actual scratch/request and exact
cap boundaries with source bytes on both sides. No huge owner is requested
merely to test full-width call quotas; max byte limits may be large while the
source stays finite and requests stay at most 1024.

Reference classifications include 3,922 Text failures retaining their complete
raw body and 612 ByteLimit observations retaining confirmed probe bytes. These
are reference corpus counts, not independent runtime coverage counters. Storage
failures are not injected in this model; their public variants are reported
exactly and any unexpected Storage result fails the nominal model. Separate
fault tests cover actual reached allocation failure before delegation.

CPU controls check confirmed cap prefix/probe recovery, no synthetic EOF,
zero call quota, Interrupted exhaustion, invalid-count precedence on the last
call, byte-limit precedence over text validation, strict error offset/raw body,
temporary EOF resumption and a four-way split Unicode scalar. Eight deliberate
corruptions of extra byte, source position, request size, termination, spent
calls, UTF-8 index, raw failure bytes and error precedence are rejected by the
serialized-output verifier. These are verifier controls, not production-code
mutations; the independent literal controls and strict host UTF-8 decoder supply
separate semantic expectations.

## Protocol and acceptance

Requests contain eight little-endian u64 header words, up to sixteen event
words and at most 2052 byte words. Header fields select mode/source layout,
both byte/call limits and source/script lengths. Each invocation emits a
twelve-word result/state header, every owned prefix byte and the cumulative
three-word direct-read transcript. Exact framing, bytes, effects and errors are
checked, with complete case/index/seed diagnostics.

The first compile stopped before native execution with fixture syntax error
`LNC0016`: the match-pattern grammar does not admit unary-negative literals.
The initial producer's SHA256 prefix was `53d6ac10`; the receipt is
`target/stdlib-work/owned-input-model-first.log`. Replacing those patterns with
equivalent explicit comparisons preserves all reader schedules and oracle
expectations. No production or compiler repair was made. Native acceptance of
the amended producer passed **1 registered test in 7.87s**, reporting **17,542
cases / 35,084 invocations / 2 modes / 2 source layouts** at seed
`0xa11c0261103`. The receipt is `target/stdlib-work/owned-input-model-retry.log`.
This executes exact prefix, probe, call, source-state, error and raw UTF-8
failure-byte observations against the reference, beyond compilation. Per-kind
counts above classify the finite corpus rather than separately emitted native
runtime coverage counters.

The registered test is
`independent_owned_input_schedules_match_prefix_calls_probe_recovery_and_utf8`
in `stdlib_owned_input_model_execution`. It checks executable ELF admission and
shared strict x86 jumps, then runs one batched native process with a 90-second
outer timeout and 75-second child timeout. Accepted scope is finite native
Linux x86_64 CPU output from the GPU compiler. This bounds delegations, not the
duration/internal work of a reader call. Allocation failure, ownership transfer,
growth scale and real CLI/host faults have separate gates; no GPU-device,
automatic lifetime or formal verification guarantee is claimed.

Frozen tested identities (SHA256):

| Source | SHA256 |
| --- | --- |
| `stdlib/alloc/io.lani` | `2ed4586e3f33702e10c935d0e68b618fdc65ca6260d1b764cc893e7af9ee7c86` |
| `stdlib/alloc/string.lani` | `2196e427ba4091eafc7de4c13ae66c640027fa1f3ad1b5c63b2c53b2348d6282` |
| `model.lani` | `e633ac07bd7cba65faf60ef8f12e2f9da36960e9c3f2158681156686e171a8db` |
| `oracle.py` | `a517632d58b268b8dd627b19ed6b1f5685b88b7de024c7ae1a62983a0251e5d1` |

```sh
python3 -B tests/fixtures/stdlib_foundation/owned_input_model/oracle.py controls
cargo test --test stdlib_owned_input_model_execution independent_owned_input_schedules_match_prefix_calls_probe_recovery_and_utf8 -- --nocapture
```
