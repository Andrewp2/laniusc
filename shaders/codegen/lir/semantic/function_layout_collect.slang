import hir_records;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_variant_count;
RWStructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
RWStructuredBuffer<uint> semantic_struct_field_count_by_hir;
RWStructuredBuffer<uint> semantic_struct_field_start_by_hir;
RWStructuredBuffer<uint> semantic_struct_word_count_by_hir;
// Indirect arguments for the layout rounds: [0..3) one lane per variant row,
// [3..6) one lane per field row.
RWStructuredBuffer<uint> semantic_layout_dispatch_args;

static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint MAX_GROUPS_X = 65535u;

void publish_layout_dispatch(uint slot, uint rows)
{
    uint groups = rows / 256u + (rows % 256u != 0u ? 1u : 0u);
    semantic_layout_dispatch_args[slot * 3u] = min(groups, MAX_GROUPS_X);
    semantic_layout_dispatch_args[slot * 3u + 1u] =
        max(1u, groups / MAX_GROUPS_X + (groups % MAX_GROUPS_X != 0u ? 1u : 0u));
    semantic_layout_dispatch_args[slot * 3u + 2u] = 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (row < hir_count &&
        (compact_hir_core[row].kind == HIR_STRUCT_ITEM ||
         compact_hir_core[row].kind == HIR_ENUM_ITEM))
    {
        uint name_token = compact_hir_payload[row].b;
        if (name_token < gParams.n_tokens)
            semantic_aggregate_hir_by_name_token[name_token] = row;
        if (compact_hir_core[row].kind == HIR_ENUM_ITEM)
            semantic_struct_word_count_by_hir[row] = 1u;
    }

    uint field_count = min(compact_field_count[0u], gParams.n_hir_nodes);
    if (row == 0u)
    {
        publish_layout_dispatch(0u, min(compact_variant_count[0u], hir_count));
        publish_layout_dispatch(1u, field_count);
    }
    if (row < field_count)
    {
        HirField field = compact_fields[row];
        if (field.owner < hir_count)
        {
            uint ignored;
            InterlockedMin(semantic_struct_field_start_by_hir[field.owner], row, ignored);
            InterlockedMax(semantic_struct_field_count_by_hir[field.owner],
                           field.ordinal + 1u, ignored);
        }
    }
}
