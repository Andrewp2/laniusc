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

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_ordinal;
StructuredBuffer<uint> x86_struct_field_width_by_node;
StructuredBuffer<uint> x86_struct_field_base_scan_local_prefix;
StructuredBuffer<uint> x86_struct_field_base_scan_block_prefix;

RWStructuredBuffer<uint> x86_struct_field_stream_width;
RWStructuredBuffer<uint> x86_struct_field_stream_index_by_node;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
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
    if (!valid_node(node))
        return;

    x86_struct_field_stream_index_by_node[node] = INVALID;
    x86_struct_field_stream_width[node] = 0u;

    uint struct_node = hir_struct_field_parent_struct[node];
    uint ordinal = hir_struct_field_ordinal[node];
    if (!valid_node(struct_node) || ordinal == INVALID)
        return;

    uint stream_i = scanned_struct_base(struct_node) + ordinal;
    if (stream_i >= active_hir_node_count())
        return;

    x86_struct_field_stream_width[stream_i] = x86_struct_field_width_by_node[node];
    x86_struct_field_stream_index_by_node[node] = stream_i;
}
