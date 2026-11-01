# Streaming deflate direct and resource gates

Driver: `tests/extended_streaming_deflate_execution.rs`.
Contract: `docs/library-streaming-deflate-plan.md`.

All four selectors passed across the focused invocations below. Independent
source/harness review passed, including the metadata-only literal correction
at its final hash. Review added no runtime executions. Root alone performed
compiler/native commands.
Rust formatting, static checks and a host-only zlib check of the exact literal
wires passed. These controls do not replace native runtime evidence.

## Admission receipt

`streaming_deflate_raw_zlib_gzip_native_admission` passed 1/1 in 5.44 seconds,
after a 0.19-second Rust build, recorded in
`target/stdlib-work/streaming-deflate-admission-final.log`. It observed three
exact workspace allocations and releases, 0.008725 seconds native process
time and 5.429589 seconds compilation. The source hashes were raw `f1dd114f`
and framing `4d23bd47`; the admission driver was
`4c338ca79d525bb546948ebf3fbcfa030e251f751a3928622171e0a44501074d`.
The subsequent driver adds three selectors and a zlib oracle without changing
the admission selector, runner or ledger.

The first attempt failed during compilation in 3.53 seconds because the
framing implementation used unsupported block-valued match-arm syntax. No
native admission ran in that attempt. The framing author corrected the syntax;
the admission producer, support module and driver were unchanged for the
passing retry. This is one accepted native admission, not two executions.

`admission.lani` checks exact literal bytes through raw output suspension,
immediately overwrites consumed input, drains the saved bytes, checks fused
Done and reset, and compares deterministic empty raw/zlib/gzip output.
Nonzero workspace/output offsets and sentinels are checked. All borrowed
operations occur inside one phase that rejects every host effect.

## Focused direct/resource receipts

The next invocation ran the remaining three selectors, recorded in
`target/stdlib-work/streaming-deflate-direct-resources.log`: two passed and
one failed in 14.49 seconds after a 1.16-second Rust build. The accepted native
observations are:

- Framing/limits/stride: twelve empty output-limit cases, three bytewise
  framed streams, the three nonzero-input body-limit cases, and all 32,769
  recycled source bytes. Four exact allocations and releases; native process
  time 0.015170 seconds, compilation 8.911244 seconds.
- Scale: eight streams, all 6,357,096 original bytes independently decoded,
  3,207,473 encoded bytes, 1,961 pure phases, and five exact allocations and
  releases totaling 208,933 bytes. Native process time 3.914524 seconds,
  compilation 1.009526 seconds.

The metadata fixture failed during compilation with LNC0069: the literal in
`4294967296 as u64` was checked as i32 before the cast. It never executed
natively. The fixture now binds `let wide_limit:u64 = 4294967296` and uses that
value in both allowance fields. This preserves the tested boundary at 2^32,
beyond the u32 range; no compiler or production change was needed. Only this producer
changed, from `c8c6ff81` to `812c45be`; the accepted framing/scale producers and
driver are unchanged.

The corrected metadata selector then passed 1/1 in 5.63 seconds after a
0.19-second Rust build, recorded in
`target/stdlib-work/streaming-deflate-metadata-final.log`. It checked complete
196,637-byte workspace snapshots with six exact allocations and releases.
Native process time was 0.150638 seconds; compilation took 5.471175 seconds.
Only that failed selector was retried; the earlier accepted framing and scale
selectors were not repeated. Independent review accepted the typed literal
correction with all behavior assertions and other frozen sources unchanged.

## Metadata, reset and terminal state

Selector:
`streaming_deflate_metadata_first_recovery_reset_and_terminal_state_preserve_backing`

`metadata.lani` exercises negative starts, negative lengths and overflowing
end indices independently for all three workspace descriptors. Other
workspaces are short in these cases, proving metadata rejection precedes
capacity errors. Null-backed invalid descriptors must never be dereferenced.
The three actual insufficient capacities check exact raw errors and framed
error mapping. Successful construction must leave every workspace byte intact.

Six input/output metadata classes are checked before work, while encoded bytes
are pending, after Done and after a sticky container error. Bounds failures are
0/0, recoverable, output-preserving and metadata-first. Complete workspace
snapshots compare all 196,637 backing bytes, rather than selected sentinels.
Reset preserves backing while discarding buffered or pending raw data and
resetting container format, counters, checksum and failure state. Wide u64
allowances at 2^32, beyond the u32 range, must admit the ordinary literal
stream. Extra offered workspace suffix entries remain guards outside the
required prefixes.

The selector uses six exact owners: three actual workspaces and three snapshot
buffers. It has one pure phase and no output publication.

## Framing limits, strides and input recycling

Selector:
`streaming_deflate_exact_limits_bytewise_framing_and_strided_recycled_input_execute`

