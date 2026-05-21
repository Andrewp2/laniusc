// Mark struct declaration/literal field nodes and compute block-local prefixes.
//
// The block-prefix scan uses the same generic scan shader as semantic HIR
// compaction, but this family owns separate record buffers.

import generated_parse_production_ids;
import prefix_scan;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirStruct;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;

RWStructuredBuffer<uint> hir_struct_rank_flag;
RWStructuredBuffer<uint> hir_struct_rank_local_prefix;
RWStructuredBuffer<uint> hir_struct_rank_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirStruct.uses_ll1 != 0u ? min(gHirStruct.n, ll1_status[5u])
                                     : gHirStruct.n;
}

uint struct_rank_flag(uint node, uint active)
{
    if (node >= active)
        return 0u;
    uint prod = node_kind[node];
    return (prod == PROD_STRUCT_FIELD || prod == PROD_STRUCT_LIT_FIELD) ? 1u : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;
    uint active = active_node_count();
    uint flag = struct_rank_flag(node, active);
    uint inclusive = prefix_scan_u32_256(lane, flag);

    if (node < gHirStruct.n)
    {
        hir_struct_rank_flag[node] = flag;
        hir_struct_rank_local_prefix[node] = inclusive - flag;
    }

    if (lane == WG_SIZE - 1u)
        hir_struct_rank_block_sum[block_i] = inclusive;
}
