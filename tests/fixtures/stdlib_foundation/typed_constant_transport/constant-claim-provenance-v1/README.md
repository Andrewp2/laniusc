# Unexecuted regression inputs

No compiler, shader, x86 or GPU execution was performed in this lane. Root owns integration and execution.

- `runtime_array_only_nested_count.lani`: expected exit 0. In the original outer generic body, `pair` receives count K:u64 and the nested count conversion P_u64(P_u8(K)); both are array-only claims.
- `runtime_mixed_claim_priority.lani`: expected exit 0. `Tag<K>` contributes ordinary exact identity while array arguments contribute nested count conversions. Both source argument orders must select K, not the nested conversion.
- `reject_mixed_exact_projection_identity.lani`: expected rejection of the original generic body. Tag<K> and Tag<P_u64(P_u8(K))> are two ordinary claims; a weaker array result context cannot make them ordinary-identical.
- `reject_nested_count_fit.lani`: expected rejection. Matching equal counts cannot discharge the retained U8 fit for 256.

The typed_constant_identity rows 52–63 that this lane added tested the old inference engine (constant_constraints.slang). They were deleted with it on 2026-10-15; claims now go through ct_match and the checked claim kernels, covered by constant_claim_publication_tests.rs, ct_match_tests.rs and the source tests in tests/compiler_generic_types_execution.rs.

Still required during root integration: a buffer-backed claim/context selection probe or focused execution assertions for precedence and selected flags. The pure graph rows cover merge semantics but do not by themselves cover `call_const_claim_selected` publication, replay-map resource bindings, or retained host routing.
