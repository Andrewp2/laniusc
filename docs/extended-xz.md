# xz and .lzma

`ext::xz` decodes xz streams (LZMA2) and legacy `.lzma` files (LZMA1 "alone"
format) incrementally, and encodes xz with a streaming LZMA2 encoder at
levels 0 to 3 (plus a stored-chunk writer). It is pure Lanius over caller-owned `core::slice::View` storage: it
allocates nothing and calls no host service. The decoder suspends for more
input, more output space, or a larger dictionary, and resumes where it
stopped, so callers can stream archives of any size through fixed buffers.

Executable evidence covers **x86_64 Linux with native executables produced by
the GPU compiler**. Other targets and GPU-kernel execution are unverified.

```lanius
let probs: alloc::vec::Vec<i32> = alloc::vec::new(); probs.try_resize(ext::xz::probabilities_len(),0);
let stage: alloc::vec::Vec<u8> = alloc::vec::new(); stage.try_resize(ext::xz::stage_len(),0);
let dict: alloc::vec::Vec<u8> = alloc::vec::new();
let decoder: ext::xz::Decoder = core::result::unwrap(ext::xz::decoder(probs.as_view(),stage.as_view(),ext::xz::Format::Xz));
// loop:
let step: ext::xz::Step = core::result::unwrap(decoder.borrow().step(input,output,input_is_last));
// consume step.read input bytes, use step.written output bytes; on
// Status::NeedDictionary:
dict.try_resize(decoder.borrow().dictionary_len(),0);
decoder.borrow().set_dictionary(dict.as_view());
```

## Library API

```text
Format = Xz | Lzma
Error  = Bounds | Header | Options | UnsupportedCheck | UnsupportedFilter
       | Corrupt | Checksum | Index | Footer | SizeMismatch | Truncated
       | TrailingData | Failed
Status = NeedInput | NeedOutput | NeedDictionary | Done
Step { read: i32, written: i32, status: Status }

probabilities_len() -> i32          // PROBABILITIES = 14,902 i32 words
stage_len() -> i32                  // STAGE = 65,536 bytes
decoder(probabilities: View<i32>, stage: View<u8>, format: Format) -> Result<Decoder, Error>
Decoder.step(input: View<u8>, output: View<u8>, final_input: bool) -> Result<Step, Error>
Decoder.dictionary_len() -> i32     // bytes wanted after NeedDictionary
Decoder.window_len() -> i32         // the stream's full window (the most it can ask for)
Decoder.set_dictionary(dictionary: View<u8>) -> Result<bool, Error>
Decoder.total_read() -> u64
Decoder.total_written() -> u64
Decoder.is_done() -> bool
Decoder.is_failed() -> bool

ENCODER_STAGE = 65,600 bytes
encoder_window_len(level: i32) -> i32       // 2 x dictionary bytes
encoder_workspace_len(level: i32) -> i32    // PROBABILITIES + 65,536 heads + one chain word per window byte
encoder(workspace: View<i32>, window: View<u8>, stage: View<u8>, level: i32) -> Result<Encoder, Error>
Encoder.step(input: View<u8>, output: View<u8>, final_input: bool) -> Result<Step, Error>   // NeedInput | NeedOutput | Done
Encoder.is_done() -> bool
Encoder.total_read() -> u64
Encoder.total_written() -> u64
unused_encoder(bytes: View<u8>, words: View<i32>) -> Encoder   // placeholder whose every step fails

STORE_WORKSPACE = 512 i32 words
store_encoder(workspace: View<i32>) -> Result<StoreEncoder, Error>
StoreEncoder.begin(output) -> Result<i32, Error>        // 24 bytes: stream + block header
StoreEncoder.chunk(data, output) -> Result<i32, Error>  // 1..65,536 bytes in, data + 3 out
StoreEncoder.finish(output) -> Result<i32, Error>       // at most 64 bytes
```

**Storage.** The probability workspace holds the LZMA models (14,134 words
for `lc + lp <= 4`) followed by CRC32 and CRC64 lookup tables. The stage holds
fixed-size headers and one whole compressed LZMA2 chunk (at most 64 KiB), or
the sliding `.lzma` input window. Both must stay alive, unaliased, for the
decoder's lifetime.

**Dictionary.** The decoder never needs the whole declared window up front.
It first asks for `min(window, 4096)` bytes and, whenever the buffer fills
before reaching the window, returns `NeedDictionary` with `dictionary_len()`
doubled (capped at the window). The new view must begin with the previous
view's bytes, which `Vec.try_resize` provides. Memory therefore stays near
the decoded size: a 5 KB file in a `-9` (64 MiB window) stream costs 8 KiB,
not 64 MiB. Windows over 2^31-1 bytes (LZMA2 property codes 37 to 40, or a
`.lzma` header above that) are clamped to 2^31-1; only streams whose output
exceeds that and reference further back would be affected. When an xz block
header records the uncompressed size, the window is capped at it.

