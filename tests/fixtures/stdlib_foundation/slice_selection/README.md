# Checked slice selection direct contracts

All three registered direct tests passed across two commands:

| Receipt | Accepted scope | Time |
| --- | --- | --- |
| `target/stdlib-work/slice-selection-admission-first.log` | One admission test and native process | 6.93s |
| `target/stdlib-work/slice-selection-contracts-first.log` | Two tests: one native five-scenario contract process and three marked LNC0008 rejections; admission filtered | 7.25s |

Root ran the compiler, Cargo and native commands. Independent model, owner and
application gates are separate from these finite direct receipts.

`admission.lani` directly calls both public selection functions over a nonzero
17-element subview, checks literal median/extreme rank results and outside
guards, then mutates each returned one-element View to prove that it aliases
the stored nth element.
The custom comparator records calls; the natural wrapper exercises its Ord
bound. Both accepted native processes passed strict x86_64 ELF checks and full
syscall tracing: only process entry and exit occurred, with no allocation or
other host services.

`contracts.lani` has five finite scenario functions. Its lawful comparison cases
check every rank in a literal 17-element duplicate-heavy input under ascending,
descending and natural order; both partition inequalities, complete occurrence
counts and outside guards are checked without requiring a particular internal
permutation. Repeated selections reuse permuted backing and the latest returned
View is used as a live alias. Tagged payloads have no Ord implementation and
retain each whole shallow value exactly once under a custom comparator.

Both actual byte strides exercise every rank of a nine-byte binary input, with
full permutation, partition, alias and surrounding-storage checks. Empty and
forged metadata, extreme invalid ranks and backed invalid ranges reject without
comparison or mutation; valid singleton selection performs zero comparisons.
Three deliberately inconsistent returning comparator modes and an all-equal
mode must finish and retain the complete permutation, without an order or
comparison-cost claim.

Three marked negative fixtures rejected with LNC0008 for missing Comparator, wrong
right-hand Comparator type and missing Ord. The runtime Tagged case separately
proves that the comparator-taking function requires no implicit Ord bound.

Accepted fixture and production source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `9e1a7cf36115f237ac29931622ad385aa30d688ad3a52cc5a3c5cfc182380be6` |
| `contracts.lani` | `10b6eddbd6593728c9d2b6d5803325f1a94178fe1e2a23c461b6843b2d8b5b44` |
| `stdlib/core/slice.lani` | `d77cb28ceb9f6df5e3fa0f752a36409bc4d2ddab1bd35214969fc39614fd13d5` |

```text
cargo test --test stdlib_slice_selection_execution slice_selection_custom_and_natural_functions_return_live_nth_aliases -- --exact
cargo test --test stdlib_slice_selection_execution slice_selection_executes_rank_partition_permutation_bounds_and_stride_contracts -- --exact
cargo test --test stdlib_slice_selection_execution slice_selection_requires_matching_comparator_and_natural_order_bounds -- --exact
```

Accepted target scope is native Linux x86_64 CPU execution of executables
produced by the GPU compiler. GPU device execution and formal correctness are
unclaimed.
