# Exact image resizing model

This fixture checks `ext::image::resize` against the exact profile in
[`library-image-resize-plan.md`](../../../docs/library-image-resize-plan.md).
The Lanius producer emits observations from real runtime calls. Python supplies
only the test reference, corpus and protocol verifier; production image code is
Lanius.

## Independent reference

`resize_rgba(pixels, sw, sh, dw, dh, filter)` is importable by the image-tool
consumer tests. Filters accept `0`, `1`, `2` or `nearest`, `bilinear`, `area`.
Importing the module does not build a corpus or launch a process.

The reference builds exact `Fraction` destination-by-source weight matrices.
Nearest uses destination pixel centers with ties to the higher source index.
Bilinear uses clamped triangular weights. Area intersects each destination
footprint with every source cell. Complete pixels are evaluated directly from
the tensor product of those weights. It has no production tile, projection row,
orientation selection or intermediate raster. Zero weights are omitted and
identical weighted pixel tuples are cached to keep enlarged tiny sources cheap.

Filtered colors divide by exact weighted alpha, even if rounded alpha is zero.
Zero exact alpha yields transparent black. Final nonnegative ties round upward;
there is no intermediate row quantization or color-space conversion. Every
filter preserves all bytes when dimensions are unchanged, including hidden RGB.

## Finite corpus and observations

Seed: `0x1a6e0261113`. The frozen corpus has **626 cases**, comprising:

- All 256 source/destination geometries with each dimension in `1..4`, rotating
  through seven pixel families, three filters and two layouts.
- Eight analytical witnesses and sixteen selected geometries, each under all
  three filters and both layouts. These include opacity extremes, colored
  transparent pixels, impulses, odd ratios, one-pixel axes, identity and mixed
  scaling directions.
- 64 seeded cases with dimensions up to 13 and deliberately biased alpha values.
- 120 metamorphic companion cases, establishing 84 complete transpose or
  reflection relations. Nearest reflection is deliberately not asserted because
  midpoint ties choose the higher source index.
- Six Area tile cases, with source shapes `3×2` and `2×3`. Under the plan's cost
  formula, destination shapes `(255,256)`, `(256,257)`, `(257,258)` choose
  horizontal-first with inner lengths 255, 256, 257; their transposes choose
  vertical-first with the same inner lengths. The respective horizontal/vertical
  costs are `65790/66048`, `66564/67080`, `66824/67596`; transpose swaps them.
- 24 invalid source descriptors combined with invalid destination dimensions,
  plus 12 destination dimension/extent errors with a valid source.

Success counts: **590**, including 180 Nearest, 202 Bilinear, 208 Area, 40 exact
identity copies and 386 cropped sources. The successful results contain
**403,513 pixels**. Rejection count: **36**.

Layout 0 uses a native `u8` array with actual physical byte stride **-8**.
Layout 1 exposes separate stack `i32` storage as packed bytes
with actual physical stride **+1**. Both layouts have real backing for every
access. Image row stride remains a positive logical byte-element count. Source
views include offsets, row padding and selected interior rectangles.

The output records every source descriptor field and actual byte stride, error
code, successful packed result descriptor, and all RGBA bytes. It compares all
8,192 source backing cells, including guards and padding, after resizing. After
the resize borrow ends, it overwrites every source cell and rechecks the complete
result. It then changes every result byte and compares every source cell again.
All results have one cleanup authority and are destroyed before the next case.
Physical extent, lifetime and race freedom remain caller obligations.

The protocol is raw little-endian binary with a fixed case count, exact result
lengths and end marker. One native process handles the complete corpus. Missing,
extra, reordered or differing output bytes fail verification. The reference
expects exactly **14,902,084 output bytes**, not an aggregate checksum.

## Host controls and native gate

The host-only control run passed the fixed corpus and **21 deliberate
corruptions**. Eleven corrupt metadata/observations, eight substitute coherent
incorrect pixel results, and two truncate/append protocol bytes. The pixel
alternatives expose early row rounding, final truncation, nearest ties to the
lower pixel, straight-alpha mixing, division by rounded alpha, discarded
positive-alpha color, lost transparent identity data and corner coordinates.
Controls regenerate complete result observations, including owner-independence
snapshots, for their analytical witnesses.

Host command:

```sh
timeout --kill-after=2s 90s python3 -B tests/fixtures/extended_image_resize_model/oracle.py controls
```

Native selector:

```text
--test extended_image_resize_model_execution image_resize_matches_exact_rational_pixels_guards_and_independent_owners --exact
```

The Rust driver checks that compilation returns an x86_64 ELF, then launches the
Python verifier with a 90-second harness bound. Its one native child has a
75-second bound and must exit zero with empty stderr and exact complete binary
output. The driver also checks the full fixed textual summary.

## Accepted native receipt

Root's focused native gate passed **1/1 tests in 7.88 seconds**, after a separate
**1.64-second Rust build**. The process exited zero, and the complete summary
matched the driver's fixed assertion:

```text
image-resize-model cases=626 admitted=590 rejected=36 nearest=180 bilinear=202 area=208 identity=40 cropped=386 output_pixels=403513 relations=84 layouts=2 seed=0x1a6e0261113
```

Receipt: `target/stdlib-work/image-resize-model.log`. Accepted SHA-256 sources:

- Producer: `5af1217f6efdbd183cde53a676a9aaf96f209ea0047054e466b9cd18ab014ae4`
- Oracle: `7567787179f0d9884a7809eddbaf325ef40c72085f488209443cfd8da1f4bba9`
- Driver: `3ebd06de294b743317535150bf323b52aa555a6b065feab5dbf6fed2f7883f5d`

Independent static review passed these frozen sources and separately reproduced
the **21 host-only corruption controls**. Those controls establish verifier
signal; they are separate from the native runtime receipt.

Acceptance applies to GPU-compiled Linux x86_64 CPU execution. These finite
checks do not establish GPU device execution, other targets, formal correctness,
ownership enforcement or allocation-failure behavior. Separate direct, resource
and scale fixtures cover additional admission details, reached allocation
failures and larger workloads.
