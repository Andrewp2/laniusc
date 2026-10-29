# Stable sorting direct contracts

All four registered direct tests passed on their first attempts in two
separate commands:

| Receipt under `target/stdlib-work/` | Accepted scope | Time |
| --- | --- | --- |
| `stable-sort-admission-first.log` | One both-form stable-record admission test and native process | 7.35s |
| `stable-sort-direct-first.log` | Two native contract processes and one capability group with four marked rejections; admission filtered | 14.68s |

The separate Rust driver builds took 1.80s and 1.75s respectively. Root ran
compiler, Cargo and native commands; fixture authors performed static review
only. Independent model, resource/scale and migrated application gates have
separate receipts.

The admission sorts seventeen identifiable equivalent-key representatives in
guarded, nonzero-start views through each public form. A key-only Ord record
proves natural stability; a distinct record with no natural comparison traits
uses a descending canonical Comparator. Literal expected representative IDs
and full-width payload stamps check stability and whole-value preservation.
Only the documented finite comparison ceiling is asserted, not an exact merge
trace. The source guards remain unchanged.

`contracts.lani` has three finite scenario functions. Generic records carry
distinct identities, full-width stamps and nested Option/Result/array/error
payloads. Literal stable orders cover irregular seventeen-item ties, reverse
source order, repeated sorting, descending policy, two successive independent
keys and nine completely equivalent items. A bounded host list-sort control
independently checked all four seventeen-ID expected lists without reproducing
merge passes. Comparators inspect only their policy keys, never identities as
tie-breakers. Their call counts satisfy the public n*ceil(log2(n)) ceiling.

Actual native descending and packed ascending u8 views have the same logical
contents, nonzero/nested views and outside sentinels. Both natural and custom
forms produce literal sorted bytes without changing the guards. Additional
natural cases preserve i64 extrema and full-width values, and canonical
TotalF64 keys preserve infinity, signed-zero and NaN payload bits.

`bounds.lani` tests malformed empty/nonempty metadata over unreadable backing,
metadata error precedence over excessive workspace counts, complete unchanged
source guards, exact existing i32/u64 workspace byte ceilings, and valid
zero/singleton no-access paths. Both sort forms run seven zero-sized elements
without host allocation; the custom comparator is actually invoked, bounded
by the normal engine ceiling. The MAX-start empty and near-MAX singleton cases
exercise only their promised no-access paths, not general physical backing
safety. Four negative fixtures require LNC0008 at marked calls for a missing
comparator, wrong left/right operand type, or raw f64 without Ord.

The strict x86_64 ELF/shared-jump harness traces all syscalls, permits only
entry/exit and exact workspace mmap/munmap pairs, and requires no live mappings
at exit. Admission expects two successful reservations, one per sort call.
All three accepted native processes passed these checks. Admission observed
exactly two reservations/releases; the bounds/ZST process observed none.
Reached ENOMEM, protected backing and nested-owner cases have separate resource
fixtures.

Accepted source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `d913ad1990d532585c90abf488a410e714179af8922d1c99792271e38d0858de` |
| `contracts.lani` | `69e67748455ed19b322f8f5fc5b808f213cb8591f20bdd527f5bf353c4043784` |
| `bounds.lani` | `ad552c07544b6a1ab86b8d8a4e380a54328d7e05859504313c202513b3b39fee` |
| `negative_missing_comparator.lani` | `e21cbee46e7aa2cb9d7d80e8d42103c89b0222e8366b4619ab3102ac693d6912` |
| `negative_wrong_left.lani` | `bc41aef5eac30e493700907a8b98ff5d52186946875c66a631b60d2ea4c43729` |
| `negative_wrong_right.lani` | `cde9367ae0aa84178bda1eeaac8f3b349ad1e1019d3cd6dc52b33fadce375ee0` |
| `negative_missing_ord.lani` | `b40b7d94c7a32cdff08b0f4a0be46b10ac6e13e426b32180067d04d3e8526ba6` |
| `stdlib/alloc/slice.lani` | `e56129df41d435c226a11612d67b52cd9364e25d35d295e90f592376009aa667` |

```text
cargo test --test stdlib_stable_sort_execution stable_sort_natural_and_custom_record_orders_execute_stable_admission -- --exact
cargo test --test stdlib_stable_sort_execution stable_sort_preserves_compound_ties_successive_policies_and_real_layouts -- --exact
cargo test --test stdlib_stable_sort_execution stable_sort_metadata_capacity_trivial_and_zero_sized_admission_uses_no_host_memory -- --exact
cargo test --test stdlib_stable_sort_execution stable_sort_requires_exact_comparator_operands_or_natural_ord -- --exact
```

The accepted target is native Linux x86_64 CPU execution of GPU-compiler
output. GPU device execution, other targets, automatic ownership and formal
verification need separate evidence.
