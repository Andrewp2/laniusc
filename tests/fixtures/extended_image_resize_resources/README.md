# Image resize resource and scale gates

Driver: `tests/extended_image_resize_resources_execution.rs`.
Contract: `docs/library-image-resize-plan.md`.

Both resource gates passed with the amended driver below, recorded in
`target/stdlib-work/image-resize-resources-final.log`: 2/2 tests in 7.74 seconds,
after a 1.87-second Rust build. Root performed the execution. Independent
resource review passed at the same driver and unchanged producer hashes.

## Native receipts

The accepted amended run observed:

- Six owner/filter baseline cycles, thirteen exact allocations and releases,
  0.008637 seconds native process time and 1.078285 seconds compilation.
- Output denial at `mmap` 2 (site 0), source preservation and same-process
  recovery, three exact successful allocations and releases, and 0.006501
  seconds native process time.
- Scratch denial at `mmap` 3 (site 1), partial-output cleanup and same-process
  recovery, four exact successful allocations and releases, and 0.004438
  seconds native process time.
- All five scale cases, all 1,321,000 output bytes, fifteen exact allocations
  and releases, 0.413954 seconds native process time and 6.169641 seconds
  compilation. Scratch was 16 KiB for the first three shapes and 64 bytes for
  both thin-image shapes.

The host-only publication controls also passed: the valid trace was accepted
and both invalid traces were rejected. Their two expected, caught panic
diagnostics are visible in the log; neither is a failed test.

### Earlier invocation

The first invocation of these same two selectors passed 2/2 in 8.38 seconds,
after a 1.89-second Rust build, recorded in
`target/stdlib-work/image-resize-resources.log`. These are historical receipts,
not additional test identities. That run observed:

- The six owner/filter baseline cycles passed with thirteen exact allocations
  and matching releases. Native process time was 0.008698 seconds; compilation
  of that Lanius fixture took 1.085342 seconds.
- Output denial at `mmap` 2 (site 0) preserved the source and recovered in the
  same process, with three exact successful allocations and releases. Native
  process time was 0.006512 seconds.
- Scratch denial at `mmap` 3 (site 1) released partial output, preserved the
  source and recovered in the same process, with four exact successful
  allocations and releases. Native process time was 0.004410 seconds.
- All five scale cases passed with the complete 1,321,000-byte output and
  fifteen exact allocations and releases. Native process time was 0.541874
  seconds; compilation of that Lanius fixture took 6.663407 seconds. The first
  three cases used 16 KiB scratch each, and both thin-image cases used 64 bytes.

Native times include tracing, process startup, source construction, checks
and output publication. They are separate from compilation and are not isolated
resize timings or evidence of a speedup over another implementation. Rust
formatting and host-only arithmetic checks also passed; those checks do not
replace the native observations.

Independent review found a narrow gap in the original driver's output-write
admission: the producer retired source before output, but the ledger did not
require that ordering at each write. The amended driver requires the cleanup
phase and exactly the successful result owner to be live for every stdout
write. Two host-only negative controls exercise the complete trace parser with
publication before retirement and retirement of the wrong owner; a valid trace
is accepted first. These controls run within the existing owner selector.
No output-byte checks or producer behavior changed. The first receipt used
driver `be78e31d6702d7e9fb454fb80eab420da99989ca521d80ebb1283e36e4e3d93f`;
it is retained as history rather than attributed to the amended assertion.
The final run above exercises the strengthened assertion and both controls.

## Owner and allocation-failure gate

Selector:
`resize_preserves_borrowed_source_and_recovers_reached_result_and_scratch_failures`

`owners.lani` runs six baseline cycles: nonidentity Area, Nearest and Bilinear,
followed by identity under each filter. Each source is a real 172-byte Vec
owner holding a 7-by-5 raster, five padding bytes per row, three leading guard
bytes and four trailing guards. Pixels have varying colors and alpha values
0, 1, 64, 128 and 255, including hidden RGB. Complete source bytes, padding and
guards are checked after every successful or failed operation.

The three nonidentity cases produce 11-by-9 images. Identity produces 7-by-5
independent copies. The host checks every emitted RGBA byte with a small
two-dimensional integer-weight reference. It uses interval overlaps and
triangular linear weights and does not reproduce the tiled implementation.
Input destruction occurs before output publication. The exact allocation
ledger must show only the independent result remaining in that phase, followed
by one explicit result release.

Area first allocates 396 output bytes, then 704 scratch bytes. The latter is
two rows of eleven four-word Sum values. Scratch must be released before the
result returns. Nearest, Bilinear and all three identity cases allocate only
their result. Invalid destination dimensions are rejected inside a phase that
forbids every host effect. The six cycles account for thirteen successful
allocations and releases.

