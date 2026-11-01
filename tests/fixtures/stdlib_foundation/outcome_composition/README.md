# Eager outcome composition contracts

All three focused gates passed in the separate runs recorded below. Root owns
compiler, Cargo and native commands; the receipts do not imply a combined
rerun or a broader generic-type proof.

The first gate is `admission.lani`: a small executable check of specialized
Option flatten, Result flatten, Option-of-Result transpose and the imported
Result-of-Option transpose extension defined in `core::option`.

`contracts.lani` covers the literal four-tag tables for cross-type Option.and,
Result.and and Result.or through free functions and methods. Distinct selected
errors check left-error preservation versus right-error selection. Small u64
successes with errors changing between bool and four-word arrays force wider
and narrower Result layouts, including selected left successes and originals.

Both flatten families and both transpose directions exercise their three
variant states, inverse compositions and original inputs. Payloads include a
generic record, nested enums/arrays, full-width signed and unsigned fields,
signaling IEEE payloads checked by integer bits, and borrowed byte slices on
negative-stride fixed and packed positive-stride backing. Deliberate mutations
after conversion verify that borrowed slices retain their live alias. All
ordinary conversion phases preserve the original bytes and caller copies.

Eager side-effect-producing operands must each execute exactly once even when
their outcome is discarded; no argument evaluation order is asserted. Existing
same-type call shapes, Some(false) and Some(None) remain distinct. Unit payload
and error controls observe enclosing Option/Result tags without exercising the
separate direct zero-sized-value function-return dependency.

Both executable gates require genuine x86_64 ELF and the shared jump checks.
Each requires an empty trace of mmap/mremap/munmap/brk/read/write/close services.
The finite target is Linux x86_64 CPU output from the GPU compiler; device
execution, formal correctness and arbitrary generic-type completeness are
unclaimed. These are shallow copies: the suite adds no cleanup authority, and
real owned-resource lifetimes are covered by separate owner fixtures.

A focused negative gate checks six explicit generic calls: Result.and retains
one error type, Result.or retains one success type, both flatten functions need
nested outcomes, and each transpose needs its precise optional/fallible shape.
Each fixture produced `LNC0006` at the marked operation; syntax rejection
cannot satisfy the gate.

## Executed receipts

| Gate | Observed scope | Result | Log under `target/stdlib-work/` |
| --- | --- | --- | --- |
| Specialized methods | One native admission process, including imported Result.transpose | 1 passed, 4.87s | `outcome-composition-admission-first.log` |
| Broad contracts | One native contract process, both actual byte strides and the variant/payload cases above | 1 passed, 6.81s | `outcome-composition-contracts-first.log` |
| Shared types and shapes | Six diagnostic compiles, each rejected at its marked typed call with `LNC0006` | 1 passed, 7.71s | `outcome-composition-negative-shapes-first.log` |

Both native processes passed their empty memory/I/O-service trace checks.
The negative-gate extension extracted the shared compile helper without
changing executable fixture behavior. Earlier native receipts were retained;
the Lanius bodies and production modules remained unchanged.

Retained Lanius SHA-256 identities:

| Source | Hash |
| --- | --- |
| `admission.lani` | `9900de6765c32e0a6313cafd427cf00be7db65b0e5b70a3af7797c1b439f75a6` |
| `contracts.lani` | `25ae3eb3c4798a107c15e25cf0ff0a2bbef715dc1861dc82886b00405ac70b4b` |
| `negative_and_error_type.lani` | `6eaf85529f1cf286c2ad2a16764905baadaad02ed17e064d21ac228563870226` |
| `negative_or_success_type.lani` | `7b5d92a5a8751242e5988cc99b1d1a99a313c989ab0abef18d97e1daeb638286` |
| `negative_result_flatten_shape.lani` | `d2de7ce0259dd1f58a59f60f331f5814d7bf9ec3b3fd5c0d4210f031e9a7923e` |
| `negative_option_flatten_shape.lani` | `bc9eb240d8a113d91116dc35875a30fe340ccbc349ca6c70efb0e6c38d778417` |
| `negative_transpose_to_result_shape.lani` | `dbce2c36a89c843c4958af517e17d7044b008abe7bf1f901e4a42ad50562a974` |
| `negative_transpose_to_option_shape.lani` | `b3b60da72734d2901659386976e7ba2bda272fcaf6da75e5c652b5045ee4637a` |
| `stdlib/core/option.lani` | `8b3cf42862f2c6c0203281d5b2b120124c0df74d1b0c664418f5a6e9f57938ee` |
| `stdlib/core/result.lani` | `1a036786910bdcb2f637a1d5e89d08881c2a2dea758beadc488065f8b23e748b` |

Focused selectors:

```text
cargo test --test stdlib_outcome_composition_execution specialized_outcome_methods_admit_native_flatten_and_imported_transpose -- --exact
cargo test --test stdlib_outcome_composition_execution eager_outcome_tables_preserve_cross_type_payloads_and_original_copies -- --exact
cargo test --test stdlib_outcome_composition_execution outcome_composition_rejects_shared_type_mismatches_and_wrong_nested_shapes -- --exact
```
