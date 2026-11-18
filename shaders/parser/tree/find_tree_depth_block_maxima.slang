// Per-workgroup raw parse-tree depth summaries from subtree close counts.
//
// In preorder, node i's ancestors are the earlier nodes whose subtrees are
// still open at i, so depth[i] = i - C(i), where C(i) is the number of
// subtrees that end at a position <= i. tree/spans counts the subtrees ending
// at each position in tree_depth_close_count. One workgroup scans its 256
// counts and publishes the block's close total and the maximum of
// i - C_local(i); tree/depth/schedule subtracts each block's preceding closes
// to get the exact maximum depth.
//
// The same lanes check the parent links: a raw parent must be INVALID or an
// earlier node, otherwise the node is reported through tree_depth_status as a
// malformed tree.

import prefix_scan;

struct Params { uint n; uint uses_status_count; uint n_prefix_blocks; uint max_tree_leaf_base; };
ConstantBuffer<Params> gTree;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> tree_depth_close_count;
RWStructuredBuffer<int> tree_depth_block_max;
RWStructuredBuffer<uint> tree_depth_block_close;
RWStructuredBuffer<uint> tree_depth_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const int NO_DEPTH = -2147483647;

groupshared int block_depth[WG_SIZE];

uint linear_thread_id(uint3 tid) { return tid.x + tid.y * MAX_GROUPS_X * WG_SIZE; }
uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_node_count() { return gTree.uses_status_count != 0u ? min(gTree.n, tree_count_status[5u]) : gTree.n; }

[shader("compute")]
[numthreads(WG_SIZE, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID, uint3 gid: SV_GroupID, uint3 lane: SV_GroupThreadID)
{
    uint node = linear_thread_id(tid);
    bool live = node < active_node_count();
    uint closes = live ? tree_depth_close_count[node] : 0u;
    uint closed = prefix_scan_u32_256(lane.x, closes);

    if (live)
    {
        uint up = parent[node];
        if (up != INVALID && up >= node)
            InterlockedMax(tree_depth_status[0u], node + 1u);
    }

    block_depth[lane.x] = live ? int(node) - int(closed) : NO_DEPTH;
    GroupMemoryBarrierWithGroupSync();
    for (uint stride = WG_SIZE / 2u; stride != 0u; stride >>= 1u)
    {
        if (lane.x < stride) block_depth[lane.x] = max(block_depth[lane.x], block_depth[lane.x + stride]);
        GroupMemoryBarrierWithGroupSync();
    }
    if (lane.x == WG_SIZE - 1u)
    {
        uint block = linear_group_id(gid);
        tree_depth_block_max[block] = block_depth[0u];
        tree_depth_block_close[block] = closed;
    }
}
