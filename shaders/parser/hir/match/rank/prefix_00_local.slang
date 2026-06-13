// Mark match arm/pattern-payload nodes and compute block-local prefixes.

import generated_parse_production_ids;
import prefix_scan;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirMatch;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;

RWStructuredBuffer<uint> hir_match_rank_flag;
RWStructuredBuffer<uint> hir_match_rank_local_prefix;
RWStructuredBuffer<uint> hir_match_rank_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirMatch.uses_status_count != 0u ? min(gHirMatch.n, tree_count_status[5u])
                                    : gHirMatch.n;
}

bool is_pattern_production(uint prod)
{
    return prod == PROD_PATTERN_IDENT || prod == PROD_PATTERN_INT ||
           prod == PROD_PATTERN_TRUE || prod == PROD_PATTERN_FALSE;
}

uint match_rank_flag(uint node, uint active)
{
    if (node >= active)
        return 0u;
    uint prod = node_kind[node];
    return prod == PROD_MATCH_ARM || is_pattern_production(prod) ? 1u : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;
    uint active = active_node_count();
    uint flag = match_rank_flag(node, active);
    uint inclusive = prefix_scan_u32_256(lane, flag);

    if (node < gHirMatch.n)
    {
        hir_match_rank_flag[node] = flag;
        hir_match_rank_local_prefix[node] = inclusive - flag;
    }

    if (lane == WG_SIZE - 1u)
        hir_match_rank_block_sum[block_i] = inclusive;
}