`contracts.lani` checks empty-stream output allowances at zero, one, one byte
short and exact size for all three formats. OutputLimit is sticky and reports
the initialized prefix exactly; exact-fit completion succeeds. Three literal
body-limit cases also check nonzero consumed-input counts on failure. Whole
offered-input admission occurs before queued headers can emit any bytes.
One-byte output traverses every header, body and trailer boundary for an exact
literal stream in each format. Reset abandons a partially emitted gzip header
and starts a complete independent zlib stream.

A separate full-block raw stream uses native u8 arrays with asserted negative
byte strides for block storage, pending storage and output. Its input is an
actual packed owner with stride +1; hash scratch has stride +4. Every view has
a nonzero start, and workspace suffix capacity exceeds the admitted prefix.
The stream consumes 32,768 repeated bytes with no output, immediately
overwrites that entire source, and proves another input byte waits behind
pending output. After the final byte is consumed, it too is overwritten.
All guards and output suffix bytes remain intact. System zlib independently
decodes the complete output to all 32,769 original bytes.

This selector uses four exact heap owners. The negative-stride arrays are
fixed local workspace, not hidden heap allocations. One pure phase encloses
all encoding and checking; publication occurs afterward while its explicit
packed output carrier remains live.

## Fixed-owner scale

Selector:
`streaming_deflate_large_profiles_recycle_fixed_owners_and_match_complete_independent_decode`

`scale.lani` runs eight streams: raw repeated/random data at 32,769 bytes, then
both profiles in raw, zlib and gzip at 1,048,593 bytes. The repeated profile is
a 31-byte period; random bytes use a fixed xorshift32 seed. The host constructs
both profiles independently and uses system zlib to check every decompressed
byte, exact compressed-input consumption and successful stream termination.
The total is 6,357,096 source bytes. The driver also checks the stored-block
upper bound, including the mandatory final partial block and framing overhead.

The same five owners remain live across all eight streams: guarded block,
pending and hash storage, a 4,099-byte input carrier, and an 8,197-byte output
carrier. Their exact allocation sum is 208,933 bytes. Active input/output
chunks are at most 4,093 and 8,193 bytes; there is no complete source or output
allocation in Lanius. Every consumed input prefix is immediately overwritten.
Unread bytes, output prefixes/suffixes, workspace guards and exact cumulative
counters are checked after every step. Caller input/output views are never
retained. Each stream begins with a zero-output call and has a 4,096-step bound.

Reset and every step occur in full-syscall pure phases. Output chunks are
published between phases; no allocation/release is allowed between workspace
admission and explicit final cleanup. All five owners must be released once.
This is fixed-storage execution at two sizes, not a compression-ratio or
compiler-throughput claim. Native timing is reported separately from
compilation and includes tracing, source generation, checks and publication.

## Exact resource admission and scope

The three base extents are 32,772 bytes, 32,777 bytes and 131,088 bytes. They
derive from the public workspace sizes plus four guard entries each; packed
`i32` scratch occupies four bytes per entry under `core::mem`'s layout rule.
All heap buffers are actual `alloc::vec` owners. The ledger uses full-width
addresses and exact extents, rejects overlap, unknown/repeated releases and
incorrect lengths, and requires complete cleanup before a terminal marker.
Process exit is not cleanup evidence. Every stdout write occurs with the
entire admitted owner set still live. Pure phases prohibit all intervening
host effects. No artificial allocation-failure campaign targets borrowed
encoding; actual application-owner failures belong to the file consumer tests.

Each artifact must be ELF x86-64 and pass the shared complete jump validator.
Native processes have a twenty-second timeout. Initial evidence is limited to
Linux x86-64 CPU output from the GPU compiler. System zlib is linked only by
the Rust test oracle; production encoding remains Lanius. No device execution,
other host, borrow checker, automatic cleanup or formal proof is claimed.
Broader chunk-invariance and block-policy states belong to the independent
model gate; these groups concentrate on public contracts and actual storage.

## Frozen hashes

- Driver: `96e5ae5d154bd8a2c3f42faadf6dd2fb420ca0369b022c38b2b1bb40de37127a`
- `fixture/support.lani`: `af290e6cf53c6da56ec328b9a65c2aa7eb116421908390c704561cc18ef32a61`
- `admission.lani`: `6f16d64129e42e5ddbcbef005c3b17edb3c2b562bc50579e119278f9d0770ae6`
- `metadata.lani`: `812c45bea5529489bd1d62bb2293fa3a8baceab9a44d2341843a162f241f8840`
- `contracts.lani`: `4719ea8377c0593fac502bdfd2ac1366625eeaac2a046c7f0298137297cfc890`
- `scale.lani`: `22d06c5b0b3648b7edae4a24a421926e1867bb4ea5c3f072896feb8dec5ff4d0`
