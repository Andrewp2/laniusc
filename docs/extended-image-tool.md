# PNG inspection and transformation

`sample_programs/library/image_tool.lani` reads PNG from stdin. It uses
`ext::cli`, native streams, bounded owned input, `ext::png`, `ext::image` and
checked formatting. Production behavior is Lanius.

The [resize increment](extended-image-resize.md) adds the options and ordering
described below. All four new application groups pass 102 native cases on
Linux x86_64 CPU output from the GPU compiler. Standalone compilation and both
documented resize examples also pass. The
earlier 400-invocation receipt at the end of this guide covers the original
crop/rotate/flip application, not the new resize behavior.

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/image_tool.lani -o target/stdlib-work/image-tool
target/stdlib-work/image-tool info <input.png
target/stdlib-work/image-tool transform --crop 10,20,100,80 --rotate 90 --flip-x \
  --resize 40,50 --filter area \
  <input.png >output.png
target/stdlib-work/image-tool transform --resize 256,256 --filter nearest \
  <input.png >enlarged.png
```

`info` completely decodes and validates the input, then emits two CSV lines:
`width,height` and the decimal dimensions. It does not merely inspect an IHDR.
`transform` always decodes and re-encodes, even without transformation options.

## Transform order

The resize contract makes the fixed order crop, clockwise rotation, horizontal
flip, vertical flip, resize.
Option order does not change it. A crop is exactly four comma-separated
nonnegative decimal integers `X,Y,WIDTH,HEIGHT`, with positive width/height and
a rectangle contained in the decoded image. Rotation is 0, 90, 180 or 270
degrees. Repeated valued options use the last value; repeated flip flags still
apply that flip once. Transform options are invalid in `info` mode.

`--resize WIDTH,HEIGHT` requires exactly two positive ASCII decimal dimensions
fitting i32; leading zeros are allowed. `--filter nearest|bilinear|area` selects
the resize filter; Area is the default. A filter without resize is an argument error. Repeated resize and
filter options use their last valid values; every occurrence must parse, so a
later valid value does not erase an earlier argument error. These checks and
`info` transform-option rejection precede help output and input reads.
Requested dimensions name the final output axes, after rotation and flips. The
[resize guide](extended-image-resize.md#exact-sampling) specifies exact filter,
alpha and identity behavior.

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
fit `i32`, as must positive resize dimensions. Option parsing rejects overflow
rather than truncating.

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

`--max-pixels` limits decoded input and resized output independently. The
requested output check occurs after complete PNG validation and earlier
transforms, before allocating the replacement raster. An invalid input therefore
does not become a resize-limit error merely because the requested output is
large. A resized-output excess selects status 3 with
`image-tool: resource-limit stage=transform` followed by a newline; a diagnostic
write failure overrides that status with 5. This ceiling does not add a new
library work-quota parameter.

## Failure and ownership

Exit 0 means success; 2 means invalid arguments, PNG data or transformation;
3 means a resource/size limit; 4 means allocation failure; 5 means host I/O
failure, including failure to write a diagnostic. Error diagnostics identify
the stage: arguments, input, decode, transform, encode or output.

The entire input is read before decoding. A decoded image owns independent
pixels, so the input buffer is released before transformation. Every crop or
rotation or resize releases the replaced raster. A resize failure releases the
current raster, and the resize routine retires its own partial output/scratch.
All owners are released on error.

No stdout is written until the complete report or PNG is ready. Malformed
input, late filter errors, invalid crops, limits and allocation failures leave
stdout empty. A stdout write failure can leave a prefix already transferred;
the program then reports I/O failure. stdin EOF, short transfers and interrupted
reads/writes follow the standard stream contracts.

## Execution evidence

The new resize pixel group passes 24 native cases against the shared rational
reference: one test in 8.22 seconds, with a separate 1.78-second Rust build,
in `target/stdlib-work/image-resize-tool-pixels.log`. Application source remains
`5e7138e5...`. A trace-ledger authoring correction around the start of that run
allows reuse of the already retired input mapping's virtual address; pixel
expectations did not change and no extra native cases are counted. The remaining
three groups pass together in 10.68 seconds, with a separate 0.18-second Rust
build, in `target/stdlib-work/image-resize-tool-remaining.log`. This is a combined
command time, not three individual timings.

| New group | Native cases | Accepted scope |
| --- | ---: | --- |
| Pixel comparisons | 24 | All filters, default Area, identities, mixed axes and complete crop/rotate/flip/resize ordering, including palette-alpha input |
| CLI | 34 | Dimensions/filter syntax, dependencies, info/help, leading zeros, attached and repeated values |
| Limits | 10 | Input/output pixel caps, staged PNG byte caps, earlier transform errors and complete PNG-validation precedence |
| Faults | 34 | One baseline, 22 reached application allocation denials and 11 I/O/diagnostic cases |

The total is 102 native application cases; the baseline is counted once. The
allocation sweep includes both resize result and Area workspace. Its 22
denials are separate from direct library allocation-failure tests. Complete
PNG pixels, dimensions, chunk extents/CRCs and final IEND are checked; compressed
bytes need not match another encoder.

The [fixture record](../tests/fixtures/extended_image_resize_tool/README.md)
specifies its eight observed syscalls and exact mapping-release checks. This
scope is separate from the direct library tests' complete host-effect traces.
Successful publication starts with only staged output and argv observed owners
remaining; diagnostics follow observed owner cleanup. Each application case is
a fresh process, so this evidence does not claim same-process application
retry. It adds no new write-attempt bound or SIGPIPE policy.

Standalone CLI compilation passes with exit 0 and an empty success log in
`target/stdlib-work/image-resize-cli-build.log`. The artifact is
`target/stdlib-work/image-tool-resize`; the commands above use the guide's
`image-tool` output name. Both documented resize examples execute successfully
on a generated 128-by-128 PNG, with strict PNG decoding and complete RGBA
comparison through the accepted shared rational oracle `75677871...`. Each
returns 0 with empty stderr. Log:
`target/stdlib-work/image-resize-cli-examples.log`.

| Example | Output dimensions | Complete RGBA bytes | PNG bytes |
| --- | --- | ---: | ---: |
| Crop, rotation, flip and Area resize | 40 × 50 | 8,000 | 8,118 |
| Nearest enlargement | 256 × 256 | 262,144 | 146,032 |

These two standalone runs are separate from the 102 application cases.

Three selected preexisting groups pass on application source `5e7138e5...` with image source `daad5347...`:
209 discrete pixel comparisons, 109 CLI/capacity cases and 28 late PNG failures,
for 346 native process cases. The combined command passes three tests in
10.51 seconds, with a separate 1.71-second Rust build, in
`target/stdlib-work/image-resize-existing-tool.log`. This reruns three selected
groups, not all six groups of the historical 400-case campaign below. Those
cases do not establish new resizing behavior.

The following historical receipt retains its original behavior scope.

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
