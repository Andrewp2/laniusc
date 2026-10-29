# Vector ownership transfer model

This fixture checks the four operations in the
[vector transfer contract](../../../docs/library-vector-transfer-plan.md):
`take`, `try_append`, `try_split_off` and `try_extract_range`. All actual
container behavior executes in Lanius. Python supplies a test-only semantic
model and transcript verifier; Rust supplies the focused compiler/runtime gate.

## Independent state and allocation policy

The reference keeps four ordered Python lists plus introduced/retired entry
ledgers. Whole-owner transfer moves one list, append concatenates and empties
the donor, and split/extract use list slicing. It does not reproduce typed
storage loops, compaction, reallocation or geometric growth.

Every action records the actual result and all four complete vector states:
length, capacity, backing address, signed physical stride, empty flag and every
initialized element. The verifier compares exact list contents and payloads,
then checks capacity/address transitions against the public contract:

- `take` preserves the old allocation/capacity and resets its source completely.
- Append retains donor allocation/capacity. Empty donors preserve both owners;
  sufficient destination capacity preserves that allocation/capacity.
- Split/extract retain source allocation/capacity. Nonempty results have at least
  the removed count of capacity and independent backing. Empty results have
  zero capacity and null backing.
- Errors preserve participating descriptors, values and saved views. Existing
  push/reserve/shrink operations provide bounded setup and subsequent reuse.

No exact geometric rounding or exact nonempty extraction capacity is assumed.
Two host-only synthetic allocation policies, minimal capacity and larger power
of two capacity, are both accepted. Synthetic transcripts exercise the verifier;
they do not provide native expected values. Actual allocation addresses are
opaque observed identities, checked for required stability and nonoverlapping
live extents. They are not compared with predetermined addresses.

## Corpus and ownership signal

Seed: `0x7ec7a0261114`. There are **56 cases of 64 actions**, totaling **3,584
actions**. Twelve composed schedules run with each of four element shapes;
eight schedules also run with a zero-sized type:

1. Packed `u8` values, stride +1.
2. Packed `i32` values with signed/high-bit payloads, stride +4.
3. A descending composite record containing a wide integer, `Option<bool>`,
   a fixed array and `Result<u64,i32>`. Every field, array cell and enum payload
   is compared, including None/false/true and both Result variants.
4. Descending records containing an ID and a real owned `Vec<u8>`. Every inner
   byte, capacity and allocation identity is observed throughout transfers.
5. True zero-sized entries with stride 0 and the existing positive-reservation
   capacity of `i32::MAX`; these cases compare logical counts, not distinct
   per-entry identities that a zero-sized value cannot contain.

Schedules combine populated and reserved-empty takes, allocated-empty donor
append, exact and spare capacities, growing append, prefix/interior/suffix/full
extraction, splitting at zero/interior/length, invalid negative/reversed/past-end
bounds, order changes, retirement and immediate reuse. Requested setup capacities
include 0, 1, 2, 3, 4, 7, 8, 9, 15, 16, 17 and 31. Deterministic random suffixes
choose among live owners and available result slots. Bounds are 48 live entries
and 200 introduced IDs per case; the fixed corpus stays within them.

The fixed semantic summary includes:

- **787 introduced entries**, including **170 real nested byte-vector owners**.
- **3,698 moved entries** across **913 nonempty transfers** and **397 documented
  empty transfers**.
- **242 bounds errors**, **112 reserve capacity errors**, **1,049 saved-view
  observations**, and **28,352 complete snapshot entries**.

Progress assertions require both growing and spare-capacity append, substantial
nonempty transfers, real errors and nested owners. Saved views are read only
after rejected calls or documented empty no-ops. No stale borrowed view is read
after a successful mutation.

After every action, live entries plus explicitly retired entries equal all
introduced entries. For nonzero-sized shapes, unique IDs and complete payloads
make loss, duplication and reordering observable. Nested owners retain their
original allocations across moves. Retirement pops each value, emits it, then
destroys its nested storage once. Final cleanup drains all four vectors and
checks their completely reset descriptors. Returned owner descriptors are
installed only in empty reset slots; the temporary returned handle then stays
inactive. There are no self-appends, shallow owner aliases or invalid overlapping
owners in the input corpus.

