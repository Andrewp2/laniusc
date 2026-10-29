# Image resizing

The full library goal remains open. At `84000c90`, the image module and PNG
tool crop, rotate, flip and composite but cannot resize a raster. This increment
adds resizing to that existing image pipeline. The independent roadmap audit
also identified vector owner transfer and streaming compression encoding as
substantive later work; neither is replaced by this media increment.

## Contract and sources

Add to `ext::image`:

```text
Filter { Nearest, Bilinear, Area }
resize(source:View, width:i32, height:i32, filter:Filter) -> Result<Image,Error>
```

The result is a new packed straight-alpha RGBA8 owner. The source is borrowed
and unchanged on every success or failure. Existing Image/View, row padding,
actual byte stride and manual lifetime contracts apply. Copies do not create
another cleanup authority. Source backing must remain alive and immutable
through the operation.

Validate the complete source descriptor first (`Bounds`), then destination
dimensions and checked byte extent (`Dimensions`/`SizeOverflow`). Finish all
admission and allocations before sampling source pixels. Allocation failures
return `AllocationFailed` and retire partial output/scratch. No partial Image
escapes. There is no new host service, compiler feature or work quota.

The source references are the OpenCV 4.13.0
[geometric transform documentation](https://docs.opencv.org/4.13.0/da/d54/group__imgproc__transform.html)
and its [linear coefficient implementation](https://github.com/opencv/opencv/blob/4.x/modules/imgproc/src/resize.cpp),
plus the 29 October 2026 CSS Color 4
[alpha interpolation description](https://www.w3.org/TR/2026/CRD-css-color-4-20261029/#interpolation-alpha).
These establish the filter families, half-pixel linear coordinates and
premultiplication principle. The exact integer rounding, area coverage and
identity policies below define this library's profile. They are not a promise
of byte identity with another library. Pillow 13's
[filter documentation](https://pillow.readthedocs.io/en/stable/handbook/concepts.html#filters)
also makes clear that its resize minification kernels differ from a fixed
2-by-2 bilinear neighborhood.

For each destination coordinate `d`, let the corresponding source coordinate
be `(d + 1/2) * source_length / destination_length - 1/2`.

- **Nearest:** choose `floor((d + 1/2) * source_length / destination_length)`
  on each axis. Exact halfway ties choose the higher source index. Copy all
  four bytes, including hidden RGB under zero alpha.
- **Bilinear:** clamp the source coordinate to `[0, source_length - 1]`,
  then combine its neighboring samples with the exact tensor product of the
  two linear weights. This is fixed-support interpolation, not an antialiasing
  minification filter.
- **Area:** integrate the piecewise constant source pixels over the destination
  pixel footprint `[d*s/t, (d+1)*s/t]` on each axis. Weight each source pixel by
  its exact overlap area. This supports reduction, enlargement and mixed-axis
  resizing. The footprints partition the complete source rectangle.

Filtered modes operate in the existing stored sample space; no gamma or color
profile conversion is implied. For positive integer weights `w`, compute
`D = sum(w)`, `A = sum(w*a)` and `C = sum(w*a*c)` per color channel. Alpha is
`floor((A + floor(D/2))/D)`. If exact `A` is zero, output is transparent black.
Otherwise each color is `floor((C + floor(A/2))/A)`, even when the rounded alpha
is zero. There is no intermediate premultiplication or row quantization.
Nonnegative exact halfway results round upward. When both dimensions are
unchanged, every filter returns a byte-preserving independent copy, including
hidden RGB. This explicit identity rule precedes filtered accumulation.

## Algorithm and resource bounds

Nearest and bilinear use constant scratch and work proportional to output
pixels. Bilinear axis weights have denominators `2*destination_length`.
The total weight is `4*destination_width*destination_height`, below `2^31`
under the existing image byte bound. Area weights use integer overlaps between
`[d*s,(d+1)*s]` and `[i*t,(i+1)*t]`, with total weight `source_width*source_height`,
below `2^29`. Coordinate products fit signed 64 bits; weighted alpha/color
sums fit unsigned 64 bits. Cast before products; do not rely on wrapping.

Area uses exact separable passes with a cached source projection row and an
output accumulator row. Process the inner output axis in tiles of at most 256
pixels, and project only the source intervals touched by that tile. Monotone
outer footprints reuse their shared boundary row. Store unrounded alpha and
color-times-alpha sums until final output.

Choose the cheaper orientation using the exact one-dimensional overlap counts
`Ix = sw + dw - gcd(sw,dw)` and `Iy = sh + dh - gcd(sh,dh)`. Horizontal-first
work is proportional to `sh*Ix + dw*Iy`; vertical-first is proportional to
`sw*Iy + dh*Ix`. Break ties by the shorter inner output dimension. The minimum
is linear in source plus destination pixels, including `N*1 -> 1*N` and its
transpose. A naive nested two-dimensional overlap scan would be quadratic on
those shapes and is not accepted.

Use one bounded allocation of at most 512 private Sum values (four u64 fields
each) for Area's two rows. Workspace is independent of full raster dimensions;
there is no full intermediate image. Identity, Nearest and Bilinear need only
the result allocation. Allocate the output before scratch, retire either on
failure, and retire scratch before returning the result. This makes allocation
failure behavior directly observable without a new workspace abstraction.

## PNG consumer

Extend the existing `image_tool transform` with `--resize WIDTH,HEIGHT` and
`--filter nearest|bilinear|area`. The default filter is Area. A filter without
resize is an argument error. Dimensions are positive ASCII decimal integers
fitting i32; repeated valued options use their last value. Existing `info`
rejects transform options. Keep the existing argument snapshot limits.

The fixed order becomes crop, clockwise rotation, horizontal flip, vertical
flip, resize. Final requested width/height therefore describe output axes.
Apply the existing `--max-pixels` ceiling to resized output as well as decoded
input, before allocating the replacement. This transform check occurs after
complete PNG validation and earlier transforms, preserving stage order.
Keep full PNG staging before stdout, existing exit/diagnostic meanings and
explicit cleanup of replaced rasters. No metadata/color-management behavior
changes. A resize failure retires the current raster through the same owner
handoff used by crop and rotation.

## Verification and work split

Eight agents own image implementation, consumer implementation, direct tests,
independent model, resource/scale tests, consumer tests, documentation and
independent review. Root owns this contract, integration, native commands and
release. Compile one tiny real admission before the larger campaigns.

Direct tests cover exact ties, one-pixel axes, identity, alpha extremes and
low nonzero alpha, odd reductions, mixed-axis changes, cropped/padded views,
actual positive/negative byte strides, invalid metadata and error precedence.
The independent model uses rational two-dimensional reference weights, full
RGBA output and source preservation, not the production separable traversal.
Include finite metamorphic checks and corruptions that demonstrate oracle
signal. Resource tests check reached result/scratch allocation failures,
complete allocation identities/extents, cleanup and same-process recovery.
Scale cases include ordinary images, dimensions crossing tile boundaries and
both extreme aspect-ratio directions; record native runtime separately from
compilation without making unsupported speed claims.

Consumer tests exercise decoded output pixels against the reference, transform
order, CLI syntax, output pixel caps, staged failures, reached allocation
failures and relevant I/O paths. Existing image contracts and the existing
consumer behavior remain relevant regression gates because their source files
change. Select tests according to actual risk; do not rerun unrelated suites.

Root alone runs compiler/Cargo/native commands serially under
`target/stdlib-work/library-gpu.lock`, each outer command capped at 100 seconds.
No broad GPU/performance reruns. Runtime acceptance is Linux x86_64 CPU output
from the GPU compiler. User GPU programs, other hosts, formal proofs and
enforced ownership require separate evidence. Preserve the root README,
AI_POLICY, CONTRIBUTING, protected `std::vec`/`core::mem`, `tests/common` and
compiler/IR/ABI/extractor/proof files. Report any compiler dependency with a
small reproduction instead of absorbing its repair into this increment.

## Accepted increment

The frozen image source `daad5347` and PNG consumer `5e7138e5` execute on the
Linux x86_64 CPU profile. All seven new library groups and four new consumer
groups pass. No production correction or compiler change was needed after the
first tiny admission.

| Gate | Accepted result | Local receipt |
| --- | --- | --- |
| Tiny filter admission | 1/1, 6.18 s; separate Rust build 1.95 s | `target/stdlib-work/image-resize-admission.log` |
| Exact direct contracts, layouts and preflight | 3/3, 8.54 s; build 1.71 s | `target/stdlib-work/image-resize-direct.log` |
| Independent rational model | 626 cases, 7.88 s; build 1.64 s | `target/stdlib-work/image-resize-model.log` |
| Final resource and scale gates | 2/2, 7.74 s; build 1.87 s | `target/stdlib-work/image-resize-resources-final.log` |
| Consumer pixel model | 24 cases, 8.22 s; build 1.78 s | `target/stdlib-work/image-resize-tool-pixels.log` |
| Consumer CLI, limits and faults | 34 + 10 + 34 cases in one combined 10.68 s run; build 0.18 s | `target/stdlib-work/image-resize-tool-remaining.log` |
| Existing image regressions | 2/2, 7.44 s; build 1.90 s | `target/stdlib-work/image-resize-existing-image.log` |
| Selected existing consumer regressions | 346 cases in 3 groups, 10.51 s; build 1.71 s | `target/stdlib-work/image-resize-existing-tool.log` |

The rational model checks 590 successful calls and 36 admission errors, with
403,513 complete output pixels, 40 identities, 386 cropped cases, two physical
byte layouts and 84 metamorphic relations. Seed `0x1a6e0261113` is fixed.
Twenty-one host corruption controls remain separate from native case counts.

Resource acceptance covers six filter/identity lifecycle cases and both reached
Area result/scratch allocation denials with source preservation, partial cleanup
and same-process recovery. The five scale shapes compare 1,321,000 output bytes,
including both 65,536-axis reversals and both tile-crossing orientations. Exact
mapping extents and retirement are observed. The final scale process took
0.413954 seconds, including process and trace overhead but excluding its
separately measured 6.169641-second compiler invocation; this is a finite
observation, not a general throughput ratio. Scratch requests are at most
16,384 bytes and are 64 bytes for each extreme aspect-ratio case.

Independent review strengthened the resource ledger after its initial passing
run: every output write must observe only the independent result still live.
The final driver `3cbd6cc1` also rejects synthetic early-publication and
wrong-owner-retirement traces. These expected caught failures print diagnostic
text in the passing test log. The initial 8.38-second resource receipt is
history of the same two test identities, not two more accepted groups.

The four new consumer groups contain 102 native cases, including 22 reached
allocation denials. These are separate from the two new library denials and
the five old-image regression denials. A consumer trace-parser correction
around the pixel run stopped mistaking later reuse of a virtual address for
a second retirement of the original input. Pixel cases and complete expected
bytes were unchanged; the corrected harness was reviewed before the final
three groups. See the [consumer fixture receipt](../tests/fixtures/extended_image_resize_tool/README.md)
for the exact source-hash scope.

Standalone CLI compilation and both documented examples also pass, in
`target/stdlib-work/image-resize-cli-build.log` and
`target/stdlib-work/image-resize-cli-examples.log`. The crop/rotate/flip/Area
example produces a 40-by-50 image with 8,000 exact decoded RGBA bytes; the
Nearest example produces a 256-by-256 image with 262,144 exact decoded RGBA
bytes. Both complete PNGs validate, exit 0 and emit no stderr. These examples
are separate from application case counts.

The [resize guide](extended-image-resize.md) and linked fixture receipts retain
the precise runtime and ownership scope. No additional compiler dependency was
encountered. Broader media work, other targets, formal proofs, enforced
ownership and the full standard/extended-library goal remain open.
