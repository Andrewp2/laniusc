# PNG images

`ext::png` decodes PNG image data into owned [`ext::image`](extended-image.md)
RGBA8 images and encodes RGBA8 views. Production code is entirely Lanius and
uses the existing [`ext::compression`](extended-compression.md) zlib codec.
No host image or compression library participates in production execution.
Executable evidence establishes GPU-compiled x86_64 Linux behavior.

## API and limits

```text
Limits { max_input: i32, max_pixels: i32, max_inflated: i32, max_chunks: i32 }
default_limits() -> Limits
decode(input: core::slice::View<u8>, limits: Limits) -> Result<Image, Error>
encode(source: ext::image::View, max_output: i32) -> Result<Vec<u8>, Error>
```

Defaults are 16 MiB input, 16,777,216 pixels, 128 MiB inflated scanline data,
and 65,536 chunks. `max_inflated` includes the filter byte on every nonempty
scanline, per-pass byte padding, and all Adam7 passes. It bounds decompressed
scanline storage, while `max_pixels` bounds the RGBA result independently.
An exact fit succeeds; negative limits return `Bounds`. The input limit covers
all supplied bytes, and the chunk limit includes IHDR, empty IDATs, ancillary
chunks, and IEND. RGBA storage and inflated counts must also fit `i32`.
The encoder's `max_output` includes the complete signature, chunks, compressed
stream, and checksums. The caller chooses image dimensions before encoding.

Successful decoding owns its pixels independently of the input. Successful
encoding owns its bytes independently of the image. Destroy one active result
owner when finished. All errors release internal owners and return no partial
image or PNG. The input and image view are borrowed, and their physical backing
and lifetime follow the image/slice view contracts.

## Decoding behavior

The decoder supports all standard static PNG color/depth combinations:

| Color type | Bit depths | RGBA8 conversion |
| --- | --- | --- |
| 0, grayscale | 1, 2, 4, 8, 16 | Gray replicated into RGB |
| 2, RGB | 8, 16 | RGB samples |
| 3, indexed | 1, 2, 4, 8 | PLTE RGB and optional palette alpha |
| 4, grayscale + alpha | 8, 16 | Gray replicated, explicit alpha |
| 6, RGBA | 8, 16 | Four explicit channels |

It supports no interlace and all seven Adam7 passes, including empty passes
in small images, scanline padding, all five filters, and filtering 16-bit
samples byte by byte. Consecutive IDAT chunks form one zlib stream; boundaries
may split any part of that stream, and IDAT chunks may be empty.

Sample conversion uses `floor((sample * 255 + maximum / 2) / maximum)`, where
`maximum = 2^depth - 1`. Thus 16-bit samples use nearest-value rescaling rather
than dropping their low byte. RGB and grayscale transparency compare original
samples before rescaling. For depths below 16, unused high bits in tRNS samples
are masked as required by [PNG 3 section 11.3.1.1](https://www.w3.org/TR/png-3/#11tRNS).
Palette entries not listed in tRNS are opaque; out-of-range palette indexes
are errors. Transparent pixels retain their RGB sample values.

The codec returns stored sample values. It ignores ancillary color metadata,
including gamma, ICC, sRGB, significant-bit, and HDR metadata; no color space
conversion, display rendering, background composition, or orientation transform
is applied. It does not retain metadata on re-encoding. For APNG input, it
decodes the default PNG image in IDAT and ignores animation chunks; it does not
return frames or apply animation disposal/blending.

## Validation and failure

Before allocating IDAT or pixel storage, the parser validates the signature,
chunk bounds, chunk type letters, every chunk CRC (including
ignored ancillary chunks), dimensions, color/depth/method values, supported
chunk ordering, and resource limits. IHDR is first and unique; PLTE is unique
and precedes IDAT and tRNS; tRNS is unique and precedes IDAT; IDAT chunks are
consecutive; IEND is empty and last. Indexed input requires a valid palette.
Unknown critical chunks are rejected. A set reserved bit in the third chunk
letter makes the chunk unknown: ancillary types are skipped and critical types
are rejected, following the decoder rule in PNG section 13.5.
Ignored ancillary chunks are not parsed
or decompressed, and their private ordering/semantics are not validated.

The zlib codec checks its method, window, dictionary flag, DEFLATE stream, and
Adler-32. The inflated length must exactly match the expected scanlines. Invalid
filter bytes are rejected, and bytes following IEND are rejected. As allowed
by [PNG section 11.2.3](https://www.w3.org/TR/png-3/#11IDAT), unused compressed
input after the validated zlib trailer inside IDAT is ignored. The normal
decode uses the existing whole-buffer zlib API. If that API reports trailing
data after successful checksum validation, the decoder replays the validated
DEFLATE stream into an exact buffer and ignores only the trailing input.

Errors are `Bounds`, `InputLimit`, `PixelLimit`, `InflatedLimit`, `ChunkLimit`,
`OutputLimit`, `AllocationFailed`, `SizeOverflow`, `Signature`, `Truncated`,
`ChunkType`, `ChunkOrder`, `Crc`, `Header`, `Palette`, `Transparency`,
`UnknownCritical`, `DataSize`, `Filter`, `TrailingData`, or
`Compression(ext::compression::Error)`. Compression allocation errors are
promoted to `AllocationFailed`. An inflated stream exceeding the exact expected
length is `DataSize`, even if the caller's inflated limit is larger.

## Encoding and resource costs

Encoding writes a deterministic noninterlaced color-type-6, depth-8 PNG with
IHDR, one IDAT, and IEND. It uses filter None for each row and the existing
zlib encoder's fixed/stored DEFLATE size policy. It preserves all four bytes
of every pixel, including transparent RGB. It accepts padded image rows and
selected byte views and emits no padding or metadata.

These are whole-buffer APIs. Parsing and CRC work are linear in supplied
input, even for ignored ancillary chunks. Decoding holds collected IDAT,
inflated scanlines, and RGBA output during reconstruction; compression growth
can temporarily hold old and new buffers and replay prefixes. Encoding holds
filtered scanlines, the compression encoder's scratch storage, compressed
bytes, and the final PNG at different phases. Limits bound counts rather than
the aggregate peak live memory. Allocation can fail at any of these phases;
all owned intermediate storage is released.

## Sources and verification

The implementation follows the [PNG 3 specification](https://www.w3.org/TR/png-3/),
especially sections 5 (chunks/CRC/order), 7–10 (serialization, Adam7, filters,
zlib), 11 (IHDR/PLTE/tRNS/IDAT/IEND), and 13.12 (sample rescaling).
[LodePNG](https://github.com/lvandeve/lodepng/blob/master/lodepng.cpp) was
consulted as a mature reference for pass layout, scanline filtering, and
palette/transparency handling; the implementation is written for Lanius APIs.

`tests/extended_png_execution.rs` checks a 600-case independent Python generator
matrix covering every standard color/depth combination, every filter, both
interlace methods, odd rows, and tiny dimensions with empty Adam7 passes.
Pillow independently decodes encoded outputs, including deterministic random
RGBA images up to 511 × 511. Other cases exercise split/empty IDATs, tRNS high
bits, precise 16-bit scaling, malformed chunks/checksums/order/filters/sizes,
truncations, input/pixel/inflated/chunk/output limits, native byte strides and
offset views. `strace` denies each observed allocation in encode, decode, and
late failures and verifies cleanup and absence of partial output. Python and
Pillow are test oracles only.
