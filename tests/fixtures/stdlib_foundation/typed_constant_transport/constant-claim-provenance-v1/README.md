# Unexecuted regression inputs

No compiler, shader, x86 or GPU execution was performed in this lane. Root owns integration and execution.

- `runtime_array_only_nested_count.lani`: expected exit 0. In the original outer generic body, `pair` receives count K:u64 and the nested count conversion P_u64(P_u8(K)); both are array-only claims.
- `runtime_mixed_claim_priority.lani`: expected exit 0. `Tag<K>` contributes ordinary exact identity while array arguments contribute nested count conversions. Both source argument orders must select K, not the nested conversion.
- `reject_mixed_exact_projection_identity.lani`: expected rejection of the original generic body. Tag<K> and Tag<P_u64(P_u8(K))> are two ordinary claims; a weaker array result context cannot make them ordinary-identical.
- `reject_nested_count_fit.lani`: expected rejection. Matching equal counts cannot discharge the retained U8 fit for 256.

The existing typed_constant_identity shader grows from 52 to 64 rows. Rows52–63 expect `[1,1,1,1]` and call production merge/constraint functions. They cover array-only nested identity, both mixed priority orders, two conflicting ordinary identities, declared result scalar mismatch, noninteger provenance, default producer modes, ordinary concrete inverse-projection provenance, exact terminal declaration/scalar identity, and failed concrete fits. These rows are not claimed as executed.

Still required during root integration: a buffer-backed claim/context selection probe or focused execution assertions for precedence and selected flags. The pure graph rows cover merge semantics but do not by themselves cover `call_const_claim_selected` publication, replay-map resource bindings, or retained host routing.
