# Vector transfer resource and scale gates

Driver: `tests/stdlib_vec_transfer_resources_execution.rs`.
Contract: `docs/library-vector-transfer-plan.md`.

All three native selectors passed at the frozen hashes below, recorded in
`target/stdlib-work/vector-transfer-resources.log`: 3/3 tests in 12.52 seconds,
after a 1.90-second Rust build. Root performed execution. Independent read-only
resource review passed at the same driver and producer hashes; it added no
native runs. Rust formatting and a host-only control of the fixture sequences,
owner counts and complete output sizes also passed.

## Native receipts

The accepted run observed three baseline processes and three additional
denial/recovery processes:

- Nested transfer: seventeen entries, thirty-four actual inner owners, all
  340 payload bytes, and thirty-nine exact allocations and releases. Native
  process time was 0.008633 seconds; compilation took 1.734160 seconds.
- Fault baseline: all three operation cycles completed, with 109 successful
  allocations and releases. Native process time was 0.016829 seconds;
  compilation took 7.129254 seconds.
- Reached append-growth denial at `mmap` 37, split denial at `mmap` 73 and
  extraction denial at `mmap` 109 preserved old views and recovered using the
  same owners in the same process. Each process had 109 successful allocations
  and matching releases. Native times were 0.016848, 0.014701 and 0.014685
  seconds, respectively.
- Scale: all 532,480 values and 4,259,904 output bytes matched, with twelve
  exact allocations and releases. Native process time was 0.369045 seconds;
  compilation took 3.183870 seconds.

Native times include tracing, process startup, construction, checks and
publication. They are separate from compilation and do not measure isolated
transfer throughput or establish a speedup over another implementation.

## Nested ownership and reuse

Selector:
`vector_transfers_conserve_nested_owners_and_reuse_empty_donors_without_hidden_cleanup`

`nested.lani` constructs seventeen entries, each with an actual eight-byte
`Vec<u8>` and twelve-byte `String`. Pointer snapshots are scalar observations,
not additional cleanup owners. Every observation checks both inner allocation
identities, capacities, lengths and all twenty payload bytes per entry.

The sequence takes a nonempty source and a reserved-empty owner, extracts seven
middle entries, splits a five-entry suffix, and rebuilds the original sequence
through consuming appends. It then reuses the emptied destination and donor,
and takes the final owner. All appends in this selector fit the existing
capacity and must perform no host effects. Each emptied donor retains its
original backing and capacity; each taken source becomes `(0,0,0)`.

After explicit retirement of the empty containers, all thirty-four inner
owners and exactly the final outer owner must remain live for every output
write. The host compares all 340 payload bytes with independent formulas.
Cleanup releases each inner allocation once and the final container last.
The expected observation is four pure phases and thirty-nine exact successful
allocations and releases.

## Reached allocation failure and same-owner recovery

Selector:
`vector_transfer_allocation_errors_preserve_existing_views_and_recover_same_owners`

`faults.lani` has three baseline cycles: append from a fourteen-entry donor into
a three-entry destination that must grow; split seventeen entries at seven;
and extract `[4,13)` from seventeen entries. Each entry has the two actual
inner owners described above. Invalid range admission also occurs inside a
phase that forbids host effects.

The driver selects each operation's sole reservation from its successful
baseline trace, then runs three additional processes denying those reached
sites. An error must preserve all source and destination fields, capacities,
initialized entries and inner identities. Only on that error path does the
fixture reread every entry through the captured old views. It then retries
using the same actual owners and checks the complete result. Old views are
never read after successful mutation.

The trace checks the normalized setup and operation prefix before each denial,
the exact unchanged live owner set on return, and successful recovery. No
allocation or release beyond the one required outer reservation is permitted
inside an operation; successful append may release its replaced outer backing.
Nested payloads must survive unchanged until explicit caller cleanup. Each
process emits 1,020 payload bytes plus three sixteen-byte capacity headers and
has 109 successful allocations with matching releases. A denial adds one
failed reservation, not another successful owner. This is one baseline plus
three denial processes, covering the actual reservation in each operation;
there is no invented allocation failure for `take` or no-growth append.

## Typed scale and complete values

Selector:
`vector_transfer_scale_checks_complete_packed_and_composite_values_after_linear_range_work`

`scale.lani` uses 4,096 and 262,144 entries in both packed `i32` and a descending
record layout with `id:i32` and `checksum:i64`. Each source reserves seventeen
extra entries so logical length cannot stand in for physical capacity.

Every cycle extracts the middle half, splits the retained suffix, consumes
both result owners back into the original source, then takes that owner. Full
order and values are checked after each stage. The emptied intermediate
containers are explicitly destroyed before final validation and publication.
The original allocation and capacity remain the final owner throughout.

The host independently checks all 532,480 values: each identifier and every
byte of `id * 1,000,003 + 17` for the composite records, including its high
bits. Total output is 4,259,904 bytes including four sixteen-byte capacity
headers. Publication uses fixed 1,024-byte stack scratch, not another heap
owner. There are twelve exact allocations and releases across four cycles.
The large middle extraction and bounded runtime expose repeated-removal
quadratic work; they do not prove asymptotic complexity or a compiler speedup.
Native process time is reported separately from compilation and includes
tracing, construction, checks and publication. Each native process has a
fifteen-second timeout.

## Layout and trace evidence

`core::mem` defines packed `u8` as one byte and packed `i32` as four bytes.
Other record fields occupy native eight-byte words. `Vec<u8>` has three such
fields; `String` contains one `Vec<u8>`. Thus each nested Entry occupies six
words, or 48 bytes. The scale record occupies two words, or 16 bytes, while
its explicit output serialization contains twelve bytes.

Setup extents follow explicit caller capacities. New outer reservation
extents are checked against the returned owner's capacity times its
source-derived element size, with the required logical count as a lower bound.
The ledger therefore checks exact extents without fixing an incidental result
capacity or growth factor. It tracks full-width addresses, rejects overlapping
owners, unknown/repeated releases and wrong extents, and checks the exact live
owner set at every publication. Every actual inner owner has one observed
release. All allocations must be retired before the completion marker;
process exit is not cleanup evidence.

Artifacts must be ELF x86-64 and pass the shared complete jump validator.
Full syscall tracing admits only launch, the fault fixture's initial mode
byte, protocol markers, selected allocations/releases, output writes and
successful exit. Pure phases forbid every other host effect.

These gates target Linux x86-64 CPU output from the GPU compiler. They do not
establish user-program GPU execution, other targets, automatic ownership
checking, alias detection or formal proof. Direct/model gates separately cover
ordinary boundary, overflow and zero-sized-count cases. The resource scope is
valid disjoint owners, manual lifetime transfer, the three reached allocation
sites and the selected large typed workloads.

## Frozen hashes

- Driver: `d0cf10ee814e9a0339c13e276d62dad7dc51230432fab7bad5e98b1d109ffaa3`
- `fixture/support.lani`: `6f137690a40d49a04d98c0d9cdf06b0e5b99b232a7667b33718ae577095da8d1`
- `nested.lani`: `5597cdd0f400d42c56d80c04a875948642757f37108ac5b0d05467b2be0b43e2`
- `faults.lani`: `f5eeede698ab096e015d7eac474f48c0579c2e1595828accdd806a3442b49189`
- `scale.lani`: `f9ca8a343cbac9293a7859409b94c3879562497f3f73657a7c8f9afa3b7d9b8a`
