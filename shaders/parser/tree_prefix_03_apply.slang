// Apply scanned block prefixes to local preorder deficits and build block maxima.

struct Params
{
    uint n;
    uint uses_ll1;
    uint n_node_blocks;
    uint n_prefix_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gTree;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<int> prefix_inblock;
StructuredBuffer<int> block_sum;
StructuredBuffer<int> block_prefix;

RWStructuredBuffer<int> tree_prefix;
RWStructuredBuffer<int> prefix_block_max;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const int NEG_INF = -2147483647;

groupshared int s_max[256];

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gTree.uses_ll1 != 0u ? min(gTree.n, ll1_status[5u]) : gTree.n;
}

int prefix_value(uint p)
{
    if (p < gTree.n)
    {
        uint block_idx = p / WG_SIZE;
        return block_prefix[block_idx] + prefix_inblock[p];
    }

    uint last_block = gTree.n_node_blocks - 1u;
    return block_prefix[last_block] + block_sum[last_block];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gTree.n_prefix_blocks)
        return;

    uint lane = ltid.x;
    uint p = block_idx * WG_SIZE + lane;
    uint active_n = active_node_count();

    int value = 0;
    bool in_capacity = p <= gTree.n;
    if (in_capacity)
    {
        value = prefix_value(p);
        tree_prefix[p] = value;
    }

    s_max[lane] = (p <= active_n) ? value : NEG_INF;
    GroupMemoryBarrierWithGroupSync();

    for (uint step = WG_SIZE >> 1; step > 0u; step >>= 1u)
    {
        if (lane < step)
            s_max[lane] = max(s_max[lane], s_max[lane + step]);
        GroupMemoryBarrierWithGroupSync();
    }

    if (lane == 0u)
        prefix_block_max[block_idx] = s_max[0];
}