The script's `clear` label means explicit repeated `pop` plus per-entry cleanup,
retaining the outer allocation. It does not call the shallow `Vec.clear` method
on live nested owners. The `destroy` label performs the same retirement and then
destroys the empty outer vector.

These observations establish finite state/ownership evidence, not a syscall
allocation audit. The separate resource suite checks reached allocation failures,
allocation identities/extents and cleanup. Maximum-length zero-sized operations
and append-overflow witnesses belong to direct/resource gates; this stateful
model keeps logical lengths bounded. Borrowed-entry lifetimes and exclusive
ownership remain caller obligations.

## Verifier controls and native gate

The host controls passed both legal capacity policies and rejected **27 deliberate
corruptions**: 17 protocol/state/payload fields, four specific transfer/error
capacity or independent-backing violations, truncation, trailing bytes and four
coherent wrong-order models. The latter reverse taken contents, appended donor
order, extracted result order or retained suffix order while continuing the
complete operation sequence. The minimal-capacity synthetic transcript contains
**1,871,224 bytes**; this is host-control evidence, not a fixed native allocation
transcript or an additional native execution.

```sh
timeout --kill-after=2s 90s python3 -B tests/fixtures/stdlib_vec_transfer_model/oracle.py controls
```

Native selector:

```text
--test stdlib_vec_transfer_model_execution vector_transfers_match_ordered_owner_states_payloads_and_capacity_contracts --exact
```

One binary corpus drives one native child. The protocol uses little-endian u64
words, explicit case/action counts, complete variable-length snapshots and an
end marker; every byte must be consumed. The Rust driver requires an x86_64 ELF
and the complete fixed textual summary. The Python verifier bounds the child at
75 seconds; the Rust harness bounds verification at 90 seconds. Native status
must be zero with empty stderr.

## Accepted native receipt

Root's corrected focused gate passed **1/1 tests in 9.42 seconds**, after a
separate **0.20-second Rust build**. The native process exited zero and the full
summary matched the fixed driver assertion:

```text
vec-transfer-model cases=56 actions=3584 created=787 nested_owners=170 moved_items=3698 nonempty_transfers=913 empty_transfers=397 bounds_errors=242 capacity_errors=112 saved_views=1049 snapshot_entries=28352 shapes=5 seed=0x7ec7a0261114
```

Receipt: `target/stdlib-work/vector-transfer-model-final.log`. Accepted SHA-256
sources:

- Producer: `bf71c4bdb2c0e7a5f04231187dd3c7365d36a5d75d344fa705ad315cbb90be0a`
- Oracle: `9c3f1ccb02e87442e9d4440ff627b9869e61e9cba879c02b79b84280f62003a9`
- Driver: `3cdb249f50b9312b6eed4baca2520898145999d988fd41626f40bf83784bd9d7`

The first attempt failed during fixture compilation with `LNC0072` at
`model.lani:88`, because the observer attempted a prohibited `ptr as usize`
conversion. Its gate reported 0 passed/1 failed in **3.94 seconds**, after a
separate **1.70-second Rust build**; no native model case executed. That receipt
is `target/stdlib-work/vector-transfer-model.log`, at producer
`851fa3e4e5b97b7495af070709ef2f3a70a68f45d257bedc574002c141afb405`.

The producer-only correction writes each pointer directly into one eight-byte
raw pointer slot, following the existing `std::linux::store_address` pattern.
It retains complete pointer identities and extent checks. The oracle, corpus,
driver and production vector code were unchanged. This was a fixture authoring
error, not a transfer implementation failure or a new compiler dependency.

Independent review passed the corrected producer and unchanged verifier. The
**27 host-only corruption controls** remain separate verifier evidence, not
additional native executions.

Acceptance applies to Linux x86_64 CPU output from the GPU compiler. These finite
checks do not establish GPU device execution, other hosts, formal correctness
or language-enforced ownership.
