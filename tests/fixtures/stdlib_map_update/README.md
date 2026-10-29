# Scoped map update direct contracts

The authoritative API and ownership rules are in
[`docs/library-map-update-plan.md`](../../../docs/library-map-update-plan.md).
These fixtures call the production HashMap and TreeMap `update_value` methods.
The independent operation model and live-owner/fault tests have separate owners,
drivers and receipts.

## Registered groups

`tests/stdlib_map_update_execution.rs` registers four groups:

- `map_updates_generic_compound_values_and_results_execute_tiny_admission`:
  both maps, generic Mapper and method forwarding, a record V containing
  Option<bool> and full-width u64 values, old V returned as R, and a nested
  Result error returned while the changed value is installed. Missing keys
  return None without callbacks. Exactly two map allocations are released.
- `map_updates_preserve_representatives_structure_and_exact_callback_lookup_effects`:
  deliberately colliding hash keys, deletion/tombstones, and tree
  insert/remove/free-list histories. Equivalent query keys have distinct
  representative tags. For each present/missing query, a separate ordinary
  get_entry supplies the exact hash/equality/order transcript; update must
  reproduce that prefix and append only one mapper event when present.
  Callback results, counts, stored representatives, all contents, pointers,
  capacity and public structural metadata remain checked. Exactly two
  pre-reserved map allocations are released.
- `map_updates_bool_array_and_zero_sized_shapes_execute`:
  bool values/results, nonempty three-word arrays, zero-sized V with bool R,
  bool V with zero-sized R, and simultaneous zero-sized V/R for both maps.
  The final shape deliberately exercises a zero-sized callback return; it
  must execute or produce a separately recorded compiler dependency. It is
  not silently replaced with a nonzero surrogate. The expected successful
  run allocates and releases ten independent maps.
- `map_updates_require_mapper_and_map_key_capabilities`: five source-local
  LNC0008 rejections for missing HashMap Mapper, TreeMap Mapper with the wrong
  replacement-value type, independent missing hash/equality key capabilities,
  and missing ordered-key capability. Executing positive controls live in
  the admission and contracts fixtures.

The contracts fixture also snapshots the complete concrete allocation before
and after each scalar update. Test-only source-shaped mirrors provide the
storage extent; the only permitted byte change is the unique old u64 value
word becoming its new value. This is an additional observation on the admitted
native representation, including unused cells. It is not a portable padding
or storage-layout guarantee. Any mismatch must be classified against semantic
key/structure preservation before production changes are considered.

## Execution and scope

Positive fixtures compile through the GPU compiler into Linux x86_64 CPU
programs, pass strict ELF and shared in-function jump checks, and execute with
a 15-second child bound. Complete syscall traces admit only one successful
launch/exit and the fixture's exact successful mmap/munmap lifetimes. The ledger
matches full-width base addresses and requested lengths and requires no live
mapping at exit. Stdout/stderr are empty; callback work is in stack memory.

This finite execution profile does not establish user-program GPU execution,
other target support, automatic ownership/lifetimes, panic recovery or formal
verification. Nested resource growth and callback allocation failures are
covered separately. These tests add no map implementation or compiler changes.
Root alone runs compiler/Cargo/native commands under the shared library lock,
with each outer command bounded to 100 seconds.

## Receipts

- Tiny generic admission passed 1/1 in 7.64 seconds (separate Rust build
  2.97 seconds), including the full host-effect/allocation ledger.
  Log: `target/stdlib-work/map-update-admission.log`.
  This run used admission `cdc01973...`, driver `eae6ba35...`, HashMap
  `259e6440...`, and TreeMap `fc671134...`.
- The driver later changed only the expected allocation count for the expanded
  shapes fixture from eight to ten. The tiny admission logic/source remains
  unchanged. Its current driver hash is recorded at final freeze.
- The remaining run finished with 2 passed, 1 failed in 9.06 seconds
  (separate Rust build 1.76 seconds): the bool/array/all zero-sized shape group
  executed successfully with all ten map lifetimes released, and the capability
  group passed all five negative fixtures. The contracts fixture failed
  compilation with LNC0006 at its inferred `with_capacity(16).unwrap()` tree
  constructor, so this run supplies no execution claim for that fixture.
  Log: `target/stdlib-work/map-update-direct.log`.
- The contracts fixture was corrected to supply explicit `<Key,u64>`
  constructor type arguments. Its focused native retry passed 1/1 in 6.88
  seconds (separate Rust build 0.19 seconds), with exit 0 and the complete
  host-effect/allocation ledger. Log:
  `target/stdlib-work/map-update-contracts-revised.log`.
  Corrected source: `3dff7057...`. All other accepted fixture and driver
  sources were unchanged. No compiler change was made.
- Independent source reviews accepted the tiny admission and remaining exact
  lookup/callback/representative/storage observations, type shapes and
  capability boundaries. Source review is not runtime acceptance.
- All four registered groups are accepted across these receipts: three
  execute native programs and one checks five capability rejections. The
  jointly zero-sized V/R callback path executed successfully. No source change
  or native rerun followed acceptance.

## Frozen sources

| Source | SHA-256 |
| --- | --- |
| `tests/stdlib_map_update_execution.rs` | `d98231cdb8cd4ae34ce7fb10c3b49cfeb361d5851b13681f970b3c595c5ed6b6` |
| `admission.lani` | `cdc01973333d7f485be9715e82d92f17523c4cdc312341bd4ae1550fba27e109` |
| `contracts.lani` | `3dff70570d564c2b9bdc66c63058172eb1677d1cfc8357f0ee4c90d56768a7ab` |
| `shapes.lani` | `ff619d2e2bb1ef07cb0ca25fb39cd4f43de4dc037f03e02cf3d6658c5032c00a` |
| `negative_hash_key_eq.lani` | `0c86101c336472955d34addd48db293baafcfdb710f8408cb51f583ded56c149` |
| `negative_hash_key_hash.lani` | `ec8ccb419bd322cc658519ee8e8e6294ba315fc62f84053424ffa29f2dda3423` |
| `negative_hash_mapper.lani` | `15ba25d33b3c38bb724f11f86523c4bf0bb91c65fb12590b4045f36e9bd69ec1` |
| `negative_tree_key_ord.lani` | `36b9e5a2bf01400790125f691d767f859215d351baded4c3caf1a7653e74b60a` |
| `negative_tree_mapper.lani` | `fb9e05606f8313ff7ae7ef0b643fa0c5a9a1e0e64abbf1738dc1a657df7eaac5` |
