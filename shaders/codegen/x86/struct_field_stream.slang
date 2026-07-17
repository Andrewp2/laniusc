// x86_64 dense struct-field stream scatter.
//
// Field declaration HIR rows are not assumed to be contiguous. This pass uses
// scanned per-struct field counts to scatter each field width to a dense
// declaration-order stream at base(parent_struct) + field_ordinal.

import gpu_index;
import prefix_scan;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> x86_struct_field_width_by_node;
StructuredBuffer<uint> x86_struct_field_base_scan_local_prefix;
StructuredBuffer<uint> x86_struct_field_base_scan_block_prefix;

RWStructuredBuffer<uint> x86_struct_field_stream_width;
RWStructuredBuffer<uint> x86_struct_field_stream_index_by_node;
RWStructuredBuffer<uint> x86_struct_field_base_by_hir;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint HIR_STRUCT_ITEM = 27u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint scanned_struct_base(uint struct_node)
{
    return global_exclusive_prefix(
        struct_node,
        WG_SIZE,
        x86_struct_field_base_scan_local_prefix,
        x86_struct_field_base_scan_block_prefix);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint field_count = min(compact_field_count[0u], gParams.n_hir_nodes);
    if (node >= field_count)
        return;

    HirField field = compact_fields[node];
    uint struct_node = field.owner;
    uint ordinal = field.ordinal;
    if (!valid_node(struct_node) ||
        compact_hir_core[struct_node].kind != HIR_STRUCT_ITEM ||
        ordinal == INVALID)
        return;

    uint stream_i = scanned_struct_base(struct_node) + ordinal;
    if (stream_i >= active_hir_node_count())
        return;

    x86_struct_field_base_by_hir[struct_node] = stream_i - ordinal;
    x86_struct_field_stream_width[stream_i] = x86_struct_field_width_by_node[node];
    x86_struct_field_stream_index_by_node[node] = stream_i;
}
