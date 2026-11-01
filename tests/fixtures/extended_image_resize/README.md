# Image resize direct contracts

The exact coordinate, rounding, alpha, ownership and resource contract is in
[`docs/library-image-resize-plan.md`](../../../docs/library-image-resize-plan.md).
These fixtures invoke production `ext::image::resize`; they contain no resize
implementation. The independent model, reached allocation failures, scale
cases and PNG application have separate drivers and receipts.

## Registered groups

`tests/extended_image_resize_execution.rs` registers four executable groups:

- `image_resize_all_filters_execute_tiny_admission`: a guarded two-pixel
  borrowed source reduces to one pixel with all three filters. Nearest copies
  the selected source pixel; Bilinear and Area reject hidden transparent RGB
  contamination and round alpha upward. Every result is packed and separately
  retired. Exactly four allocations are released: three outputs and Area's
  scratch, exercising the private generic Sum workspace through the real API.
- `image_resize_exact_samples_alpha_ties_and_single_axes_execute`: twenty
  literal cases distinguish exact nearest ties, transparent hidden color,
  one-pixel axes, zero exact alpha, positive exact alpha that rounds to zero,
  half-up alpha/color rounding, clamped borders, odd reductions and mixed-axis
  changes in both orientations. Odd reduction expectations distinguish all
  three filter families. Complete RGBA output and source bytes are checked.
  The cases require twenty output allocations and eight Area scratch
  allocations, all released.
- `image_resize_padded_cropped_native_strides_identity_and_independence_execute`:
  an interior crop of a padded raster is tested on actual negative native
  byte stride and positive packed byte stride. All three filters preserve
  hidden RGB exactly for identity resize and produce independent packed
  owners. Downsampling the same crop checks alpha-weighted values. Result
  mutation leaves the source and other result unchanged; subsequent source
  mutation leaves both results unchanged. Every source pixel, every padding
  byte and all outer guards are compared across the full 96-byte backing.
  Twelve result allocations and two nonidentity Area workspaces are released;
  identity Area has no scratch allocation.
- `image_resize_metadata_and_destination_error_precedence_execute`: malformed
  source dimensions, byte metadata, stride and final-row extent produce Bounds
  before invalid destination errors. Valid source descriptors then reject
  nonpositive or oversized destinations as Dimensions/SizeOverflow. Deliberate
  null-backed sentinels establish rejection before sampling; one logically
  maximum descriptor is used only with rejected destinations. No allocation
  or other host work is admitted. Real guarded backing remains unchanged.

The twenty literal sample vectors were checked before native admission with
an independent, bounded host calculation using two-dimensional exact rational
weights. The first host authoring check conflated same-named arrays from
separate fixture functions; restricting that check to function scopes fixed
the checker, without any fixture expectation change. The corrected check
accepted all twenty vectors and their 28 specified allocation lifetimes.
This authoring check is separate from native execution and from the larger
independent model campaign.

## Execution profile

Each fixture compiles through the GPU compiler to a Linux x86_64 CPU program,
passes strict ELF/shared in-function jump checks, and executes with a 15-second
child bound. Complete syscall traces admit only one successful launch/exit and
successful mmap/munmap lifetimes. Full-width allocation addresses and requested
lengths must match, the exact finite allocation count must hold, every mapping
must be released, and stdout/stderr must be empty. The preflight group admits
zero allocations. No new host service is used.

These are finite tests of the library's integer sample-space profile, not a
claim of byte identity with other image libraries, gamma conversion, color
management or antialiasing from fixed-support Bilinear. Physical source backing
remains a caller obligation; unreadable spans appear only on paths required to
reject before access. No successful huge raster is simulated. Other targets,
user-program GPU execution, enforced lifetimes and formal verification require
separate evidence. Allocation failure and extreme-aspect-ratio work bounds are
covered by the separate resource/scale owner.

Root alone runs compiler/Cargo/native commands under the shared library lock,
with each outer command bounded to 100 seconds. This fixture owner performs
source preparation and bounded host checks only.

## Receipts

- Tiny admission passed 1/1 in 6.18 seconds (separate Rust build 1.95 seconds),
  with all four matched allocation lifetimes released.
  Log: `target/stdlib-work/image-resize-admission.log`.
  Tested sources: admission `dd083b36...`, driver `2a643e2e...`, and image
  `daad5347...`.
- After tiny acceptance, the driver changed only the two remaining positive
  groups' allocation bounds to their exact counts, 28 and 14. Tiny source,
  helper and expectations remain unchanged.
- The remaining three groups passed 3/3 in 8.54 seconds (separate Rust build
  1.71 seconds). Contracts released all 28 matched mappings; layouts released
  all 14; preflight performed no allocations. Every group passed the complete
  host-effect trace and exited successfully.
  Log: `target/stdlib-work/image-resize-direct.log`. Tested sources are the
  final driver/fixture hashes below; image source remained `daad5347...`.
- Independent source review accepted the exact literal samples, cropped
  offsets, both actual stride signs, all source/guard bytes, owner independence,
  preflight sentinels and lifecycle counts. Source review and the host rational
  check are distinct from native execution.
- All four registered groups are accepted across the two native runs. No
  fixture or production change and no native rerun followed acceptance.

## Frozen sources

| Source | SHA-256 |
| --- | --- |
| `tests/extended_image_resize_execution.rs` | `d05ef12281590f7c3a55cf7ebc69409671090ed2d81a5e8c1dc80b050a4f5aef` |
| `admission.lani` | `dd083b3669f872963555c29a4cea79bc45d64bbf7a271284005badf22013cdcf` |
| `contracts.lani` | `36a26fca2eb82a4bb67592a39372d973aadf95f76191b54712ee282286848bef` |
| `layouts.lani` | `e57ea879013a7a16ec91a7e616053c027c52018fd01b6bf4ade95c3db298bff7` |
| `preflight.lani` | `404df8cd2444f22c6d1552602b2dc7e8dda8dab0e5cbbcf0620b37288bba704a` |
