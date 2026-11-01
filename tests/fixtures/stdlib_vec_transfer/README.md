# Vector transfer direct contracts

The authoritative API and ownership rules are in
[`docs/library-vector-transfer-plan.md`](../../../docs/library-vector-transfer-plan.md).
The fixtures call the production `alloc::vec` methods. Independent stateful
models, reached allocation failures, large workloads and the CSV application
have separate drivers and receipts.

## Registered groups

`tests/stdlib_vec_transfer_execution.rs` registers four executable groups:

- `vec_transfer_all_methods_execute_tiny_composite_admission`: a generic helper
  transfers a trait-free record containing i32, full-width u64, Option<bool>
  and a nonempty byte array through take, split, extraction and two appends.
  Complete field values and final order are asserted. Source reset, original
  allocation transfer, donor capacity retention and independent source reuse
  are observed with actual unequal capacities 7/2/1. Four mappings are released.
- `vec_transfer_ranges_capacity_empty_noops_and_bounds_execute`: reserved-empty
  take and reuse; seven empty/prefix/middle/suffix/full ranges; splitting at
  zero, an interior index and length; independent result storage; ordered
  reconstruction; append with spare capacity, required growth, vacant and
  pre-reserved empty destinations. Donors retain their allocation and can be
  reused. Invalid bounds preserve full contents, pointers, capacities and
  existing views. Empty ranges/donors preserve old views; both old and fresh
  reads are compared with independent expected values. The finite profile
  allocates and releases exactly 31 mappings.
- `vec_transfer_typed_layouts_and_nested_owners_execute`: the generic transfer
  sequence executes for packed u8, descending bool, nonempty u64 arrays and
  nested Option<Result<array, tagged error>>. Actual stride signs are asserted.
  A small compound owner holds a UTF-8 String (including NUL) and Vec<u64>.
  Every nested pointer/value survives transfers without cloning or destruction.
  The reset source is independently reused. A popped item grows both nested
  resources before cleanup; no borrowed descriptor is mutated while its
  containing vector still owns it. Each nested owner is explicitly retired
  once. All 26 observed mappings are released.
- `vec_transfer_zero_sized_maximum_counts_and_overflow_execute_without_allocation`:
  ordinary public operations first create small Unit owners. A separate
  explicitly constructed valid maximum-length Unit owner exercises checked
  overflow, error preservation, empty boundaries, large extraction, append,
  split and take through descriptor-only operations. Distinct empty/Unit
  owners legitimately share a null storage pointer. No allocation or other
  host work is permitted, and the native time bound rejects accidental
  billion-entry transfer loops.

The maximum Unit fixture is a valid state constructor:
`Vec<Unit>{storage:null,length:2147483647,reserved:2147483647}`, using
a prior `let null:ptr=0` binding. Unit has one
inhabited empty value, size zero and no resources; all initialized entries
require zero backing bytes. This is not a claim that billions of pushes were
executed, nor permission to forge nonzero-sized backing or invalid metadata.
The frozen contract and root explicitly authorize this arithmetic/descriptor
witness. No existing resize or storage helper is changed to construct it.

No transfer adds trait bounds; positive generic helpers use types without
Clone, Destroy, equality or ordering capabilities. Self-append, copied owner
aliases and overlapping backing violate the API's explicit caller precondition
and are not executed as if rejection were guaranteed. All ordinary owners in
these tests are live, disjoint and valid. Fallible allocation tests belong to
the separate resource gate.

## Observation and target scope

Fixtures compile through the GPU compiler to Linux x86_64 CPU programs, pass
strict ELF/shared in-function jump checks, and execute with a 15-second child
bound. Complete syscall traces allow only successful launch/exit and matched
mmap/munmap lifetimes. The ledger checks full-width addresses and requested
lengths, exact finite allocation counts, no live mappings at exit and empty
stdout/stderr. The zero-sized fixture allows no mappings at all.

Contents, logical counts and specified retained capacities are behavioral
contracts. Exact small result capacities in generic admission are observations
of this native profile used to exercise differing typed-storage layouts; they
do not establish a portable padding or raw representation contract. No raw-byte
copy or implementation loop is used to calculate expected vector contents.

This evidence does not establish another host, user-program GPU execution,
enforced lifetimes, implicit element destruction, panic cleanup or formal
verification. Root alone runs compiler/Cargo/native commands serially under
the shared library lock, with every outer command bounded to 100 seconds.
This fixture owner edits only the direct driver/fixtures and runs no native
or compiler commands.

## Receipts

- Tiny admission passed 1/1 in 4.89 seconds; the separate Rust build took
  37.16 seconds. All four matched allocation lifetimes were released.
  Log: `target/stdlib-work/vector-transfer-admission.log`.
  Tested sources: fixture `9387c039...`, driver `976fd504...`, production Vec
  `d1c9d25d...`. All four selectors already existed in that driver, so the
  other three were filtered from this invocation.
- After tiny acceptance, only the remaining positive groups' allocation bounds
  were narrowed to their exact finite counts, 31 and 26. Tiny source, helper
  and expectations remain unchanged.
- The remaining run finished with 1 passed and 2 failed in 10.01 seconds
  (separate Rust build 1.91 seconds). Range/capacity/bounds contracts executed
  successfully with all 31 matched lifetimes released. Types and zero-sized
  fixtures failed compilation with LNC0006 because untyped zero literals in
  pointer arrays and the Unit owner storage field were inferred as i32.
  Log: `target/stdlib-work/vector-transfer-direct.log`. This run supplies no
  execution claim for those two fixtures.
- Only the literal pointer typing was corrected: each fixture now introduces
  a typed null binding. Expectations, accepted fixtures and driver remain
  unchanged. The focused retry passed both groups (2/2) in 9.03 seconds
  (separate Rust build 0.19 seconds), with all 26 typed/nested mappings
  released and no allocation or other host work in the maximum Unit fixture.
  Log: `target/stdlib-work/vector-transfer-direct-retry.log`. Corrected
  sources are types `2f2233fc...` and zero-sized `94e21158...`; production
  remained `d1c9d25d...`. These were fixture authoring corrections, not compiler
  or library changes.
- Independent review accepted semantic conservation, independent no-op/error
  observations, nested owner lifetimes, valid maximum Unit states and exact
  allocation counts. Source review is distinct from runtime acceptance.
- All four registered groups are accepted across the tiny, mixed and focused
  retry runs. No accepted group was rerun, and no source change followed the
  final acceptance.

## Frozen sources

| Source | SHA-256 |
| --- | --- |
| `tests/stdlib_vec_transfer_execution.rs` | `a2c189fb76a0deacf6ce80d812c410d212e604f518d7d77cf2e41fadea0d962c` |
| `admission.lani` | `9387c0395fe7a5c97a1e2a1c62cd65f9e7a677fd90c313787bd554e6b6c011cc` |
| `contracts.lani` | `977cf4152da6f280cdc3059c7326730ec6303a34ffc5e78fa6ae316e54fcfe1f` |
| `types.lani` | `2f2233fc0f6d1e20e988d07e19677625342812c36d7fded3d530bd0d750430da` |
| `zero_sized.lani` | `94e21158cd77e1a94e7c712c8280fb8ac415f0a7c318cf76752ea027059d0d92` |