**Step contract.** Each call consumes `read` input bytes and writes
`written` output bytes, then reports why it stopped. `NeedInput` means all
offered input was used; `final_input` says nothing follows the offered span,
which turns a stream that is still incomplete into `Truncated`. `NeedOutput`
means the output view filled. Errors are sticky (later calls return
`Failed`); bytes already written stay written, so a caller that must not act
on bad data should validate first (as `tgz` does) or discard on error.

## Accepted formats

**xz.** Every stream header, block header, index and footer CRC32 is checked.
Check types none, CRC32 and CRC64 are verified; SHA-256 and the reserved IDs
return `UnsupportedCheck`. Blocks must use the single filter LZMA2 (`0x21`);
delta, BCJ and other chains return `UnsupportedFilter`. Block header sizes
(compressed and uncompressed) are verified when present, as is the index:
its record count and an order-sensitive hash of every `(unpadded size,
uncompressed size)` pair must match the blocks. Concatenated streams and
stream padding (multiples of four zero bytes) are accepted; any other bytes
after a stream are `TrailingData`.

**LZMA2.** Dictionary resets, state resets and property changes are enforced
like liblzma: the first chunk resets the dictionary, an LZMA chunk after a
dictionary reset must set new properties, `lc + lp <= 4`, and each LZMA chunk
must consume exactly its packed size and leave the range coder at zero. A
match may not cross the chunk's unpacked size, read before the start of the
dictionary or exceed the window.

**`.lzma`.** The 13-byte header (properties, little-endian dictionary size,
little-endian uncompressed size or `-1`) is followed by one LZMA1 stream.
With an unknown size the end-of-payload marker is required; with a known
size the stream may stop flushed at that size or carry the marker there (as
liblzma accepts). Decoding keeps 20 bytes of lookahead unless the input is
final. Nothing may follow.

## Encoder

`Encoder` writes one xz stream: stream header, one block (LZMA2, CRC64
check, `lc=3 lp=0 pb=2`), index and footer. Input is copied into a window of
twice the dictionary; chunks are encoded only when the window is full or the
input is final, so **the output bytes do not depend on how input and output
are split across calls** (the oracle checks this). After a full window, the
oldest bytes beyond one dictionary are dropped and the hash heads and chains
are rebased.

| Level | Dictionary | Match finder | Memory (window + workspace) |
| --- | --- | --- | ---: |
| 0 | 256 KiB | 3-byte hash chains, depth 4, nice 32, greedy | 2.8 MiB |
| 1 | 1 MiB | depth 8, nice 64, one-step lazy | 10.3 MiB |
| 2 | 2 MiB | depth 16, nice 128, one-step lazy | 20.3 MiB |
| 3 | 4 MiB | depth 48, nice 192, one-step lazy | 40.3 MiB |

At every position the four repeat distances are tried first; a repeat wins
when it is within one byte of the hash-chain match (two or three bytes for
far matches), a length-3 match must be nearer than 4 KiB, and a literal whose
byte equals the rep0 byte becomes a short rep. Each LZMA2 chunk stops before
2 MiB unpacked or 64 KiB packed; a chunk that does not shrink is written
stored instead, and the next LZMA chunk resets state (and properties after a
stored first chunk), as liblzma requires. A single block means the index
records one block and the stream cannot be decoded in parallel.

## xz-bytes

[`sample_programs/library/xz_bytes.lani`](../sample_programs/library/xz_bytes.lani)
decodes stdin to stdout:

```text
xz-bytes [xz|lzma] [IN] [OUT]     decode; offer at most IN input / OUT output bytes per step
xz-bytes eN [IN] [OUT]            encode stdin to xz at level N (0..3)
xz-bytes batch                    many streams as (u8 format, u32 IN, u32 OUT, u32 length, bytes)
                                  records (format 0 xz, 1 lzma, 16+N encode at level N); each
                                  answered with (u8 status, u32 length, bytes)
```

