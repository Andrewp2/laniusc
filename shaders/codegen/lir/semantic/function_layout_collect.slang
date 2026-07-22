import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
RWStructuredBuffer<uint> semantic_struct_hir_by_name_token;
RWStructuredBuffer<uint> semantic_struct_field_count_by_hir;

static const uint HIR_STRUCT_ITEM = 27u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (row < hir_count && compact_hir_core[row].kind == HIR_STRUCT_ITEM)
    {
        uint name_token = compact_hir_payload[row].b;
        if (name_token < gParams.n_tokens)
            semantic_struct_hir_by_name_token[name_token] = row;
    }

    uint field_count = min(compact_field_count[0u], gParams.n_hir_nodes);
    if (row < field_count)
    {
        HirField field = compact_fields[row];
        if (field.owner < hir_count)
        {
            uint ignored;
            InterlockedMax(semantic_struct_field_count_by_hir[field.owner],
                           field.ordinal + 1u, ignored);
        }
    }
}
