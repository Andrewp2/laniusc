// x86_64 owning-function HIR-order local scan.
//
// Pareas assigns function-local data from the node stream with scans, using
// function declarations as segment starts. This pass seeds that same shape for
// the native backend: each executable function item publishes node + 1, then a
// prefix max carries the most recent owning function through the HIR stream.
// Trait method signatures can be HIR_FN records, but they are not executable
// function items and must not become ownership segment starts.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_item_kind;

RWStructuredBuffer<uint> x86_func_owner_scan_local_prefix;
RWStructuredBuffer<uint> x86_func_owner_scan_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_FN = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_hir_node_count()
{
    return gScan.n_items == 0u ? 0u : min(gScan.n_items, hir_status[5u]);
}

uint function_owner_seed(uint node_i)
{
    return node_i < active_hir_node_count() &&
                   hir_kind[node_i] == HIR_FN &&
                   hir_item_kind[node_i] == HIR_ITEM_KIND_FN
               ? node_i + 1u
               : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    if (block_i >= gScan.n_blocks)
        return;

    uint lane = ltid.x;
    uint i = block_i * WG_SIZE + lane;
    uint value = i < gScan.n_items ? function_owner_seed(i) : 0u;
    uint inclusive = prefix_scan_u32_max_256(lane, value);

    if (i < gScan.n_items)
        x86_func_owner_scan_local_prefix[i] = inclusive;
    if (lane == WG_SIZE - 1u)
        x86_func_owner_scan_block_sum[block_i] = inclusive;
}
