# Lazy map owner recovery

The two probes compile through the GPU compiler's native-link path and execute
as Linux x86_64 programs. Both use independently owned String keys, borrowed
Text queries, and values containing an owned Vec and String.

Each probe verifies a full-map hit without initialization or source allocation;
the update returns an error report while its latest value descriptor remains
installed. An owned initializer error stays usable after map destruction.
A rejected key returns its candidate intact, and the probe releases that
candidate before continuing.

The baseline then reaches four allocations: candidate key, vector, label, and
table growth. The oracle derives their actual mmap ordinals and injects one
ENOMEM at each. Partial initializer failures clean their completed owners;
table-growth failure returns the complete candidate with the same pointers and
contents. Every failed call preserves the previous map, and each process retries
successfully. Storage failure retries with the recovered candidate itself.

The current `native_c/source_allocations.py` verifier identifies exact source
allocation sites. The shared `temp_file/ledger.py` checks requested lengths,
flags, full-width addresses and matching releases under `LANIUS_ALLOC=mmap`.
Native and CRT mappings are explicitly outside the source-owner balance claim.
Fourteen host-only controls check the phase observer and deliberate ledger
corruptions, including the current CRT terminal cleanup distinction.

Both native selectors pass, one Rust test each:

| Map | Receipt under `target/stdlib-work/` | Test time |
| --- | --- | ---: |
| HashMap | `lazy-map-hash-owners-final.log` | 7.86 s |
| TreeMap | `lazy-map-tree-owners.log` | 7.85 s |

Each Rust assertion requires the oracle's exact result:
`cases=5 reached=4 recovered=4 balanced=yes`. That is one baseline and four
individually reached allocation denials per map, with successful recovery in
all four failed processes. The probes cover these selected source allocation
sites, not every possible allocation or native-library owner. Fixture-only
match expressions and null-pointer annotations were corrected before the final
runs; neither the map implementation nor compiler changed for those fixes.
