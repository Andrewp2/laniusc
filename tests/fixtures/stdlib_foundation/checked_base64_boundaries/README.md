# Checked Base64 memory boundaries

Both registered gates passed compiler/native acceptance on the first attempt:
two tests in 8.50 seconds after a 1.90-second Rust build, recorded in
`target/stdlib-work/checked-base64-boundaries-first.log`. The parent agent ran
all executable commands. The positive trace accepted four profiles, eleven
input lengths, three ordinary layouts and seven pure phases, with one mapping,
protection and exact release. Both migrated physical-overclaim cases separately
exited 101. No compiler, Cargo or native executable was run by this author.
The gate targets the [checked Base64 contract](../../../../docs/library-checked-base64-plan.md),
with four explicit profiles and the supported exact-alias storage contract.
It complements the independent wire/error model and direct RFC vectors.

## Seven pure phases

`contracts.lani` has seven P/p phases:

1. Native descending-byte storage with a nonzero View start.
2. Packed ascending-byte storage with a nonzero View start.
3. Packed ascending bytes at base+1, with physical outer guards.
4. Null-backed logical metadata, empty, structural and capacity admission.
5. Disjoint guarded encode input and output extents.
6. Disjoint guarded decode input and output extents.
7. Guarded exact same-base in-place encoding and decoding.

Each ordinary layout tests all four profiles at every input length 0 through
10, including every residue modulo three and several group boundaries. The
binary prefixes contain `fb ff ff`, ASCII and zero, so both alphabet-specific
symbols and tails are exercised. Literal expected wire rows were obtained
independently using Python's standard-library Base64 functions; decoding is
checked against the literal original binary bytes. Neither direction uses a
roundtrip as its only expectation. Written counts are relative to output.start.

Source and destination selected first-byte address and stride are identical
for the in-place tests. Encoding checks every byte of the 64-byte backing.
Decoding checks the replaced binary prefix, every trailing original wire byte,
and every outside sentinel. Exact capacities succeed; capacities one byte below
the complete required count must return BufferTooSmall with that full count
and preserve every backing byte. Empty operations must succeed without access.
Malformed final groups after a valid complete prefix check whole-backing
atomicity and error precedence over short aliased output. The noncanonical
sextet index, invalid symbol index and malformed padding index are checked.

Other partial overlap is outside the public contract. The fixture does not
invent address comparisons or promise a recoverable overlap error. Disjoint
and supported exact-alias cases are the only admitted storage relationships.
Borrowing does not enforce this physical discipline.

## Protected extents and no speculative access

One 8192-byte allocation supplies two native 4096-byte pages. The second page
is protected with PROT_NONE before every codec phase. Each guarded raw slice
honestly covers two leading canaries and exactly its selected payload length;
the raw slice and selected payload end immediately before the guard page.
No raw slice in a positive access test overclaims inaccessible storage.

For all four profiles and all eleven input lengths, encode is checked with
either its input or output at the guard boundary; decode is checked with
either its wire input or binary output at the boundary. The other buffer has
independently checked logical outside sentinels and a nonzero View start.
The guarded exact-alias phase starts input/output at the same selected byte,
checks short-capacity atomicity, then exact-fit encode and shrinking decode.
Guards catch overreads and overwrites beyond complete groups and short tails.
Different counts put raw buffers at several actual byte alignments.

The null-backed phase rejects negative start/length or overflowing start+length
for either View before byte access. A valid empty View at start i32::MAX
succeeds. An admitted logical source over null backing is used only when
capacity or structural length rejection guarantees no payload access: encoding
a one-byte source into empty output returns the complete required count;
decoding a one-symbol wire returns InvalidLength in every profile. Malformed
output metadata must precede validation of a nonempty null-backed input.
These are no-access witnesses, not arbitrary-pointer safety claims.

The Rust driver traces all syscalls and requires no host operation inside any
P/p phase. Outside phases it accepts only process entry/exit, explicit markers,
one successful 8192-byte mapping, one protection of exactly its second page,
and one matching complete release after all seven phases. Strict x86_64 ELF
and shared jump admission precede executable publication. The positive native
lifecycle is bounded to 15 seconds.

CPU-only controls checked all 44 profile/prefix literal wires against Python's
Base64 functions, decoded those independent expected wires, checked all 17
possible guarded payload extents through the largest 16-byte wire, and checked
the noncanonical last-group witness. These checks are not native receipts.

## Retained physical-backing preconditions

| Retired fixture | Checked replacement |
| --- | --- |
| `core_base64_bounds.lani` | `read_overclaim.lani` |
| `core_base64_output_bounds.lani` | `write_overclaim.lani` |

The replacements deliberately provide one actual native backing byte while
claiming a four-byte View. The reader has a valid initial alphabet symbol and
must reach a second physical access. The writer has one source byte and a
logically sufficient four-byte destination. Both are expected to trap with
exit 101 under the current native physical-bounds contract, with a five-second
process limit each. They violate a caller precondition. They do not promise
recoverable Bounds, rollback after a trap, or safety for arbitrary pointers.
A writer can have touched backing before a physical trap.

Accepted executable evidence is restricted to finite Linux x86_64 CPU output
from the GPU compiler, native descending and packed byte layouts, and the
4096-byte base-page profile. GPU-device execution, unrelated targets, arbitrary
overlap and formal verification remain unclaimed.

| Executed source | SHA-256 |
| --- | --- |
| `contracts.lani` | `1896ebb82e1138b43431ca04d52f97c4b8b0c9e0176b0a931275306931802820` |
| `read_overclaim.lani` | `2c6dabbc797475b9c57f86850a5c73f751e822a963586cdb7fbbeb394e611c30` |
| `write_overclaim.lani` | `4a3069045587590901242023aeb414af534f45ba8a4d0f4a7eb30f973954ae34` |
| Rust driver, tested before formatting | `edbdf3910412c83a9797713a12e2ee82246479ef951cc5d30ef569b1f6fca9c7` |

```text
cargo test --test stdlib_base64_boundary_execution checked_base64_respects_exact_aliases_strides_guard_pages_and_atomic_failures -- --exact
cargo test --test stdlib_base64_boundary_execution checked_base64_logical_overclaims_preserve_the_physical_backing_precondition -- --exact
```
