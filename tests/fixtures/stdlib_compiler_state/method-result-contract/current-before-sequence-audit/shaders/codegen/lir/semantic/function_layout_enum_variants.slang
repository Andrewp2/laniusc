import native_value_layout;
// One lane computes one variant's tagged-union width, then publishes the
// maximum for its enum. Declaration collection initializes even empty enums
// to the discriminant width before this pass.

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
RWStructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint DISPATCH_X_STRIDE = 16776960u;

#include "type_closure_graph.slang"

bool symbolic_payload_layout(uint type_node)
{
    uint tag = semantic_expr_ref_tag[type_node];
    if (tag == TYPE_REF_GENERIC_PARAM) return true;
    if (tag != 3u) return false;
    uint instance = semantic_expr_ref_payload[type_node];
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (instance >= capacity || type_instance_kind[instance] == 3u) return false;
    return !concrete_instance_is_closed<NativeTypeStructureGraph>(instance, capacity);
}

uint nominal_declaration(uint type_node, uint type_id, uint hir_count)
{
    uint token = semantic_aggregate_decl_token[type_node];
    uint declaration = token < gParams.n_tokens
        ? semantic_aggregate_hir_by_name_token[token] : INVALID;
    if (declaration < hir_count)
    {
        uint kind = compact_hir_core[declaration].kind;
        if (kind == HIR_STRUCT_ITEM || kind == HIR_ENUM_ITEM)
            return declaration;
    }
    uint enum_declaration = INVALID;
    if (type_id >= TY_ENUM_BASE)
    {
        token = type_id - TY_ENUM_BASE;
        if (token < gParams.n_tokens)
        {
            declaration = semantic_aggregate_hir_by_name_token[token];
            if (declaration < hir_count &&
                compact_hir_core[declaration].kind == HIR_ENUM_ITEM)
                enum_declaration = declaration;
        }
    }
    uint struct_declaration = INVALID;
    if (type_id >= TY_STRUCT_BASE)
    {
        token = type_id - TY_STRUCT_BASE;
        if (token < gParams.n_tokens)
        {
            declaration = semantic_aggregate_hir_by_name_token[token];
            if (declaration < hir_count &&
                compact_hir_core[declaration].kind == HIR_STRUCT_ITEM)
                struct_declaration = declaration;
        }
    }
    if (enum_declaration != INVALID && struct_declaration != INVALID)
        return INVALID;
    return enum_declaration != INVALID ? enum_declaration : struct_declaration;
}

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

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
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
    // The last invocation checks that the bounded aggregate fixed point has
    // converged. Every enum adds a discriminant, so a by-value cycle keeps
    // growing and is rejected instead of being assigned a finite layout.
    if (gParams.reserved == 0u)
    {
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
        return;
    }
    uint ignored;
    InterlockedMax(semantic_struct_word_count_by_hir[variant.owner], words,
        ignored);
}
