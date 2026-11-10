import type_checker.constant_atoms_identity;
import native_value_layout;
// Checks every enum variant against the widths function_layout_words
// published. One lane recomputes one variant's tagged-union width from the
// published payload widths; a variant wider than its enum, or an invalid
// width, marks the lowering unsupported. A by-value cycle through an enum
// has no finite width, so the walk publishes it invalid and this pass
// rejects it. Generic declarations keep an invalid width without an error.

import hir_records;
import codegen.lowering_ir;
import gpu_index;
import type_checker.concrete_type_closure;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<uint> compact_variant_payload_start;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_aggregate_decl_token;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_native_words;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

#include "function_layout_payload_types.slang"

bool owner_has_generic_payload(uint owner, uint hir_count)
{
    uint variant_total = min(compact_variant_count[0u], hir_count);
    uint lo = 0u;
    uint hi = variant_total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_variants[mid].owner < owner) lo = mid + 1u;
        else hi = mid;
    }
    uint payload_total = min(compact_variant_payload_row_count[0u], hir_count);
    for (uint row = lo;
         row < variant_total && compact_variants[row].owner == owner;
         row += 1u)
    {
        uint start = compact_variant_payload_start[row];
        uint count = compact_variant_payload_count[row];
        if (count != 0u && (start >= payload_total || count > payload_total - start))
            continue;
        for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
        {
            HirVariantPayload payload = compact_variant_payloads[start + ordinal];
            if (payload.variant == row && payload.ordinal == ordinal &&
                payload.type_node < hir_count &&
                symbolic_payload_layout(payload.type_node))
                return true;
        }
    }
    return false;
}

// One variant row.
void validate_enum_variant_row(uint row)
{
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (row >= min(compact_variant_count[0u], hir_count)) return;
    HirVariant variant = compact_variants[row];
    if (variant.owner >= hir_count ||
        compact_hir_core[variant.owner].kind != HIR_ENUM_ITEM) return;

    uint start = compact_variant_payload_start[row];
    uint count = compact_variant_payload_count[row];
    uint payload_total = min(compact_variant_payload_row_count[0u], hir_count);
    uint words = 1u; // discriminant
    bool unresolved_generic = false;
    if (count != 0u && (start >= payload_total || count > payload_total - start))
        words = INVALID;
    for (uint ordinal = 0u; ordinal < count && words != INVALID; ordinal += 1u)
    {
        HirVariantPayload payload = compact_variant_payloads[start + ordinal];
        if (payload.variant != row || payload.ordinal != ordinal ||
            payload.type_node >= hir_count)
        {
            words = INVALID;
            break;
        }
        uint ref_tag = semantic_expr_ref_tag[payload.type_node];
        if (symbolic_payload_layout(payload.type_node))
        {
            unresolved_generic = true;
            words = INVALID;
            break;
        }
        if (ref_tag == 3u)
        {
            uint instance = semantic_expr_ref_payload[payload.type_node];
            uint capacity; uint stride;
            type_instance_kind.GetDimensions(capacity, stride);
            uint payload_words = instance < capacity
                ? type_instance_kind[instance] == 3u ? NATIVE_SLICE_WORDS : type_instance_native_words[instance]
                : INVALID;
            if (payload_words == INVALID || words >= INVALID - payload_words)
            {
                words = INVALID;
                break;
            }
            words += payload_words;
            continue;
        }
        if (ref_tag != TYPE_REF_SCALAR)
        {
            words = INVALID;
            break;
        }
        uint type_id = semantic_expr_ref_payload[payload.type_node];
        uint payload_words = type_id == SEMANTIC_LIR_TY_STRING ? 2u : 1u;
        if (type_id >= TY_STRUCT_BASE)
        {
            uint declaration = nominal_declaration(payload.type_node,
                type_id, hir_count);
            if (declaration >= hir_count)
            {
                words = INVALID;
                break;
            }
            payload_words = semantic_struct_word_count_by_hir[declaration];
            if (payload_words == INVALID)
            {
                words = INVALID;
                break;
            }
        }
        words = words > INVALID - payload_words
            ? INVALID : words + payload_words;
    }
    // Generic declarations have no fixed by-value layout. Keep their
    // width invalid so instantiations cannot assume one payload word.
    if (unresolved_generic) return;
    uint current = semantic_struct_word_count_by_hir[variant.owner];
    if (current == INVALID && words != INVALID &&
        owner_has_generic_payload(variant.owner, hir_count))
        return;
    if (words == INVALID || current == INVALID || words > current)
    {
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
        InterlockedMin(lowering_status[0u].first_unsupported_hir,
            variant.owner);
    }
}

// function_layout_collect sizes the indirect arguments in 256-lane groups.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    validate_enum_variant_row(linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE));
}
