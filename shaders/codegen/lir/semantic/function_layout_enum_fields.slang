// Cache the complete width of enum-valued struct fields before recursive
// struct layout. Each lane writes one field row; the later layout pass may
// then traverse nested structs without resolving enum variants in its stack.

import hir_records;
import gpu_index;
import uint_math;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> semantic_aggregate_decl_token;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<uint> semantic_struct_field_word_count_by_row;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = gParams.n_hir_nodes;
    if (row >= min(compact_field_count[0u], gParams.n_hir_nodes)) return;
    HirField field = compact_fields[row];
    if (field.owner >= hir_count ||
        compact_hir_core[field.owner].kind != HIR_STRUCT_ITEM) return;

    uint type_node = field.value;
    uint multiplier = 1u;
    if (type_node < hir_count && compact_hir_core[type_node].kind == HIR_TYPE)
    {
        HirPayload type = compact_hir_payload[type_node];
        if (type.a == HIR_TYPE_FORM_SLICE) return;
        if (type.a == HIR_TYPE_FORM_ARRAY)
        {
            multiplier = type.d;
            type_node = type.b;
        }
    }
    uint token = type_node < hir_count
        ? semantic_aggregate_decl_token[type_node] : INVALID;
    uint declaration = token < gParams.n_tokens
        ? semantic_aggregate_hir_by_name_token[token] : INVALID;
    if (declaration >= hir_count ||
        compact_hir_core[declaration].kind != HIR_ENUM_ITEM) return;

    uint width = semantic_struct_word_count_by_hir[declaration];
    semantic_struct_field_word_count_by_row[row] =
        width != 0u && width != INVALID
            ? saturating_mul_u32(multiplier, width) : INVALID;
}
