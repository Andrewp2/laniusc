# Native varint memory boundaries

Both registered gates passed compiler/native acceptance on the first attempt:
two tests in 9.94 seconds after a 1.84-second Rust build, recorded in
`target/stdlib-work/native-varint-boundaries-first.log`. Root performed all
executable commands. The positive trace accepted four widths, three ordinary
layouts and seven pure phases with one mapping, protection and exact release.
All four migrated invalid-physical-backing cases separately exited 101.
This gate checks the [native varint contract](../../../../docs/library-native-varint-plan.md)
for u32, i32, u64 and i64, including the distinction between checked logical
metadata and caller-provided physical backing. It does not replace the
separate exhaustive wire/value model.

## Honest extents and seven pure phases

`contracts.lani` runs seven P/p phases:

1. Native descending-byte storage.
2. Packed ascending-byte storage.
3. Packed ascending bytes at an unaligned base+1.
4. Invalid metadata/offsets over null backing and valid empty ranges.
5. Guarded u32/i32 read boundaries.
6. Guarded u64/i64 read boundaries.
7. Guarded writes for all four integer types.

The ordinary layouts use a nonzero View start and a separate nonzero codec
offset. Exact maximum-width bytes are checked independently against literal
base-128 expectations, and successful next positions are relative to the
supplied View. Signed minima use the same maximum unsigned wire pattern via
ZigZag. Complete surrounding logical storage and packed physical outer guards
must remain unchanged. Capacity rejection checks the required encoded length
and every destination byte before/after the attempted write.

The null-backing phase covers negative start/length, overflowing start+length,
negative/out-of-range offsets, and an empty View with start i32::MAX. Bounds
must precede truncation/capacity errors. Valid empty reads return Truncated;
valid empty writes return BufferTooSmall without touching backing. No null
slice is used for an admitted nonempty byte access.

## Protected-page witnesses

One 8192-byte allocation supplies two native 4096-byte pages. Before codec
phases, the fixture protects the second page with PROT_NONE. Every guarded
raw slice honestly covers two accessible leading canaries and its initialized
payload; its complete physical extent ends at the guard-page boundary. No
overclaimed backing is needed for these positive tests.

Continuation-only prefixes of lengths 0..4 and 0..9 must return Truncated.
At the complete fifth/tenth-byte limit, continuation means Overflow without
looking at another byte. Selected final-byte tests distinguish the largest
canonical payload, excessive payload and noncanonical zero termination. Every
read preserves the complete initialized prefix and both leading canaries.
A one-byte terminator in the last accessible byte checks early termination
without a speculative next-byte load, including signed ZigZag decoding.

Writers test every insufficient capacity below five/ten bytes, exact maximum
width and exact one-byte output. Insufficient capacity leaves both canaries
and every destination byte unchanged. Exact-fit stores end immediately before
PROT_NONE, so writing another byte cannot pass unnoticed. Different short
lengths place valid raw buffers at different byte alignments.

The setup uses existing allocator/Linux test APIs. The driver independently
requires one successful 8192-byte mapping, one successful protection of exactly
its second 4096-byte page and one matching full release after all seven phases.
It traces all syscalls and permits no host service inside any codec phase.
Only process entry/exit, setup/protection/release and explicit markers are
accepted outside phases. Root README, compiler, host bindings and ABI are not
changed.

CPU-only controls checked the unsigned maximum encodings, signed-minimum
ZigZag patterns and all eleven honest tail extent calculations. These are
arithmetic controls, not native runtime receipts.

## Retained caller-precondition traps

Four old fixtures were migrated and removed from the old root locations:

| Retired fixture | Native checked replacement |
| --- | --- |
| `core_varint_read_bounds.lani` | `read_u32_overclaim.lani` |
| `core_varint_write_bounds.lani` | `write_u32_overclaim.lani` |
| `core_varint_wide_read_bounds.lani` | `read_u64_overclaim.lani` |
| `core_varint_wide_write_bounds.lani` | `write_u64_overclaim.lani` |

Each replacement deliberately supplies one actual native byte while claiming
a two-byte logical View. The reader starts with continuation byte 128; the
writer requests the two-byte encoding of 128. The second native access must
hit the existing physical bounds trap (exit 101 in this target profile).
These are explicitly invalid caller inputs. They do not promise a recoverable
Bounds error, write rollback, or safety for arbitrary forged pointers; a write
may have changed the first byte before trapping.

Both gates require genuine x86_64 ELF and shared strict jump admission. The
positive lifecycle is bounded to 15 seconds and each physical trap process to
five seconds. Accepted target evidence is finite Linux x86_64 CPU execution
produced by the GPU compiler, with the tested native byte layouts and 4096-byte
base-page profile. GPU-device execution, arbitrary physical overclaims,
unrelated targets and formal verification remain unclaimed.

| Executed source | SHA-256 |
| --- | --- |
| `contracts.lani` | `35c18b3e6ddae42df69c6743171c0cc4ef092de4c4d1ed9e2fa611a234ab055f` |
| `read_u32_overclaim.lani` | `3395b509ed536f404558b76104980cf14f5e166ec9182d0da9b0af56704ae16a` |
| `read_u64_overclaim.lani` | `1341e42684fc725758c573982da0f181705bc1572472995562f5dee297e72e8b` |
| `write_u32_overclaim.lani` | `344678a2e1b11b1e803b5814e92bfc467f5803211a65c75c1bfe92b30e5d7a90` |
| `write_u64_overclaim.lani` | `02bed73136bfad5e2adf3f3beddff4cbdf7f1045a0759a7780b4e4e887780528` |
| Rust driver, tested before formatting | `7cfc223d364bbdb51be69abdc3c82396df88a055e000f7263f3bb450658d6d1f` |

```text
cargo test --test stdlib_varint_boundary_execution native_varints_respect_strides_short_prefixes_guard_pages_and_effect_free_admission -- --exact
cargo test --test stdlib_varint_boundary_execution native_varint_logical_overclaims_preserve_the_physical_backing_precondition -- --exact
```
