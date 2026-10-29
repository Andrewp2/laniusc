# RGBA8 raster images

`ext::image` provides owned images and borrowed rectangular views. Production
code is Lanius. Earlier executable tests establish GPU-compiled x86_64 Linux
behavior for the operations in their recorded scope. The new
[three-filter resize contract](extended-image-resize.md) passes all seven
library groups and four PNG-tool groups/102 native cases, with separate
current-source regressions and standalone examples. Earlier receipts retain
their original operation scope.

Pixels use four bytes in red, green, blue, alpha order. Alpha is straight
(unassociated): transparent pixels can retain nonzero color channels. Rows run
from top to bottom, and `(0, 0)` is the upper left pixel. The library does not
assign a color space, apply gamma correction, or perform color management.

## API

```text
Rgba { r: u8, g: u8, b: u8, a: u8 }
View { bytes: core::slice::View<u8>, width: i32, height: i32, stride: i32 }
Error = Dimensions | SizeOverflow | Bounds | AllocationFailed
Filter = Nearest | Bilinear | Area

byte_len(width, height) -> Result<i32, Error>
new(width, height, fill: Rgba) -> Result<Image, Error>
from_rgba(width, height, bytes: View<u8>) -> Result<Image, Error>
view(bytes: View<u8>, width, height, stride) -> Result<View, Error>
valid(view: View) -> bool

Image.borrow() -> &Image
Image.width() / Image.height() -> i32
Image.rgba() -> core::slice::View<u8>
Image.view() -> ext::image::View
Image.try_clone() -> Result<Image, Error>
Image.destroy()

get(source: View, x, y) -> Option<Rgba>
set(target: View, x, y, pixel: Rgba) -> bool
fill(target: View, pixel: Rgba) -> Result<i32, Error>
subview(source: View, x, y, width, height) -> Result<View, Error>
crop(source: View, x, y, width, height) -> Result<Image, Error>
rotate90(source: View) -> Result<Image, Error>
resize(source: View, width: i32, height: i32, filter: Filter) -> Result<Image, Error>
flip_horizontal(target: View) -> Result<i32, Error>
flip_vertical(target: View) -> Result<i32, Error>
blit(target: View, x, y, source: View) -> Result<i32, Error>
source_over(target: View, x, y, source: View) -> Result<i32, Error>
over(source: Rgba, destination: Rgba) -> Rgba
```

All omitted coordinate/count argument types are `i32`. Dimensions must be
positive, and `width * height * 4` must fit `i32`; checks precede multiplication.
Empty images and empty regions are rejected. `from_rgba` requires exactly the
packed byte count and copies its input. `new`, `crop`, `rotate90`, and
`try_clone` return independent packed owners. Rotation is 90 degrees clockwise.
The flips mutate their target in place without allocating. Successful mutation
functions return the affected pixel count.

`resize` is the new addition to this API. It returns an independent packed
owner after full source validation, destination-size admission and allocation.
Nearest copies selected pixels; Bilinear and Area use exact alpha-weighted
sampling, with a byte-preserving identity rule for every filter. The
[resize guide](extended-image-resize.md) specifies coordinates, rounding,
failure precedence and O(source + destination pixels) Area work with bounded
tiled scratch.

`subview` borrows a region while preserving the parent row stride. The full
requested region must fit; there is no implicit clipping. `blit` and
`source_over` copy the full source at the target coordinates. They snapshot
source pixels before writing, so overlapping views of the same owner work.
Allocation failure leaves the entire target unchanged. An invalid coordinate
or invalid view makes `get` return `None` and `set` return `false`; other region
operations return `Bounds` before writing.

## Compositing

`over` and `source_over` compute straight-alpha source-over using the stored
channel values. This is compositing in the existing sample space; linear-light
compositing requires the caller to linearize color samples first.

For source alpha `sa` and destination alpha `da`, in `[0,255]`, let
`A = sa * 255 + da * (255 - sa)`. The output alpha is
`floor((A + 127) / 255)`. Each color channel is
`floor((source * sa * 255 + destination * da * (255 - sa) + A / 2) / A)`.
When `A` is zero, all four output channels are zero. These operations use
integer arithmetic and round to the nearest representable result.

## Ownership and view contract

An `Image` owns one `alloc::vec::Vec<u8>`. Copies alias that allocation: keep
one active owner and call `destroy()` once. Destruction also resets the active
owner's dimensions. Borrowed views must not outlive the underlying storage.
Do not destroy an aliased copy or retain views across changes to its owner.

A view may use packed or native strided byte storage, a nonzero byte offset,
and row padding. `stride` counts logical byte elements, and must be at least
`width * 4`. Validation checks negative/overflowing byte metadata and that the
last row fits the declared byte count. Physical backing extent, backing
lifetime, and concurrent access remain caller preconditions; a fabricated
count cannot establish that the memory exists. Operations touch only pixel
bytes and preserve row padding and bytes outside the view.

## Verification

Historical `tests/extended_image_execution.rs` evidence covers coordinate
checks for every width and height from 1 through 7, crop independence,
clockwise rotation, both flips,
overlapping blits, exact compositing examples, padded native byte arrays,
selected views, invalid metadata, and size overflow. `strace` allocation
denial checks every observed allocation in construction, crop, rotation, blit,
and source-over, including target atomicity and destruction of prior owners.

Both preexisting groups were rerun against image source `daad5347...` during
the resize increment: two tests pass in 7.44 seconds, with a separate
1.90-second Rust build, in `target/stdlib-work/image-resize-existing-image.log`.
This current-source regression includes the five reached allocation denials
for the original operations. It is separate from new resizing tests, whose
[acceptance record](extended-image-resize.md#evidence-and-target-scope) includes
four direct groups, the 626-case independent model and two resource/scale groups
with reached output/scratch allocation failures and same-process recovery.
Other hosts, device execution, enforced lifetimes and formal proofs require
separate evidence.
