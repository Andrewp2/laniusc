// Scatter struct declaration/literal field nodes into a dense rank worklist
// and publish indirect dispatch args for the pointer-jump rank pass.

import prefix_scan;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirStruct;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_struct_rank_flag;
StructuredBuffer<uint> hir_struct_rank_local_prefix;
StructuredBuffer<uint> hir_struct_rank_block_prefix;

RWStructuredBuffer<uint> hir_struct_rank_node;
RWStructuredBuffer<uint> hir_struct_rank_count;
RWStructuredBuffer<uint> hir_struct_rank_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirStruct.uses_status_count != 0u ? min(gHirStruct.n, tree_count_status[5u])
                                     : gHirStruct.n;
}

uint block_count()
{
    return (gHirStruct.n + WG_SIZE - 1u) / WG_SIZE;
}

void write_dispatch_args(uint active_records)
{
    uint groups = (active_records + WG_SIZE - 1u) / WG_SIZE;
    hir_struct_rank_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    hir_struct_rank_dispatch_args[1u] =
        groups == 0u ? 0u : max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    hir_struct_rank_dispatch_args[2u] = groups == 0u ? 0u : 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint rank_count = inclusive_scan_total(block_count(), hir_struct_rank_block_prefix);
    if (node == 0u)
    {
        hir_struct_rank_count[0u] = rank_count;
        write_dispatch_args(rank_count);
    }

    uint active = active_node_count();
    if (node >= gHirStruct.n || node >= active || hir_struct_rank_flag[node] == 0u)
        return;

    uint block_i = node / WG_SIZE;
    uint block_base = block_i == 0u ? 0u : hir_struct_rank_block_prefix[block_i - 1u];
    uint dense_row = block_base + hir_struct_rank_local_prefix[node];
    if (dense_row < gHirStruct.n)
        hir_struct_rank_node[dense_row] = node;
}
