// Local semantic-HIR prefix scan.
//
// This is the first half of a Pareas-style compactification boundary: mark
// parser tree nodes that have semantic HIR meaning, compute per-block exclusive
// prefixes, and publish block sums for the global block-prefix scan.

import prefix_scan;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_semantic_flag;
RWStructuredBuffer<uint> hir_semantic_local_prefix;
RWStructuredBuffer<uint> hir_semantic_block_sum;

static const uint HIR_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirSemantic.uses_ll1 != 0u ? min(gHirSemantic.n, ll1_status[5u]) : gHirSemantic.n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;
    uint active = active_node_count();
    uint flag = node < active && hir_kind[node] != HIR_NONE ? 1u : 0u;
    uint inclusive = prefix_scan_u32_256(lane, flag);

    if (node < gHirSemantic.n)
    {
        hir_semantic_flag[node] = flag;
        hir_semantic_local_prefix[node] = inclusive - flag;
    }

    if (lane == WG_SIZE - 1u)
        hir_semantic_block_sum[block_i] = inclusive;
}
