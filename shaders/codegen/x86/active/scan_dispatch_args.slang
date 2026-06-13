// Build x86 scan dispatch arguments from GPU-resident active HIR count.
//
// Node-local scans need one extra slot beyond the active HIR node range so
// subtree_end == active_count can be queried without a host readback.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
RWStructuredBuffer<uint> active_hir_count_dispatch_args;
RWStructuredBuffer<uint> active_hir_plus_one_dispatch_args;
RWStructuredBuffer<uint> active_hir_scan_block_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

void write_dispatch_args(RWStructuredBuffer<uint> args, uint active_records)
{
    uint groups = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[2u] = 1u;
    args[3u] = active_records;
}

void write_scan_block_dispatch_args(RWStructuredBuffer<uint> args, uint active_records)
{
    uint active_blocks = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    write_dispatch_args(args, active_blocks);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0u || tid.y != 0u || tid.z != 0u)
        return;

    uint active = active_hir_node_count();
    uint active_plus_one = min(gParams.n_hir_nodes + 1u, active + 1u);
    write_dispatch_args(active_hir_count_dispatch_args, active);
    write_dispatch_args(active_hir_plus_one_dispatch_args, active_plus_one);
    write_scan_block_dispatch_args(active_hir_scan_block_dispatch_args, active_plus_one);
}
