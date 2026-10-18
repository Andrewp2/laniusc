# Unexecuted regression inputs

No compiler, shader, x86 or GPU execution was performed in this lane. Root owns integration and execution.

- `runtime_array_only_nested_count.lani`: expected exit 0. In the original outer generic body, `pair` receives count K:u64 and the nested count conversion P_u64(P_u8(K)); both are array-only claims.
- `runtime_mixed_claim_priority.lani`: expected exit 0. `Tag<K>` contributes ordinary exact identity while array arguments contribute nested count conversions. Both source argument orders must select K, not the nested conversion.
- `accept_mixed_projection_count_identity.lani`: expected exit 0; `conflicting` is never instantiated. This input predates canonical type IDs, when it was `reject_mixed_exact_projection_identity.lani` and expected `Tag<K>` and `Tag<P_u64(P_u8(K))>` to be two conflicting ordinary claims. An array's identity holds its length's count class (docs/canonical-type-ids.md), and the count class of `P_u8(K)` is K, so `narrow(values)` has type `[i32; K]`. `make`'s N has only that count claim and binds K itself, and `make(narrow(values))` is `Tag<K>`, which agrees with `tag`. This is sound: narrow's pending u8 fit for K is still checked when `conflicting` is instantiated, and whenever it holds `P_u64(P_u8(K))` equals K.
- `reject_mixed_projection_instance_fit.lani`: expected rejection. It instantiates the same `conflicting` with K = 256, so narrow's retained u8 fit fails.
- `reject_nested_count_fit.lani`: expected rejection. Matching equal counts cannot discharge the retained U8 fit for 256.

The typed_constant_identity rows 52–63 that this lane added tested the old inference engine (constant_constraints.slang). They were deleted with it on 2026-10-15; claims now go through ct_match and the checked claim kernels, covered by constant_claim_publication_tests.rs, ct_match_tests.rs and the source tests in tests/compiler_generic_types_execution.rs.

Still required during root integration: a buffer-backed claim/context selection probe or focused execution assertions for precedence and selected flags. The pure graph rows cover merge semantics but do not by themselves cover `call_const_claim_selected` publication, replay-map resource bindings, or retained host routing.