Exit status 0 success, 2 usage, 3 I/O, 4 allocation, 10 + the `Error` ordinal
for a decoder error. The [`tgz` tool](extended-pax.md#tgz) uses the decoder
for xz archives and the level-2 encoder for `-cJ`.

## Performance

**Encoder against `xz -1`** on the docs/stdlib corpus: a tar of `docs/` and
`stdlib/` (18,145,280 bytes, of which 4.8 MB are already-compressed PDFs), and
the same tar without PDFs and PNGs (13,281,280 bytes of Markdown and Lanius).
Wall time on the target laptop under a load average of about 18 (other
agents compiling), so times are approximate; every output passed `xz -t` and
decoded back identically.

| Encoder | corpus bytes | ratio | time | text-only bytes | ratio | time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `xz -1` (xz 5.4.6) | 7,561,504 | 41.7% | 2.3 s | 2,918,488 | 22.0% | 1.1 s |
| level 0 | 8,054,424 | 44.4% | 8.0 s | 3,410,872 | 25.7% | 3.6 s |
| level 1 | 7,743,540 | 42.7% | ~19 s | 3,102,364 | 23.4% | 4.2 s |
| level 2 (tgz `-J`) | 7,562,060 | 41.7% | 18.3 s | 2,979,396 | 22.4% | 5.5 s |
| level 3 | 7,425,744 | 40.9% | 27.7 s | 2,836,728 | 21.4% | 8.5 s |

Level 2 matches `xz -1` on the corpus (+556 bytes) and is 2% larger on text;
level 3 is 1.8% / 2.8% smaller than `xz -1`. Speed is the gap: 1.6 to 3.7
MB/s on text across levels and about 1 MB/s on incompressible data (each chunk is encoded
before it falls back to stored), roughly 4 to 8 times slower than `xz -1`.
Profiling is not available here; inlining the plain-literal bit loop gained
about 20% on random data, which points at per-call overhead in the generated
code.

**Decoder.** Measured with the `lcc` build on the target laptop: 1 MB of text compressed by
`xz -6` decodes in 0.12 s (CRC64; 0.08 s without a check), 4 MB of zeros in
0.18 s, and 20 MB of stored chunks in 1.1 s, with 2 MB peak RSS. The
existing gzip inflater takes 0.44 s for the same 1 MB text. GNU xz is far
faster (under 10 ms); the decoder spends its time in per-bit range-coder calls.

## Oracle evidence

[`tests/fixtures/extended/xz_oracle.py`](../tests/fixtures/extended/xz_oracle.py)
compares `xz-bytes` with Python 3.12's `lzma` (liblzma 5.4.6) and the xz 5.4.6
CLI, with one fixed seed. Valid streams must decode to the exact input under
every listed step size; corrupt streams must be rejected exactly when a
strict Python decode rejects them, with identical output when both accept. It
is registered (with `--quick`) in `tests/extended_tgz_execution.rs`; the cargo
wrapper was not run. On 2026-10-31 the full oracle ran directly against an
`lcc` executable and passed with **23,475 agreeing cases and 0 failures in
160 s** (load average about 18), decoding 315.3 MB.

| Group | Cases |
| --- | ---: |
| Python xz, 17 inputs (empty to 2.6 MB; text, random, runs, far repeats, mixed) × presets 0/1/6/9/6e × checks none/CRC32/CRC64, step sizes down to 1-byte input and output | 891 |
| Python xz with custom LZMA2 filters: 6 `lc/lp/pb` combinations × 3 dictionary/mode/match-finder settings | 468 |
| Python `.lzma`, presets 0/6/9; custom LZMA1 filters | 171 / 468 |
| `.lzma` with the size recorded in the header plus the end marker; known size without a marker | 78 / 12 |
| xz CLI: `-0`, `-6e --check=crc32`, `-T2 --block-size` (sizes in block headers), `--block-list`, custom `lzma2=` options, `--format=lzma` | 180 |
| Concatenated streams with 0/4/8 bytes of padding accepted; misaligned padding rejected | 48 / 48 |
| Truncations (every length for streams up to 120 bytes) rejected / still valid | 9,702 / 4 |
| Bit flips rejected / still valid with identical output (no-check streams) | 9,853 / 509 |
| Appended bytes rejected / valid (padding, another stream) | 333 / 142 |
| Error classes for crafted cases (magic, cut header, check, footer, trailing, SHA-256) | 6 |
| Encoder, 23 inputs (the decoder's sets plus 3 MB of runs, random-then-text, window-edge sizes, 2.4 MB of zeros across level-0 window slides) × levels 0-3: output identical under every step size (down to 1-byte input and output) | 228 |
| Encoder outputs that strict Python `lzma` decodes exactly / `xz -t` accepts / `xz-bytes` decodes exactly | 92 / 92 / 116 |
| Delta and x86 BCJ filter chains: `UnsupportedFilter` (expected) | 32 |
| SHA-256 checks: `UnsupportedCheck` (expected) | 17 |

Rejections by class: Truncated 11,169, Corrupt 2,663, Header 2,611, Footer
1,416, Index 988, Checksum 754, TrailingData 326, Options 50, SizeMismatch 3.
On the generated sets (18.4 MB, mostly random or synthetic) the encoder
produced 4,828,420 / 4,678,048 / 4,623,592 / 4,602,204 bytes at levels 0-3
against 4,677,172 for `xz -1`.
Python's `lzma.decompress` ignores trailing garbage after a stream; 349 of the
rejected cases are of that kind, and the strict reference (and `xz -d`)
rejects them too.

Remaining: an optimal-parse (price-based) encoder and higher levels,
multi-block output for parallel decoding, encoder speed, SHA-256 checks,
BCJ/delta filters, and a faster range decoder.
