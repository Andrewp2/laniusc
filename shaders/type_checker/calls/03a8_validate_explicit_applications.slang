import type_checker.constant_constraints;
// Validate immutable explicit bindings after closure, then retain them in the
// accepted context snapshot used for native specialization (including unused
// parameters). Their source-owned environment remains independent of context.
import hir_records;
import type_checker.calls.constant_claim_identity;
import type_checker.calls.explicit_application_owner;
import status;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.checked_type_graph;
import type_checker.scoped_type_equality;
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; uint n_source_files; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> resolved_value_type_qualifier_token;
StructuredBuffer<HirRange> compact_path_type_arg_ranges;
RWStructuredBuffer<uint> status;
static const uint INVALID = 0xffffffffu;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 65535u * 256u;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (call >= count || compact_hir_core[call].kind != 19u) return;
    uint callee = compact_hir_payload[call].a;
    if (callee >= count) return;
    uint leaf; bool repeated;
    uint token = explicit_callable_application_token(call, count, gParams.n_tokens,
        compact_hir_core, compact_hir_links, compact_hir_payload, path_id_by_owner_hir,
        compact_path_count, compact_paths, compact_path_segments,
        resolved_value_type_qualifier_token, compact_path_type_arg_ranges, leaf, repeated);
    if (token >= gParams.n_tokens) return;
    HirRange arguments = compact_path_type_arg_ranges[token];
    uint4 descriptor = call_explicit_environment[token];
    if (arguments.count == 0u && descriptor.x == 0u &&
        call_explicit_application_status[token] == 0u) return;
    uint anchor = compact_hir_core[call].token_start;
    if (repeated) { record_min_token_error(status, anchor, 10u, 0xffffff09u); return; }
    uint binding_status = call_explicit_application_status[token];
    if (binding_status != 1u || descriptor.x == 0u)
    {
        uint detail = binding_status == 2u ? 0xffffff09u
            : binding_status == 3u ? 0xffffff0au
            : binding_status == 4u ? 0xffffff0bu : 0xffffff08u;
        record_min_token_error(status, anchor, 10u, detail);
        return;
    }
    uint2 bindings[32]; uint mask = 0u;
    InferredConstant constants[32]; uint constant_mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++)
    {
        uint2 reference;
        if ((descriptor.w & (1u << slot)) != 0u)
        {
            if (!checked_explicit_environment_constant(0x80000000u | token,
                slot, reference.x, reference.y))
            { record_min_token_error(status, anchor, 10u, 0xffffff0bu); return; }
            if ((call_context_constant_mask[call] & (1u << slot)) != 0u &&
                !checked_constant_claims_compatible(
                    uint2(call_context_constant_kind[call * 32u + slot], call_context_constant_payload[call * 32u + slot]),
                    call_context_constant_identity_mode[call * 32u + slot], reference, 0u, gParams.n_tokens))
            { record_min_token_error(status, anchor, 3u, 0u); return; }
            constants[slot] = inferred_constant_reference(reference);
            constant_mask |= 1u << slot;
        }
        if ((descriptor.z & (1u << slot)) == 0u) continue;
        if (!checked_explicit_environment_argument(0x80000000u | token,
            slot, reference.x, reference.y))
        { record_min_token_error(status, anchor, 10u, 0xffffff0bu); return; }
        if ((call_context_arg_mask[call] & (1u << slot)) != 0u &&
            !scoped_type_refs_equal<ScopedCheckedTypeGraph>(reference.x, reference.y, INVALID,
                call_context_ref_tag[call * 32u + slot], call_context_ref_payload[call * 32u + slot],
                INVALID, checked_type_capacity(), gParams.n_tokens))
        { record_min_token_error(status, anchor, 3u, 0u); return; }
        bindings[slot] = reference;
        mask |= 1u << slot;
    }
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            call_context_ref_tag[call * 32u + slot] = bindings[slot].x;
            call_context_ref_payload[call * 32u + slot] = bindings[slot].y;
        }
    call_context_arg_mask[call] |= mask;
    if (!publish_context_constants<ScopedCheckedTypeGraph>(call, constants, constant_mask, gParams.n_tokens))
    { record_min_token_error(status, anchor, 6u, 0x474e0001u); return; }
    call_context_owner_by_token[token] = call;
}
