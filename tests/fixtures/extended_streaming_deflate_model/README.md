# Streaming DEFLATE independent model

This fixture checks the borrowed streaming encoders in `ext::deflate` and
`ext::compression`. Production compression is Lanius. Python's system zlib is
only a test oracle. The fixture exchanges a strict little-endian binary
protocol; it uses no JSON transport.

## Fixed corpus and independent observations

Seed `0xdef1a7e0261115` selects **112 cases and 260 complete passes** over
28 input patterns: 112 whole-input passes, 112 irregular passes, and 36
byte-at-a-time passes limited to inputs of at most 64 bytes. These passes
consume 5,934,732 input bytes. The four entry routes are the raw `ext::deflate`
API and the container API's RawDeflate, zlib and gzip modes. They produce three
wire formats. The summary's `formats=4` counts these entry routes. Every case
reuses its workspace through reset.

Inputs include empty and one-byte streams, all 256 byte values, high literal
codes, seeded incompressible data, overlapping repeats, almost-matching runs,
repeated random blocks, lengths 32,767/32,768/32,769 and 65,536/65,537, and
three-block streams of 70,000 bytes. A 23-byte distinct high-literal vector
forces the fixed/stored size tie; a 31-byte vector forces stored selection.
A full repeated block supplies the fixed match witness.

There are eight selected layout combinations, using actual native byte stride
`-8` and independently backed packed byte stride `+1`. Source, destination and
block workspace are selected independently; the pending workspace has the
opposite orientation from the source. These are not all 16 combinations of
four independent byte buffers. Native i32 scratch is packed with stride `+4`.
All views are interior spans with explicit surrounding guards. The unused raw
or framed cursor is an inactive witness over the same workspace; only one
cursor has active ownership, and the fixture never alternates between them.

The oracle does not port the compressor or predict its match search:

- System zlib decodes the complete native output and must produce every
  original byte with EOF reached and no unused/trailing data. zlib/gzip headers,
  Adler-32/CRC-32 and gzip size are independently checked.
- A separate RFC1951 bit reader inspects stored/fixed blocks, reconstructs
  their bytes and verifies fresh match history, nonfinal full 32 KiB blocks,
  the required empty stored alignment after nonfinal fixed blocks, and a final
  partial block including the empty block at exact multiples. The selected
  wire never exceeds the stored candidate. It does not assert global optimal
  compression or equality with the older whole-input encoder.
- An independent two-channel event sequence consists of input intake,
  final-promise barriers and opaque publication spans derived from those
  inspected blocks. It checks **exact read/written/status for every call**,
  pending output before further intake, zero-output calls, deferred finalization
  and partial headers/trailers. It contains no Huffman or matching state.
- Complete output wire must agree across all schedules, reset passes, raw and
  framed bodies, and layouts. Framed input limits exactly equal the source size;
  the output limit is `u64::MAX`.
- Every call serializes all 2,056 destination cells, including untouched tails
  and guards. The fixture immediately poisons each consumed input prefix and
  later serializes the entire source extent and its guards. Workspace guards,
  reset state, cumulative counters, fused Done and Bounds-before-Done are
  observed. Input and output views are not retained by the test harness.

The independent event sequence uses the validated native block byte lengths;
the independent zlib and RFC readers establish their content and structure.
This separates compression correctness from incremental scheduling without
duplicating the production compressor. Full physical backing, exclusive aliases
and lifetime validity remain caller obligations rather than proofs supplied by
these tests.

## Execution and scope

The Rust driver uses the shared GPU compiler helper and verifies an x86_64 ELF
before executing one batched native process. The subprocess limit is 75 seconds
and the outer host-reference limit is 90 seconds. At most 2,000 calls are
admitted per pass; input storage is bounded by 70,000 bytes. The model performs
no allocations in the Lanius producer. The root agent ran the native gate:
**1 passed, 0 failed in 13.74 seconds**, after a separate 1.06-second Rust build.
The accepted log is `target/stdlib-work/streaming-deflate-model.log`.

Accepted source SHA-256 values:

- Producer: `b0c7b363d3f342117f107b0390db12d4ff67624e2ead766ab4f8c1367d4ba416`
- Oracle: `975b8933b6063a2b4fa3d97d5934e9e0247dcb878e924a62a70119901973e9d5`
- Driver: `8a22069ac9c32b9cd59ee3597d816e346c93f3f376a3f1c8d8b60fb448db9e2d`

Selector:

```text
--test extended_streaming_deflate_model_execution streaming_deflate_matches_zlib_block_policy_progress_and_chunk_invariance --exact --nocapture
```

Observed complete summary:

```text
streaming-deflate-model cases=112 passes=260 patterns=28 whole=112 irregular=112 bytewise=36 input_bytes=5934732 formats=4 layouts=8 seed=0xdef1a7e0261115
```

Separate pure Python controls passed on synthetic literal/stored streams,
including a final empty block after full stored blocks. They checked 20 cases /
52 passes / 2,381 calls / 787,696 wire bytes and a 6,185,636-byte transcript,
rejecting
22 deliberately corrupted transcripts or semantic streams: counts, status,
limits of the offered span, final promises, cumulative totals, actual stride,
output data/tails/guards, workspace guards, truncation/trailing data, changed
plaintext and a full block incorrectly marked final. Nine separate reference
streams checked the RFC reader's fixed-match/overlap handling and a
constructed nonfinal fixed/alignment/final-empty stream. These controls test
the oracle and are not native acceptance or a formal verification result.

The accepted target is Linux x86_64 CPU execution of GPU-compiled
Lanius. GPU device execution, other targets, fault campaigns and physical
resource ownership are covered only where separate gates explicitly say so.