Two additional executions deny the output and scratch reservations selected
from the successful Area baseline. Each checks the complete normalized effect
prefix leading to its reached denial, unchanged source, partial cleanup before
the error returns, and a successful retry in the same process. A scratch denial
must retire the partial output. The source stays live until the explicit caller
cleanup phase. These cover both actual Area reservation sites, not every filter
under redundant fault injection.

## Analytic scale gate

Selector:
`resize_area_scale_matches_analytic_pixels_with_bounded_workspace_in_both_orientations`

`scale.lani` runs five Area workloads. Every source is padded and guarded as
above; all pixels and guards are preserved. The producer checks every output
pixel before and after source destruction, and the host compares all output
bytes independently.

| Source | Output | Expected scratch | Output bytes | Exact expectation |
| --- | --- | ---: | ---: | --- |
| 1024 × 768 | 512 × 384 | 16,384 bytes | 786,432 | Each 2 × 2 block is constant; preserve its RGBA except transparent blocks become black |
| 517 × 3 | 257 × 5 | 16,384 bytes | 5,140 | Opaque color half-planes integrated by clamped interval length |
| 3 × 517 | 5 × 257 | 16,384 bytes | 5,140 | Transposed half-planes exercise the other projection orientation |
| 65,536 × 1 | 1 × 65,536 | 64 bytes | 262,144 | Exact repeated-period premultiplied mean `(128,127,128,128)` |
| 1 × 65,536 | 65,536 × 1 | 64 bytes | 262,144 | Same exact mean in the reverse orientation |

The 257-pixel inner output axes cross a 256-pixel tile boundary. Both thin
directions would require over four billion source/output pairs in a naive
two-dimensional overlap scan. The bounded execution gate and exact results
exercise this risk; they are not an asymptotic proof or a compiler comparison.
Across the five shapes, the gate observes 920,606 source pixels, 330,250 output
pixels and all 1,321,000 output bytes, with fifteen exact allocations and
fifteen releases.

The native wall-clock receipt is recorded separately from compilation. It
includes tracing, source setup, preservation checks, output checks and output
publication, so it is not an isolated resize benchmark. Each native process
has a fifteen-second timeout.

## Source-derived storage and trace admission

Source storage is `(source_width * 4 + 5) * source_height + 7` packed bytes.
Result storage is exactly `destination_width * destination_height * 4` bytes.
`ResizeSum` in `extended/ext/image.lani` has four `u64` fields; current
`core::mem` layout assigns one eight-byte word to each, totaling 32 bytes.
The implementation reserves exactly two rows of
`min(256, chosen_inner_output_dimension)` values. Orientation uses the frozen
overlap-count costs and shorter-inner-axis tie rule. This yields at most 512
Sum values, or 16 KiB logical workspace, independently of raster dimensions.

The full syscall ledger requires exactly the result and the stated scratch
reservation during Area calls; there is no admission for an allocated full
intermediate raster. Successful scratch release precedes result publication.
Result-only paths cannot allocate extra workspace.

Every native artifact must be ELF x86-64 and pass the shared complete jump
validator. Full syscall tracing admits launch, one initial mode byte for the
owner fixture, protocol markers, selected allocation/release effects, checked
output writes and successful exit. Pure checking/admission phases forbid all
other host effects. The ledger tracks full-width addresses and exact extents,
rejects overlap, unknown or repeated releases and incorrect sizes, and forbids
the resize operation from releasing its borrowed source. It must be empty at
the explicit completion marker. Process exit is not cleanup evidence.

The intended target is Linux x86-64 CPU output from the GPU compiler. No
user-program GPU execution, other host target, automatic lifetime checking,
formal proof, gamma conversion or external-library byte equivalence is claimed.
Broader numerical cases and actual byte strides belong to the complementary
direct/model gates; this gate focuses on storage, recovery and the selected
scale shapes.

## Frozen hashes

- Driver:
  `3cbd6cc1133e89301cc80cb1b495426a47f424fb639fd0813f6a2b4721d894ea`
- `fixture/support.lani`:
  `dc2918f232cc7f4765b41b147f034b777c5d27eae2adc7e8109d73b5dfdbc7d6`
- `owners.lani`:
  `c3589913903069d3c9de4d62c4285e2513fb6a13f090f3a0e4e0fe714dd7bc77`
- `scale.lani`:
  `c6a7db481a007fa53e66a6e08d2f83be5f71541c6c0a271d371aa91528a430c0`
