// Cache the complete width of enum-valued struct fields before recursive
// struct layout. Checked array references own all repetition counts; source
// HIR operand indices never participate in native layout arithmetic.

import hir_records;
import gpu_index;
import type_checker.checked_array_counts;
import type_checker.native_nominal_identity;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> type_instance_native_words;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<uint> semantic_struct_field_word_count_by_row;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = gParams.n_hir_nodes;
    if (row >= min(compact_field_count[0u], hir_count)) return;
    HirField field = compact_fields[row];
    if (field.owner >= hir_count || field.value >= hir_count ||
        compact_hir_core[field.owner].kind != HIR_STRUCT_ITEM) return;

    uint tag = semantic_expr_ref_tag[field.value];
    uint payload = semantic_expr_ref_payload[field.value];
    if (tag != 3u && compact_hir_core[field.value].kind == HIR_TYPE &&
        compact_hir_payload[field.value].a == HIR_TYPE_FORM_ARRAY)
    {
        semantic_struct_field_word_count_by_row[row] = INVALID;
        return;
    }
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    uint multiplier = 1u;
    for (uint depth = 0u; depth < 64u; depth++)
    {
        if (tag != 3u) break;
        if (payload >= capacity)
        {
            semantic_struct_field_word_count_by_row[row] = INVALID;
            return;
        }
        uint kind = type_instance_kind[payload];
        // References and slices own descriptors, never inline enum payloads.
        if (kind == 3u || kind == 4u) return;
        if (kind != 2u) break;
        uint count;
        if (!checked_source_array_count(type_instance_len_kind[payload],
            type_instance_len_payload[payload], gParams.n_tokens, count) ||
            count >= 0xfffffffeu ||
            (count != 0u && multiplier > (INVALID - 1u) / count))
        {
            semantic_struct_field_word_count_by_row[row] = INVALID;
            return;
        }
        multiplier *= count;
        uint next_tag = type_instance_elem_ref_tag[payload];
        payload = type_instance_elem_ref_payload[payload];
        tag = next_tag;
        if (depth == 63u)
        {
            semantic_struct_field_word_count_by_row[row] = INVALID;
            return;
        }
    }
    if (tag == 2u || (tag == 3u &&
        (payload >= capacity || type_instance_kind[payload] != 1u)))
    {
        semantic_struct_field_word_count_by_row[row] = INVALID;
        return;
    }
    uint token = tag == 3u ? type_instance_decl_token[payload]
        : tag == 1u ? native_nominal_declaration_token(payload, gParams.n_tokens,
            hir_count, semantic_aggregate_hir_by_name_token, compact_hir_core) : INVALID;
    uint declaration = token < gParams.n_tokens
        ? semantic_aggregate_hir_by_name_token[token] : INVALID;
    // Opaque imported applications use their completed checked native width
    // in function_layout_words, without requiring a local enum declaration.
    if (declaration >= hir_count ||
        compact_hir_core[declaration].kind != HIR_ENUM_ITEM) return;

    uint width = tag == 3u ? type_instance_native_words[payload]
        : semantic_struct_word_count_by_hir[declaration];
    semantic_struct_field_word_count_by_row[row] = width != 0u && width != INVALID &&
        multiplier <= (INVALID - 1u) / width ? multiplier * width : INVALID;
}
