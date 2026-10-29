# Form resource gates

Driver: `tests/extended_form_resources_execution.rs`.
Contract: `docs/library-form-plan.md`.

All four resource gates passed on their first native invocation, recorded in
`target/stdlib-work/form-resources.log`: 4/4 tests in 15.47 seconds after a
2.06-second Rust build, with exit status zero. Root performed the execution.
The run includes four successful baselines and six separate reached-denial
processes; each denial process recovered in the same process.

## Native receipts

- Borrowed views and encoding passed both 256- and 16,384-pair workloads,
  comparing all 266,238 output bytes with eight exact allocations and eight
  matching releases across both cycles.
- Owned parse reached denials at `mmap` 3 (site 0) and `mmap` 4 (site 1).
  Both recovered all 257 pairs. The executions observed four and five
  successful allocations, respectively, with matching exact releases; the
  late failure retired the partial document before returning an error.
- Append reached denials at `mmap` 6 (site 0) and `mmap` 7 (site 1).
  Both preserved the original 257 pairs and recovered to 258 pairs. Each
  execution observed seven exact allocations and releases. The late failure
  retained the successful byte reservation, as the contract permits.
- Owned encoding reached denials at `mmap` 4 (site 0) and `mmap` 12 (site 8).
  Both preserved all three source owners and recovered the complete
  262,143-byte output. The executions observed twelve and twenty successful
  allocations, respectively, with matching exact releases.

Independent source/driver review passed at the frozen hashes below. A
host-only arithmetic check also confirmed the fixture's byte counts and
expected wires. The native receipts establish execution only for the selected
workloads and target described here.

## Selected observations

The input repeats fourteen-byte fields whose decoded names vary through
`kA` to `kZ`. Values contain space, NUL, `0xff`, a literal malformed percent
sequence and a varying digit. Each pair has eight decoded bytes and sixteen
canonical wire bytes including its separator; the final separator is absent.
The Rust output oracle independently serializes decoded pairs using the form
safe-byte rules. Every canonical output byte is compared.

### Borrowed backing and encoding

Selector:
`borrowed_form_views_and_encoder_preserve_real_backing_without_allocation`

`borrowed.lani` uses 256 and 16,384 pairs: 3,584 and 229,376 encoded input
bytes, 2,048 and 131,072 decoded bytes, and 4,095 and 262,143 output bytes.
Each cycle owns separate encoded bytes, decoded bytes, span descriptors and
fixed output scratch. The byte owners have three leading and four trailing
guards; the selected span view has an actual guard descriptor at each end.
Scratch is 4,105 bytes with a 4,093-byte writable window.

Pure phases cover parsed cursor copies and early retirement, full traversal,
component decoding, exact encoded sizing, invalid/zero reads, independent
encoding copies, full chunked output and fused EOF. The full encoded input,
decoded bytes, span descriptors and guards are checked afterward. Setup and
explicit caller cleanup account for exactly four allocations per cycle.
There is no allocation-failure injection into borrowed operations.

### Exact two-buffer parse

Selector:
`owned_form_parse_releases_partial_buffers_and_recovers_after_both_reached_failures`

`parse.lani` owns a guarded 257-pair encoded input and fixed scratch before
calling owned parse. The successful operation allocates exactly 2,056 decoded
bytes and 6,168 descriptor bytes. Each of these two reached reservations is
denied in its own process. A failed second reservation must release the first
buffer before returning an error; neither failure may release source backing.
The same process checks all input bytes and retries successfully.

The original input is then explicitly destroyed. All decoded pairs, packed
bytes, spans, cursor counts and the complete 4,111-byte encoding are checked
while only the independent document and scratch remain. Final caller cleanup
retires the two document owners and scratch exactly once.

### Append with sequential reserves

Selector:
`owned_form_append_keeps_logical_contents_through_sequential_reserve_failures`

`append.lani` starts from the exact-capacity 257-pair parsed document and one
separate guarded append-input owner. All earlier document borrows end before
each attempt; append inputs are disjoint from the document. The next pair
requires byte capacity 4,112 and span capacity 514 (12,336 bytes).

The baseline selects the reached byte and span growth reservations. Failure
at the first retains both original buffers. Failure at the second retains
the newly installed byte buffer and the old span buffer. Both cases preserve
every existing logical byte and pair. Same-owner retries publish exactly one
new pair; the second case reuses the retained byte capacity. Complete output
is 4,127 bytes. A later clear and append reuse both capacities inside a pure
phase, with no allocator effects.

This checks logical atomicity, not pointer/capacity stability after error.
Original encoded input, separate append input and scratch remain intact.
Baseline and both recovery executions each perform seven successful
allocations and seven exact releases.

### Owned output collection

Selector:
`owned_form_encode_cleans_partial_output_and_recovers_without_changing_document`

`encode.lani` uses the 16,384-pair document. Setup retains only three source
owners: guarded encoded input, 131,072 packed decoded bytes and 393,216
descriptor bytes. Negative output-limit rejection occurs in a pure phase.
The first and final reached collector allocations are selected from a
successful encoding baseline; each denial run checks the complete prior
effect sequence, temporary cleanup before error, all source contents and a
successful retry in the same process.

Successful output is an independent 262,143-byte ASCII String. The Form and
original input are destroyed first. Every output byte is checked again and
published before the String's explicit final release.

## Exact storage accounting and limits

`PairSpan` in `extended/ext/form.lani` has three `i32` record fields.
`core::mem::size_of` defines record size as eight bytes per native scalar
word, so each span occupies 24 bytes, not twelve. `alloc::vec` allocates
element size times capacity. Packed `u8` owners use one byte per element.
Parse reserves exact admitted counts; append doubles the selected capacities
within configured limits. These source contracts establish the expected
extents independently of a native trace.

Executables must be ELF x86-64 and pass the shared complete jump validator.
Full syscall traces admit launch, a single mode read for fault fixtures,
protocol markers, selected allocator effects, output writes and final exit.
Pure phases reject every other host call. The live ledger retains full-width
addresses and exact extents and rejects overlap, unknown or repeated release,
incorrect release size, and destruction of protected source owners. It must
be empty at the explicit completion marker; process exit does not establish
cleanup. Each fault is bound to a reached successful baseline site and its
complete normalized effect prefix.

Each native process has a fifteen-second timeout. There are four baselines
(the borrowed baseline contains two sizes) and six denial/recovery executions.
The intended target is Linux x86-64 CPU output from the GPU compiler. This
does not claim device execution, automatic lifetime enforcement, proof,
exhaustive collector-allocation coverage or arbitrary overlapping append input.

## Frozen sources

- Driver:
  `b8a932281c7507a4278c15e1c9314e0ea2f30850cff02971347f4229a3f40932`
- `fixture/support.lani`:
  `bb2dbd50d5540929e366d286f2f2bef82b9c71e249236dbebd9f63fafe2e38c2`
- `borrowed.lani`:
  `1c1ef05cc9f002db89cb8c5d607c11d515ffdf6efac4d32e80c506ef5d74936b`
- `parse.lani`:
  `99646f5c7101dea87bb3bf3cc43950451264abba8b6007fde453b6644a5126c7`
- `append.lani`:
  `f5f5f354a91f1e287a62e9a4a43e6691533b33bd8eaab1cb47650d2b3b527d44`
- `encode.lani`:
  `1969df3b71e7f83e51f5b94e74a92bc5b3724a5b0c329d81c61c47dc687202ac`
