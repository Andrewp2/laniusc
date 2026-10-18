// Validate immutable explicit bindings after closure, then retain them in the
// accepted context snapshot used for native specialization (including unused
// parameters). Their source-owned environment remains independent of context.
//
// This runs after the late canonical stage, so every checked type has its
// canonical ID and types compare by ID (docs/canonical-type-ids.md). A lane
// visits the explicit slots twice, first to validate and then to publish, so
// it keeps no per-slot copies.
import hir_records;
import type_checker.calls.constant_claim_identity;
import type_checker.calls.explicit_application_owner;
import status;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.checked_type_graph;
import type_checker.checked_type_identity;
import type_checker.checked_slots;
import type_checker.argument_context;
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
StructuredBuffer<HirTypeArg> compact_type_args;
RWStructuredBuffer<uint> status;
static const uint INVALID = 0xffffffffu;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_INTEGER_LITERAL_RANGE = 24u;
// Operand reasons of a diagnosed application (explicit_constant_operand).
static const uint OPERAND_LITERAL_RANGE = 2u;

// One operand of the application is diagnosed at itself: an integer literal
// outside the parameter's range at the literal (LNC0069), or a named constant
// declared with another scalar, which is conflicting type evidence (LNC0006).
void record_operand_diagnostic(HirRange arguments, uint binding_status, uint anchor, uint count)
{
    uint reason = (binding_status >> 4u) & 15u;
    uint ordinal = (binding_status >> 8u) & 255u;
    uint scalar = binding_status >> 16u;
    uint capacity; uint stride;
    compact_type_args.GetDimensions(capacity, stride);
    uint operand = ordinal < arguments.count && arguments.start < capacity &&
        ordinal < capacity - arguments.start ? compact_type_args[arguments.start + ordinal].value : INVALID;
    uint token = operand < count ? compact_hir_core[operand].token_start : INVALID;
    if (reason == OPERAND_LITERAL_RANGE)
    {
        uint literal; bool negative;
        if (integer_literal_magnitude(operand, count, compact_hir_core, compact_hir_payload,
            literal, negative))
            token = compact_hir_core[literal].token_start;
    }
    record_min_token_error(status, token < gParams.n_tokens ? token : anchor,
        reason == OPERAND_LITERAL_RANGE ? ERR_INTEGER_LITERAL_RANGE : ERR_ASSIGN_MISMATCH,
        reason == OPERAND_LITERAL_RANGE ? scalar : 0u);
}
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
    if ((binding_status & 15u) == EXPLICIT_APPLICATION_OPERAND_DIAGNOSED)
    { record_operand_diagnostic(arguments, binding_status, anchor, count); return; }
    if (binding_status != 1u || descriptor.x == 0u)
    {
        uint detail = binding_status == 2u ? 0xffffff09u
            : binding_status == 3u ? 0xffffff0au
            : binding_status == 4u ? 0xffffff0bu : 0xffffff08u;
        record_min_token_error(status, anchor, 10u, detail);
        return;
    }
    uint mask = descriptor.z;
    uint constant_mask = descriptor.w;
    // An explicit constant replaces the call's contextual claim for its slot.
    // An exact claim needs no merge; a retained count claim must be
    // compatible. Both keep the explicit reference itself (no projection).
    bool constants_published = true;
    [loop]
    for (uint pass = 0u; pass < 2u; pass++)
    {
        for (uint slot = 0u; slot < 32u; slot++)
        {
            uint2 reference;
            if ((constant_mask & (1u << slot)) != 0u)
            {
                if (!checked_explicit_environment_constant(0x80000000u | token,
                    slot, reference.x, reference.y))
                { record_min_token_error(status, anchor, 10u, 0xffffff0bu); return; }
                uint2 prior = (call_context_constant_mask[call] & (1u << slot)) != 0u
                    ? uint2(call_context_constant_kind[call * 32u + slot], call_context_constant_payload[call * 32u + slot])
                    : uint2(0u, INVALID);
                uint prior_mode = call_context_constant_identity_mode[call * 32u + slot];
                if (pass == 0u)
                {
                    // A retained claim must agree with the explicit constant:
                    // typed identity, or count identity for a count claim.
                    if ((call_context_constant_mask[call] & (1u << slot)) != 0u &&
                        !checked_constant_claims_compatible(prior, prior_mode, reference, 0u, gParams.n_tokens))
                    { record_min_token_error(status, anchor, 3u, 0u); return; }
                    // The explicit constant is published as an exact claim.
                    if (!checked_constant_claim_admitted(reference, 0u, gParams.n_tokens))
                        constants_published = false;
                }
                else if (constants_published)
                {
                    call_context_constant_kind[call * 32u + slot] = reference.x;
                    call_context_constant_payload[call * 32u + slot] = reference.y;
                    call_context_constant_identity_mode[call * 32u + slot] = 0u;
                }
            }
            if ((mask & (1u << slot)) == 0u) continue;
            if (!checked_explicit_environment_argument(0x80000000u | token,
                slot, reference.x, reference.y))
            { record_min_token_error(status, anchor, 10u, 0xffffff0bu); return; }
            if (pass == 0u)
            {
                if ((call_context_arg_mask[call] & (1u << slot)) != 0u &&
                    !checked_types_equal(CheckedSlots(), reference.x, reference.y,
                        call_context_ref_tag[call * 32u + slot], call_context_ref_payload[call * 32u + slot], true))
                { record_min_token_error(status, anchor, 3u, 0u); return; }
                continue;
            }
            call_context_ref_tag[call * 32u + slot] = reference.x;
            call_context_ref_payload[call * 32u + slot] = reference.y;
        }
    }
    call_context_arg_mask[call] |= mask;
    if (!constants_published)
    { record_min_token_error(status, anchor, 6u, 0x474e0001u); return; }
    call_context_constant_mask[call] |= constant_mask;
    call_context_owner_by_token[token] = call;
}
