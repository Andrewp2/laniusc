# Unexecuted regression inputs

No compiler, shader, x86 or GPU execution was performed in this lane. Root owns integration and execution.

- `runtime_array_only_nested_count.lani`: expected exit 0. In the original outer generic body, `pair` receives count K:u64 and the nested count conversion P_u64(P_u8(K)); both are array-only claims.
- `runtime_mixed_claim_priority.lani`: expected exit 0. `Tag<K>` contributes ordinary exact identity while array arguments contribute nested count conversions. Both source argument orders must select K, not the nested conversion.
- `accept_mixed_projection_count_identity.lani`: expected exit 0; `conflicting` is never instantiated. This input predates canonical type IDs, when it was `reject_mixed_exact_projection_identity.lani` and expected `Tag<K>` and `Tag<P_u64(P_u8(K))>` to be two conflicting ordinary claims. An array's identity holds its length's count class (docs/canonical-type-ids.md), and the count class of `P_u8(K)` is K, so `narrow(values)` has type `[i32; K]`. `make`'s N has only that count claim and binds K itself, and `make(narrow(values))` is `Tag<K>`, which agrees with `tag`. This is sound: narrow's pending u8 fit for K is still checked when `conflicting` is instantiated, and whenever it holds `P_u64(P_u8(K))` equals K.
- `reject_mixed_projection_instance_fit.lani`: expected rejection. It instantiates the same `conflicting` with K = 256, so narrow's retained u8 fit fails.
- `reject_nested_count_fit.lani`: expected rejection. Matching equal counts cannot discharge the retained U8 fit for 256.

The existing typed_constant_identity shader grows from 52 to 64 rows. Rows52–63 expect `[1,1,1,1]` and call production merge/constraint functions. They cover array-only nested identity, both mixed priority orders, two conflicting ordinary identities, declared result scalar mismatch, noninteger provenance, default producer modes, ordinary concrete inverse-projection provenance, exact terminal declaration/scalar identity, and failed concrete fits. These rows are not claimed as executed.

Still required during root integration: a buffer-backed claim/context selection probe or focused execution assertions for precedence and selected flags. The pure graph rows cover merge semantics but do not by themselves cover `call_const_claim_selected` publication, replay-map resource bindings, or retained host routing.
