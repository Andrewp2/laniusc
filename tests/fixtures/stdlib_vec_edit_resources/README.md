# Owned vector editing: resource and scale gates

All three native gates passed together in 8.75 seconds at the frozen hashes
below. Root executed them and recorded the results in
`target/stdlib-work/vec-edit-resources.log`. Independent read-only resource
review passed on the same driver and producers without requesting changes or
additional runs. The small host-only analytical control also checked the
expected survivor sequences, output lengths and source-derived extents.

## Selectors

All three selectors live in `tests/stdlib_vec_edit_resources_execution.rs`:

- `vector_owned_edits_destroy_nested_owners_once_and_reuse_original_backing`
- `vector_owned_edits_zero_sized_values_have_logical_counts_and_no_allocations`
- `vector_owned_edits_large_multiword_compaction_preserves_every_survivor_without_growth`

The driver imports the real `alloc::vec` implementation, admits x86-64 ELF and
uses the shared emitted-jump validator before execution. Each native subprocess
has a 15-second bound. Root alone runs Cargo, compiler and native commands under
the repository's serial lock and outer 100-second command ceiling.

## Accepted native receipts

| Gate | Observations | Native seconds | Compile seconds |
| --- | --- | ---: | ---: |
| Nested owners | 30 elements, 60 inner owners, 7 edit phases, 2,188 exact output bytes; 62 exact maps/releases | 0.018938 | 6.613545 |
| Zero-sized elements | 17 retain calls, 11 stateful comparisons, 8 equality comparisons, 26 destructor calls; 6 phases, maximum-count no-op, zero allocations | 0.006625 | 0.884105 |
| Typed scale | 4,096/65,536 input elements, 59,482 complete record observations, 951,880 exact output bytes; 12 phases, 2 exact maps/releases | 0.068286 | 1.141360 |

These receipts represent three registered tests and three native processes in
one invocation, with no failed attempts or reruns. The log reports no separate
Rust harness build duration. Native durations include process and strace
overhead, fixture setup, checks, output and explicit cleanup. They are finite
acceptance observations on the selected host, not untraced kernel benchmarks
or evidence about other compiler/driver combinations.

## Ownership and effects

`nested.lani` constructs 30 distinct compound elements, each owning an eight-byte
`Vec<u8>` and a twelve-byte `String`. The edited vector starts with 24 elements
and capacity 257; a separate capacity-nine vector holds six refill elements.
The custom `Destroy` checks both complete payloads and original allocation
identities, records the removed identity, then destroys each inner owner once.
Predicates record their actual operands in a fixed stack tape without acquiring
ownership. No cursor or old view survives an edit.

The short sequence retains, deduplicates by key, truncates, clears, moves the
six precreated refill elements into the original backing, uses natural partial
equality deduplication, then clears again. It checks every survivor's metadata,
pointer and byte payload after each operation. The host independently checks
all 2,188 output bytes, including the 74-entry callback/destruction tape. The
expected final destruction releases 60 inner allocations and the two original
container allocations; process exit is not cleanup evidence.

The exact extent derivation follows current `core::mem` native record layout:
`Entry` has three scalar words, two three-word descriptors and one reference,
or ten eight-byte words. Its outer extents are therefore `257 * 80 = 20,560`
and `9 * 80 = 720` bytes. Packed inner byte allocations are exactly 8 and 12
bytes. This does not assume C-style packing of `i32` record fields.

`zero_sized.lani` uses an inhabited empty type with explicitly observed callback
and destruction markers. It expects 17 retain calls, 11 stateful comparisons,
8 partial-equality comparisons and 26 destructor calls, including refill and
clear. A separate empty type with an effect-free destructor provides a valid
zero-byte descriptor at `i32::MAX` logical length: maximum-length truncation
and negative-length rejection must finish without iteration, allocation or
destruction. This does not claim billions of pushes occurred. All zero-byte
backing and logical capacity checks are explicit.

The syscall ledger observes every native syscall. Before sealing it admits
only expected anonymous mappings; after sealing it rejects all allocation.
During editing it admits only the exact expected inner releases or the
explicit zero-size instrumentation markers. It tracks full-width addresses,
exact extents, nonoverlap, release order, and the complete remaining owner set
at every phase boundary and every stdout write. Final cleanup must empty the
ledger before completion and exit. The methods have no allocation failure path,
so there is no artificial OOM campaign.

## Scale scope

`scale.lani` fills 4,096 and 65,536 four-word records. Each has independent id,
key and 64-bit checksum fields plus a reference to instrumentation. It retains
two of each three records, deduplicates eight-record key groups, truncates to
half those groups, clears, refills three records and clears again. Capacity is
`4 * initial_length + 17`, so every edit must use the original capacity-anchored
typed layout while the logical length changes substantially.

The host checks all 59,482 emitted record observations and all 951,880 bytes.
The only allocations are the two original backings, exactly 524,832 and
8,389,152 bytes. Predicate, comparison and destruction totals and the destroyed
id sum are checked inside the program. All twelve edit phases must have no
host effects. The representative large workload and finite native bound expose
accidental repeated-removal compaction; they are not a general complexity proof
or a compiler/engine performance claim. Reported native timing includes process,
tracing, setup, validation, publication and cleanup, separately from compilation.

## Frozen sources

| File | SHA-256 |
| --- | --- |
| Rust driver | `6d3f1e2a004ed405f17708aecc258a6e1e5d484e65a3fddb71c316ca9f3d50fb` |
| `nested.lani` | `b8dd343d3eb089f052687888647fb80b02014f16f4162744dbf14ec27062510a` |
| `zero_sized.lani` | `149cb5919d1af7928e3a6c9c5d5dced20222103fe5874c62fc7bbb184223dc3c` |
| `scale.lani` | `615f304056ee511b717043e1b4c44288e2f0a0142f8aee58b14b9dd9318f124b` |
| `fixture/support.lani` | `335e51f33e2e498634d6708e50831d95a6e38eeb178792909323c233d0779899` |

Verified execution profile is native Linux x86-64 produced by the existing GPU
compiler. These gates make no claim about executing library programs on a GPU,
implicit ownership checking, callback unwinding, or formally verified behavior.
