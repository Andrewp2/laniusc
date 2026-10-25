# PNG inspection and transformation

`sample_programs/library/image_tool.lani` reads PNG from stdin. It uses
`ext::cli`, native streams, bounded owned input, `ext::png`, `ext::image` and
checked formatting. Production behavior is Lanius.

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/image_tool.lani -o target/stdlib-work/image-tool
target/stdlib-work/image-tool info <input.png
target/stdlib-work/image-tool transform --crop 10,20,100,80 --rotate 90 --flip-x \
  <input.png >output.png
```

`info` completely decodes and validates the input, then emits two CSV lines:
`width,height` and the decimal dimensions. It does not merely inspect an IHDR.
`transform` always decodes and re-encodes, even without transformation options.

## Transform order

The fixed order is crop, clockwise rotation, horizontal flip, vertical flip.
Option order does not change it. A crop is exactly four comma-separated
nonnegative decimal integers `X,Y,WIDTH,HEIGHT`, with positive width/height and
a rectangle contained in the decoded image. Rotation is 0, 90, 180 or 270
degrees. Repeated valued options use the last value; repeated flip flags still
apply that flip once. Transform options are invalid in `info` mode.

The [PNG decoder](extended-png.md) accepts every standard color/depth
combination and Adam7, validates CRCs, chunk order and decompressed size, and
produces straight RGBA8. Sixteen-bit samples use the documented nearest
rescaling after original-sample transparency comparison. Output is canonical
RGBA8 PNG. Ancillary metadata, color profiles and animation are not preserved;
no implicit color management occurs. Pixel operation contracts are in the
[image guide](extended-image.md).

## Limits

All numeric options require ASCII decimal digits without signs or whitespace.
Zero is valid for a resource ceiling and is enforced by the corresponding
operation. A positive input may then exceed that ceiling. Crop components must
fit `i32`. Option parsing rejects overflow rather than truncating.

| Option | Default | Maximum |
| --- | ---: | ---: |
| `--max-input-bytes` | 16,777,216 | 268,435,456 |
| `--max-pixels` | 16,777,216 | 67,108,864 |
| `--max-inflated-bytes` | 268,435,456 | 1,073,741,824 |
| `--max-chunks` | 65,536 | 1,000,000 |
| `--max-output-bytes` | 67,108,864 | 268,435,456 |

The inflated ceiling includes filter bytes and all Adam7 passes. The output
ceiling also applies to the complete `info` report. `--help` emits usage without
reading stdin and is independent of data output limits. Argument snapshots are
limited to 32 tokens and 8,192 bytes, excluding the executable name.

## Failure and ownership

Exit 0 means success; 2 means invalid arguments, PNG data or transformation;
3 means a resource/size limit; 4 means allocation failure; 5 means host I/O
failure, including failure to write a diagnostic. Error diagnostics identify
the stage: arguments, input, decode, transform, encode or output.

The entire input is read before decoding. A decoded image owns independent
pixels, so the input buffer is released before transformation. Every crop or
rotation releases the replaced raster. All owners are released on error.

No stdout is written until the complete report or PNG is ready. Malformed
input, late filter errors, invalid crops, limits and allocation failures leave
stdout empty. A stdout write failure can leave a prefix already transferred;
the program then reports I/O failure. stdin EOF, short transfers and interrupted
reads/writes follow the standard stream contracts.

## Execution evidence

`tests/extended_image_tool_execution.rs` compiles the real application and
runs 400 native invocations: 209 Pillow pixel/order comparisons, 109 argument
and capacity cases, 28 malformed/late-error cases, three scale cases, 38
individual allocation denials, three traced allocation baselines and ten I/O
scenarios. Allocation traces check exact mapping release. Tests include PNG
binary data, transposed dimensions, every quarter turn, out-of-range crops,
input/output limits, zero/short writes, EINTR/EIO, failed stderr and `/dev/full`.

The scale inputs include 1023×769 (786,687 pixels), 4097×1 and 1×4097.
One sequential observation took 3.765 seconds across the native scale runs,
excluding compilation and reference generation; it includes process setup and
I/O. This is neither an optimized-codec comparison nor a user GPU measurement.
Verified execution is x86_64 Linux output from GPU compilation. Other targets
and user GPU kernels have not been verified.
