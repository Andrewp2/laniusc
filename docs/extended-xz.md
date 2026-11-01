# xz and .lzma decoding

`ext::xz` decodes xz streams (LZMA2) and legacy `.lzma` files (LZMA1 "alone"
format) incrementally, and writes valid xz streams made of stored LZMA2
chunks. It is pure Lanius over caller-owned `core::slice::View` storage: it
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

## xz-bytes

[`sample_programs/library/xz_bytes.lani`](../sample_programs/library/xz_bytes.lani)
decodes stdin to stdout:

```text
xz-bytes [xz|lzma] [IN] [OUT]     offer at most IN input / OUT output bytes per step
xz-bytes batch                    many streams as (u8 format, u32 IN, u32 OUT, u32 length, bytes)
                                  records; each answered with (u8 status, u32 length, bytes)
```

Exit status 0 success, 2 usage, 3 I/O, 4 allocation, 10 + the `Error` ordinal
for a decoder error. The [`tgz` tool](extended-pax.md#tgz) uses the decoder
for xz archives and the stored writer for `-cJ`.

## Performance

Measured with the `lcc` build on the target laptop: 1 MB of text compressed by
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
`lcc` executable and passed with **22,913 agreeing cases and 0 failures in
89 s**, decoding 241.6 MB.

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
| Delta and x86 BCJ filter chains: `UnsupportedFilter` (expected) | 32 |
| SHA-256 checks: `UnsupportedCheck` (expected) | 17 |

Rejections by class: Truncated 11,161, Corrupt 2,620, Header 2,610, Footer
1,416, Index 987, Checksum 762, TrailingData 326, Options 51, SizeMismatch 3.
Python's `lzma.decompress` ignores trailing garbage after a stream; 349 of the
rejected cases are of that kind, and the strict reference (and `xz -d`)
rejects them too.

Remaining: an LZMA/LZMA2 encoder (the writer stores chunks uncompressed),
SHA-256 checks, BCJ/delta filters, and a faster range decoder.
