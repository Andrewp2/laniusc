# RIFF/WAVE codec

`ext::wave` implements little-endian RIFF/WAVE parsing and encoding in Lanius. `inspect(bytes,limits)` returns borrowed `Info`; `decode(bytes,limits)` returns an owned `ext::audio::Buffer`; `encode(audio_view,format,limits)` returns an owned `alloc::vec::Vec<u8>`. Destroy returned owners explicitly. Keep input bytes alive while any `Info.data` view exists.

```lani
let limits: ext::wave::Limits = ext::wave::default_limits();
let info: ext::wave::Info = ext::wave::inspect(input,limits).unwrap();
let audio: ext::audio::Buffer = ext::wave::decode(input,limits).unwrap();
let encoded = ext::wave::encode(audio.as_view(),ext::wave::Format::Pcm16,limits).unwrap();
// Consume encoded.as_view() before destroying it.
encoded.destroy(); audio.destroy();
```

Supported sample formats are unsigned PCM8, signed little-endian PCM16/24/32 and IEEE binary32/binary64, represented by `Format::{Pcm8,Pcm16,Pcm24,Pcm32,Float32,Float64}`. Decode supports ordinary format tags 1/3 and extensible tag 65534 with the canonical PCM or IEEE float subtype GUID. Extensible valid-bit counts 1 through container width are supported for PCM: valid bits are left aligned, and nonzero unused low bits are rejected. Floating valid bits must equal container width. `Info` exposes `valid_bits`, raw `channel_mask`, and `extensible`, together with rate/channels/frames/format/data. Channel-mask bits are preserved as metadata without inventing a speaker assignment or requiring their population count to equal channels.

Encoding emits a canonical ordinary PCM `fmt ` chunk of 16 bytes or an IEEE `fmt ` chunk of 18 bytes with cbSize zero and a `fact` chunk. Encoded samples retain channel order. Encoding does not retain extensible valid-bit/channel-mask declarations, ancillary chunks or original header layout; the decoded signal is retained at the requested format's precision. Applications needing speaker metadata must keep `Info` alongside the audio buffer. A multichannel ordinary output declares channel order without a speaker mask.

Validation checks:

- Valid signed view extents and nonnegative caller limits; callers guarantee the physical backing and lifetime.
- Exact RIFF declared size, `RIFF`/`WAVE` identifiers, complete chunk headers/payloads and required odd-size padding bytes. Pad values are accepted; encoding writes zero.
- Exactly one `fmt ` and one `data` chunk, with format before data. Unknown chunks before/after data are skipped by their declared lengths. Multiple data chunks, `wavl` sample lists, RF64 and big-endian RIFX are outside this API.
- Minimum format size, channel/rate nonzero, supported container widths, exact block alignment, byte rate fitting u32 and equal to rate*alignment, and data length divisible by frame size.
- Extensible cbSize at least 22 and contained in the fmt payload, canonical subtype GUID, and valid-bit range/alignment. Extra PCM fmt fields are ignored as specified; one-byte malformed fmt extensions are rejected. Ordinary IEEE extensions with nonzero cbSize are unsupported.
- A present `fact` chunk must have at least four bytes and its frame count must match data. Duplicate fact chunks are rejected. For interoperability, a missing float fact chunk is accepted; the encoder always emits it.
- Decoded sample count and encoded byte count within limits. Nonfinite float samples and finite binary64 values that overflow when narrowed to binary32 are rejected before allocation.

`inspect` checks structure and metadata; it does not inspect sample payload values. `decode` scans floating finiteness and PCM unused bits before allocating decoded storage. NaN/Inf payloads therefore return `NonFinite`. IEEE finite values, including signed zeros/subnormals, decode without clamping; PCM conversion follows [the audio contract](extended-audio.md), including exact endpoint scaling, saturation and ties-even rounding. Float64 output preserves finite binary64 bits, and float32 output uses native nearest-even narrowing.

Default limits are 67108864 bytes and 8000000 samples. `max_bytes` bounds the complete input for inspect/decode and complete output for encode; `max_samples` bounds interleaved samples. All byte arithmetic is checked before narrowing to signed indices. Work is O(bytes + samples), decoded storage is O(samples), encoded storage O(bytes). Invalid input and allocation failure produce no owner, no partial mutation and no leaked allocation. Input and audio views can alias other borrowed views because output allocation is independent.

Errors: `InvalidView`, `Truncated`, `InvalidRiff`, `InvalidChunk`, `DuplicateChunk`, `MissingChunk`, `InvalidFormat`, `Unsupported`, `Limit`, `NonFinite`, `AllocationFailed`, `InvalidSample`. Unsupported means outside the stated codec scope, including compressed/unknown formats and unknown extensible subtypes. The codec supplies no playback or recording host service.

Sources of truth: IBM/Microsoft [Multimedia Programming Interface and Data Specifications 1.0](https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/Docs/riffmci.pdf), RIFF chunks pp. 10–11 and WAVE/PCM pp. 56–61; Microsoft [WAVEFORMATEX](https://learn.microsoft.com/en-us/windows/win32/api/mmreg/ns-mmreg-waveformatex) and [WAVEFORMATEXTENSIBLE](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ksmedia/ns-ksmedia-waveformatextensible). Arbitrary pad contents and optional missing float fact are deliberate reader tolerances; output follows the canonical declarations above.

Native evidence in `tests/extended_wave_execution.rs` uses an independent RIFF model and Python `wave`: 534 generated and malformed cases across all six formats, extensible validbits and masks, unknown odd chunks, truncations, header/format errors, nonfinite values, exact PCM endpoint conversions, exhaustive PCM8/16 and seeded PCM24/32 round-trips, byte/output limits, and a 400000-frame workload. Direct contract cases cover forged metadata, f32 narrowing overflow, f64 maximum endpoints and limit errors. No Rust/Python production codec is used.
