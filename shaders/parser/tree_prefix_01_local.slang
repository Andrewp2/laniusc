// Preorder tree prefix, block-local stage.
//
// For preorder nodes with production arity a[i], define deficit prefix
// E[p] = sum_{k < p}(1 - a[k]). Parent/span recovery can then search for
// previous/next prefix thresholds instead of replaying subtrees directly.

import prefix_scan;

struct Params
{
    uint n;
    uint uses_ll1;
    uint n_node_blocks;
    uint n_prefix_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gTree;

StructuredBuffer<uint> emit_stream;
StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> prod_arity;

RWStructuredBuffer<uint> node_kind;
RWStructuredBuffer<int> prefix_inblock;
RWStructuredBuffer<int> block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gTree.uses_ll1 != 0u ? min(gTree.n, ll1_status[5u]) : gTree.n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gTree.n_node_blocks)
        return;

    uint lane = ltid.x;
    uint i = block_idx * WG_SIZE + lane;
    uint n = active_node_count();

    int value = 0;
    if (i < n)
    {
        uint kind = emit_stream[i];
        node_kind[i] = kind;
        value = 1 - int(prod_arity[kind]);
    }

    int inclusive = prefix_scan_i32_256(lane, value);
    int exclusive = inclusive - value;

    if (i < gTree.n)
        prefix_inblock[i] = exclusive;

    if (lane + 1u == WG_SIZE)
        block_sum[block_idx] = inclusive;
}
