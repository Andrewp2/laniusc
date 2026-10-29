# Image-tool resize consumer evidence

Driver: `tests/extended_image_resize_tool_execution.rs`.
Program: `sample_programs/library/image_tool.lani`.
This suite covers the new resize path. Existing image-tool tests remain
unchanged and keep their separate cases and receipts.

## Reference and corpus

The oracle imports `resize_rgba` from
`tests/fixtures/extended_image_resize_model/oracle.py`. That test-only function
uses exact rational weights and direct two-dimensional accumulation, including
the explicit identity and alpha policies. The consumer oracle does not copy
the production resize algorithm or implement another rational filter.

Real PNG files pass through the application decoder, existing transforms,
resizer and PNG encoder. Pillow independently decodes the returned PNG, and
every RGBA byte and both dimensions must match the shared reference. The oracle
also checks each emitted chunk's extent and CRC and requires terminal IEND
with no trailing output. PNG compression bytes need not match another encoder.

| Group | Native cases / status | Scope |
| --- | ---: | --- |
| pixels | 24 accepted | All three filters on one-pixel axes, reduction, enlargement and identity; mixed axes; resize after crop/clockwise rotation/flips; default Area; RGB and palette-alpha input |
| cli | 34 accepted | New dimension/filter syntax, signs/zero/overflow/non-ASCII rejection, filter dependency, info/help behavior, leading zeros, attached values and last valid repeated values |
| limits | 10 accepted | Exact/excess resized pixel cap, source cap before downsizing, earlier crop errors, late CRC/filter/trailing errors, huge requested dimensions and exact/excess staged PNG byte cap |
| faults | 34 accepted | One real allocation baseline, 22 reached ENOMEM cases and 11 input/output/diagnostic failure cases |

The all-transform witness supplies options out of semantic order and compares
crop → clockwise rotation → horizontal flip → vertical flip → resize. Host
controls verify that omitting either flip or moving resize first changes the
expected bytes. Identity cases retain hidden RGB under zero alpha.

New option failures and help perform no stdin reads. Argument storage may be
allocated before option validation, matching the existing snapshot API. Full
PNG validation and earlier transforms precede the resized pixel cap; the
independent encoded-output cap fails before stdout. Successful help retains
the existing exact 105-byte usage text.

## Resource and failure observations

The successful fault baseline decodes a 32×19 image, crops to 27×17, rotates
clockwise, flips both axes and resizes to 67×49 with Area. Each actual mmap
ordinal is recorded and then injected separately. Every denial must be reached,
match the entire successful mmap argument prefix, return status 4 with the
appropriate stage diagnostic, and release all successful allocations. No
later allocation is accepted after the denial. The baseline is counted once.

The baseline explicitly identifies the resized raster extent, its following
bounded Area workspace, and the subsequent PNG raw scanline allocation. Both
resize allocations therefore participate in the reached-denial sweep.
The measured baseline contained 22 allocations, and all 22 individual denials
were reached. These application denials are separate from the two direct
library resource denials.

The ledger tracks full mapping addresses and extents, permits legitimate
virtual-address reuse after a release, and rejects leaks or duplicate/wrong-size
releases. It identifies arguments at the first input read and the original
input owner at EOF. During every ordinary stdout attempt, input must already
be retired and exactly the staged output plus argv owners must remain live.
No allocation is allowed after publication starts. Output retires before
argv, and diagnostics require all observed owners to be retired. Pre-output
decode/transform stages can legitimately allocate and release intermediate
rasters; the ledger does not pretend to identify each such raster by type.

The observed syscall set is `read`, `write`, `mmap`, `munmap`, `mremap`, `brk`,
`openat` and `close`. Unexpected allocation services or file opens/closes are
rejected within this scope. This is not observation of every host effect.

I/O cases reach read EIO before/after a confirmed prefix, read EAGAIN,
Interrupted reads/writes, write EIO, zero write, actual `/dev/full`, and failed
argument/output diagnostics. A later write error retains the real baseline's
first 1,024-byte PNG prefix. Every captured stdout/stderr byte must correspond
to confirmed successful writes; positive successful transfer counts are never
injected. Existing write retry policy is unchanged; no new global attempt
budget or SIGPIPE policy is claimed.

## Controls and receipts

```sh
timeout 90s python3 -B tests/fixtures/extended_image_resize_tool/oracle.py controls
```

Host-only controls pass: `pixels=24 cli=34 limits=10 faults=12+A`. Controls
exercise full expected PNG pixels, order mutations, changed-channel rejection
and deliberately invalid ownership traces. They run no Lanius executable and
add no native process cases.

The pixels selector passed 1/1: 24 native cases in 8.22 seconds, with a
separate 1.78-second build. Log:
`target/stdlib-work/image-resize-tool-pixels.log`; evidence:
`/tmp/image-resize-tool-pixels-np5etsxi`.

The remaining three selectors passed together, 3/3 in 10.68 seconds, with a
separate 0.18-second build. They shared one command and compilation; these
are combined timings, not per-group measurements. Log:
`target/stdlib-work/image-resize-tool-remaining.log`.

| Accepted group | Native cases | Evidence directory |
| --- | ---: | --- |
| cli | 34 | `/tmp/image-resize-tool-cli-onpogl4c` |
| limits | 10 | `/tmp/image-resize-tool-limits-j7lriegu` |
| faults | 34 | `/tmp/image-resize-tool-faults-a3qoehd7` |

All four new groups passed 102 native application cases: 24 + 34 + 10 + 34.
The fault summary was `cases=34 reached_allocations=22`. The successful
baseline is counted once. Existing consumer regressions, direct library
fixtures, host controls and standalone CLI examples have separate counts.

An authoring correction from oracle `108d3f5e` to `2f0d7859` occurred around
the pixel run's start: the ledger now permits later mappings to reuse the
retired input's virtual address. The earlier version could falsely reject
such reuse. Pixel/reference, source and other ownership assertions did not
change; a passing run under either version retains that evidence. No native
cases were repeated or added for this correction. Remaining gates use the
frozen corrected oracle below.

Frozen consumer source SHA256:
`5e7138e5f1427f30f8c103ea9a0d6ab530bc32a61472389eb4792d62a1df47a2`.
Driver SHA256:
`7fc8f0b0aa55082682e3aa0fad76cbacbe0c26cf75a50e6262fb2e665146342f`.
Oracle SHA256:
`2f0d7859a3afa82365928f634275b87c3497ad5425cc653c7117a3cc2c593c77`.
Imported shared model oracle SHA256:
`7567787179f0d9884a7809eddbaf325ef40c72085f488209443cfd8da1f4bba9`.
Its own fixture records separate model acceptance and counts.

The driver requires actual ELF64/little-endian/x86-64 output and the shared
jump-displacement gate. Each Rust test process compiles the application once;
each oracle is bounded to 85 seconds and each native child to 60 seconds.
Root runs compiler/native commands serially under the repository lock and a
100-second outer bound. Initial execution acceptance is Linux x86_64 CPU output
from the GPU compiler, not device execution, other hosts or formal proof.
Same-process application retry is not tested; every CLI invocation is a fresh
process. Direct image and resource fixtures have separate ownership/recovery
evidence and counts.
