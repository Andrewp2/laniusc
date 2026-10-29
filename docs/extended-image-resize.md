# RGBA8 image resizing

The [resize increment](library-image-resize-plan.md) extends `ext::image` with
three filters and adds resizing to the existing [PNG tool](extended-image-tool.md).
All seven library groups and four application groups/102 native cases pass on
Linux x86_64 CPU output from the GPU compiler. Selected existing regressions,
standalone compilation and both documented examples also pass. Earlier image
and PNG-tool receipts retain their original operation scope. The full library
goal remains open.

## API and ownership

```text
Filter { Nearest, Bilinear, Area }
resize(source: View, width: i32, height: i32, filter: Filter)
    -> Result<Image, Error>
```

The result owns an independent packed straight-alpha RGBA8 raster. The source
is borrowed and unchanged on success and failure. Keep its physical backing
alive and immutable throughout the call. Source descriptors may select a
subview, retain logical row padding, or use positive or negative physical byte
strides. Their complete logical range must satisfy the existing
[image-view contract](extended-image.md#ownership-and-view-contract).

An `Image` copy aliases its allocation and does not create another cleanup
authority. Keep one active result owner and call `destroy()` once. Resizing does
not destroy the source or retain a source view after returning. It returns no
partial image on failure. Physical extent, valid backing and manual lifetimes
remain caller obligations; descriptor validation cannot prove them.

## Admission and failures

Checks have this precedence:

1. Validate the complete source descriptor; invalid metadata returns `Bounds`.
2. Validate positive destination dimensions, then their checked packed byte
   extent; failures return `Dimensions` or `SizeOverflow` respectively.
3. Allocate the result, then Area workspace when needed. Failure returns
   `AllocationFailed` and releases every partial allocation.
4. Sample source pixels and fill the result only after admission and allocation
   have completed. Release private workspace before returning the image.

Both source and destination use the existing positive-dimension, i32 byte-count
profile. Destination `width * height * 4` must fit i32, with checks before
multiplication. Identity, Nearest and Bilinear require only the result
allocation. Nonidentity Area also allocates at most 512 private sums, each
containing four u64 values: at most 16,384 requested scratch bytes. There is no
new host service, user callback or work-quota parameter.

## Exact sampling

Let `s` be one source-axis length, `t` its destination length and `d` a
destination coordinate in `[0,t)`. The corresponding center is
`q = (d + 1/2) * s/t - 1/2`.

| Filter | Source contribution |
| --- | --- |
| `Nearest` | Select `floor((d + 1/2) * s/t)` on each axis. Exact halfway ties choose the higher source index. Copy all four bytes, including RGB under zero alpha. |
| `Bilinear` | Clamp `q` to `[0,s-1]`, then combine neighboring samples with the exact tensor product of the two linear weights. Support is a fixed 2-by-2 neighborhood; this filter does not add antialiasing support for reduction. |
| `Area` | Integrate piecewise constant source pixels over each footprint `[d*s/t,(d+1)*s/t]`. Each source pixel contributes its exact overlap area. This applies to reduction, enlargement and mixed-axis changes. |

The Area footprints partition the complete source rectangle. All filtered
arithmetic operates on stored sample values; it does not perform gamma
correction, assign a color space or convert color profiles.

### Alpha and rounding

For positive integer sample weights `w`, calculate exact sums:

```text
D = sum(w)
A = sum(w * alpha)
C = sum(w * alpha * channel)  // separately for red, green and blue

output_alpha = floor((A + floor(D/2)) / D)
output_channel = floor((C + floor(A/2)) / A)  // when A > 0
```

When exact `A` is zero, the filtered output is transparent black. When `A` is
positive, calculate its colors even if the rounded output alpha is zero.
There is no intermediate premultiplication rounding or row quantization.
Nonnegative exact halfway results round upward.

**Identity is explicit:** when both dimensions are unchanged, every filter
returns a byte-preserving independent copy before filtered accumulation.
Hidden RGB under zero alpha therefore survives identity resizing. It also
survives every Nearest selection. Other filtered pixels follow the exact-alpha
rule above.

## Work and storage bounds

Let `S = sw*sh` and `D = dw*dh` be source and destination pixel counts. Nearest
and Bilinear take O(D) work with constant scratch beyond the output owner.
Bilinear axis weights have denominators `2*destination_length`, so their total
integer weight is `4*dw*dh`, below 2^31 under the image byte bound. Area uses
integer overlap lengths between `[d*s,(d+1)*s]` and `[i*t,(i+1)*t]`; the total
weight is `sw*sh`, below 2^29. Coordinate products fit signed 64 bits, and
weighted alpha/color sums fit unsigned 64 bits. Operands are widened before
products; these bounds do not rely on integer wrapping.

Area uses two exact separable passes. A cached source-projection row and an
output-accumulator row preserve unrounded alpha and color-times-alpha sums.
The inner output axis is processed in tiles of at most 256 pixels. Each tile
projects only its touched source intervals; monotone outer footprints reuse
their shared boundary row. There is no full intermediate raster.

Choose orientation using the exact one-dimensional overlap counts:

```text
Ix = sw + dw - gcd(sw, dw)
Iy = sh + dh - gcd(sh, dh)
horizontal_first = sh * Ix + dw * Iy
vertical_first   = sw * Iy + dh * Ix
```

Use the smaller expression, breaking ties by the shorter inner output
dimension. The selected work is O(S+D), including `N*1 -> 1*N` and the
transposed shape. The bound is an algorithmic contract; it is not a measured
throughput claim. The finite native scale observations are recorded below.

## PNG consumer

The new `image_tool transform` options are `--resize WIDTH,HEIGHT` and
`--filter nearest|bilinear|area`, with Area as the default. A filter without
resize is invalid. The final order is crop, clockwise rotation, horizontal
flip, vertical flip, resize. Width and height describe the final output axes.
The existing pixel ceiling applies to both decoded input and requested output;
the output check occurs after complete PNG validation and earlier transforms,
before replacement allocation. The [application guide](extended-image-tool.md)
records syntax, stage-specific errors, staging and cleanup.

## Evidence and target scope

All seven new library groups pass on frozen `ext::image` source
`daad5347ea7d2aab2d7dc0abb99847b107538b0140cfac3bb56f2e33e18ce80a`.
They comprise four direct groups, one independent-model group and two
resource/scale groups. Independent source review also passes and adds no native
cases. The four application groups and selected existing regressions below
have separate counts.

### Direct contracts and independent model

The tiny admission executes all three filters on a 2-by-1 to 1-by-1 resize,
checks exact pixels and complete source guards, and releases four matched
allocations: three results and Area scratch. It passes one test in 6.18 seconds,
with a separate 1.95-second Rust build, in
`target/stdlib-work/image-resize-admission.log`.

The remaining three direct groups pass in 8.54 seconds, with a separate
1.71-second Rust build, in `target/stdlib-work/image-resize-direct.log`. They
cover twenty literal sample cases, padded/cropped actual positive and negative
byte strides, identity/owner independence, complete source guards and metadata
error precedence. The groups release 28 and 14 exact allocation lifetimes;
preflight performs zero allocations. All four groups pass complete host-effect
trace checks across the two runs. The
[direct fixture record](../tests/fixtures/extended_image_resize/README.md)
separates native receipts from host-only authoring calculations.

The independent rational model passes 626 native cases: 590 successful resizes
and 36 rejections, with 180 Nearest, 202 Bilinear and 208 Area results. It checks
403,513 output pixels and 84 complete transpose/reflection relations across two
layouts. The 40 identity and 386 cropped-input cases overlap the filter counts;
Nearest reflection is deliberately not asserted where its tie policy differs.
Seed is `0x1a6e0261113`. One test passes in 7.88 seconds, with a separate
1.64-second Rust build, in `target/stdlib-work/image-resize-model.log`. The
[model record](../tests/fixtures/extended_image_resize_model/README.md) keeps
21 host-only corruption controls separate from these native cases.

### Resources and scale

The two resource groups pass with the strengthened driver in 7.74 seconds,
with a separate 1.87-second Rust build, in
`target/stdlib-work/image-resize-resources-final.log`.

Six owner/filter baseline cycles release all thirteen exact allocations.
The two reached Area allocation denials target result reservation at mmap 2
and scratch reservation at mmap 3. They preserve complete source pixels,
padding and guards, release partial output before returning an error, and
recover in the same process. Their successful allocations/releases total three
and four respectively. Result-only Nearest, Bilinear and identity paths
allocate no scratch. The full syscall ledger requires source retirement before
publication, only the result owner live at each output write, and exact cleanup
before the completion marker; process exit is not used as cleanup evidence.

Five Area scale cases compare all 1,321,000 output bytes and preserve every
source byte, with fifteen exact allocations and releases:

| Source | Result | Scratch |
| --- | --- | ---: |
| 1024 × 768 | 512 × 384 | 16,384 bytes |
| 517 × 3 | 257 × 5 | 16,384 bytes |
| 3 × 517 | 5 × 257 | 16,384 bytes |
| 65,536 × 1 | 1 × 65,536 | 64 bytes |
| 1 × 65,536 | 65,536 × 1 | 64 bytes |

The 257-pixel axes cross a tile boundary, and both thin directions exercise the
adaptive orientation. Together these cases contain 920,606 source pixels and
330,250 output pixels. Their native process takes 0.413954 seconds, separately
from 6.169641 seconds compiling the Lanius scale fixture. Native time includes
tracing, setup, preservation checks and publication; it is not isolated resize
throughput or a comparison with another compiler/library.

An earlier invocation of the same two selectors passed in 8.38 seconds with a
1.89-second Rust build. Review then strengthened publication lifetime checks;
the final run above exercises those assertions and two host-only negative
controls. The earlier run is history, not two more accepted group identities.
The [resource record](../tests/fixtures/extended_image_resize_resources/README.md)
contains exact source hashes, extents, native timings and trace scope.

### Consumer and existing regressions

All four new PNG-tool groups pass 102 native cases: 24 pixel comparisons, 34
CLI cases, ten limit cases and 34 fault cases, including 22 reached application
allocation denials. Those denials are separate from the two direct library
resource denials. The pixel group passes in 8.22 seconds with a separate
1.78-second Rust build, in `target/stdlib-work/image-resize-tool-pixels.log`.
The other three groups share a 10.68-second command with a separate 0.18-second
build, in `target/stdlib-work/image-resize-tool-remaining.log`.

Standalone CLI compilation passes with exit 0 and an empty success log in
`target/stdlib-work/image-resize-cli-build.log`. Both documented resize examples
pass strict PNG decoding and complete pixel comparison, exit 0 and empty stderr
in `target/stdlib-work/image-resize-cli-examples.log`: the 40-by-50 Area result
has 8,000 RGBA bytes and an 8,118-byte PNG; the 256-by-256 Nearest result has
262,144 RGBA bytes and a 146,032-byte PNG. These example runs are separate from
the 102 application cases. The
[application record](extended-image-tool.md#execution-evidence) separates its
eight-syscall observation and trace-ledger authoring correction from the direct
library traces and pixel expectations.

Two preexisting image groups pass on the same image source in 7.44 seconds,
with a separate 1.90-second Rust build, in
`target/stdlib-work/image-resize-existing-image.log`. They cover original
coordinate/view/compositing behavior and its five reached allocation denials.
Three selected preexisting PNG-tool groups also pass on application source
`5e7138e5...`: 346 native cases comprise 209 discrete pixel comparisons, 109
CLI/capacity cases and 28 late PNG failures. The combined command passes three
tests in 10.51 seconds, with a separate 1.71-second Rust build, in
`target/stdlib-work/image-resize-existing-tool.log`. These current-source
regressions are separate from new resizing groups and do not rerun the entire
historical 400-case consumer campaign.

This acceptance is finite Linux x86_64 CPU execution from the GPU compiler.
Other hosts, user-program GPU execution, enforced ownership and formal
verification need separate evidence. The implementation uses existing Lanius
views, arithmetic and allocation. No new compiler dependency was encountered,
and no compiler, ABI or native-image-library repair was needed. The source
profile still has no color management or gamma conversion.

## Source context

The filter families and reverse coordinate mapping follow the terminology in
the [OpenCV 4.13.0 geometric-transform documentation](https://docs.opencv.org/4.13.0/da/d54/group__imgproc__transform.html).
OpenCV's [linear-coefficient implementation](https://github.com/opencv/opencv/blob/4.x/modules/imgproc/src/resize.cpp)
provides the half-pixel coordinate reference. Alpha-weighted interpolation is
grounded in the [29 October 2026 CSS Color 4 Candidate Recommendation Draft](https://www.w3.org/TR/2026/CRD-css-color-4-20261029/#interpolation-alpha).
The integer rounding, coverage, identity and resource rules in this guide are
Lanius contracts and make no byte-identity promise with those implementations.
[Pillow 13 filter documentation](https://pillow.readthedocs.io/en/stable/handbook/concepts.html#filters)
describes resize reduction kernels that differ from this fixed-support
Bilinear profile; its output is not an exact oracle for this filter.
