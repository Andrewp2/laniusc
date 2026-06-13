// Mark enum variant/payload nodes and compute block-local prefixes.
//
// The block-prefix scan uses the shared semantic prefix-scan shader, but this
// rank family owns separate record buffers so it cannot clobber HIR compaction
// or another list-rank family.

import generated_parse_production_ids;
import prefix_scan;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirEnum;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_enum_rank_flag;
RWStructuredBuffer<uint> hir_enum_rank_local_prefix;
RWStructuredBuffer<uint> hir_enum_rank_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirEnum.uses_status_count != 0u ? min(gHirEnum.n, tree_count_status[5u])
                                   : gHirEnum.n;
}

uint enum_rank_flag(uint node, uint active)
{
    if (node >= active)
        return 0u;
    return node_kind[node] == PROD_ENUM_VARIANT || hir_kind[node] == HIR_TYPE
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
    uint flag = enum_rank_flag(node, active);
    uint inclusive = prefix_scan_u32_256(lane, flag);

    if (node < gHirEnum.n)
    {
        hir_enum_rank_flag[node] = flag;
        hir_enum_rank_local_prefix[node] = inclusive - flag;
    }

    if (lane == WG_SIZE - 1u)
        hir_enum_rank_block_sum[block_i] = inclusive;
}
