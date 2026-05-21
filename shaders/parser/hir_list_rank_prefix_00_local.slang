// Mark owner/link-seeded HIR list nodes and compute block-local prefixes.
//
// This generic pass is used for single-list pointer-jump families where the
// seed pass has already written owner/link records. It consumes those records
// directly rather than rediscovering list membership from grammar productions.

import prefix_scan;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirList;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_list_owner_a;
StructuredBuffer<uint> hir_list_link_a;

RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_local_prefix;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirList.uses_ll1 != 0u ? min(gHirList.n, ll1_status[5u])
                                   : gHirList.n;
}

bool valid_node(uint node, uint active)
{
    return node != INVALID && node < active;
}

uint list_rank_flag(uint node, uint active)
{
    if (node >= active)
        return 0u;
    return valid_node(hir_list_owner_a[node], active) ||
           valid_node(hir_list_link_a[node], active)
        ? 1u
        : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;
    uint active = active_node_count();
    uint flag = list_rank_flag(node, active);
    uint inclusive = prefix_scan_u32_256(lane, flag);

    if (node < gHirList.n)
    {
        hir_list_rank_flag[node] = flag;
        hir_list_rank_local_prefix[node] = inclusive - flag;
    }

    if (lane == WG_SIZE - 1u)
        hir_list_rank_block_sum[block_i] = inclusive;
}
