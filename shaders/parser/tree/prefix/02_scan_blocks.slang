// Exclusive scan over preorder tree prefix block sums, in one workgroup.

struct Params
{
    uint n;
    uint uses_status_count;
    uint n_node_blocks;
    uint n_prefix_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gTree;

StructuredBuffer<int> block_sum;
RWStructuredBuffer<int> block_prefix;

static const uint WG_SIZE = 256u;
static const uint ROWS_PER_LANE = 8u;
static const uint CHUNK_ROWS = WG_SIZE * ROWS_PER_LANE;

groupshared int g_lanes[WG_SIZE];

// The sum of the values of the lanes before `lane`; `total` is the sum of
// every lane's value. Every lane of the workgroup calls it.
int workgroup_exclusive(uint lane, int value, out int total)
{
    g_lanes[lane] = value;
    GroupMemoryBarrierWithGroupSync();
    for (uint offset = 1u; offset < WG_SIZE; offset <<= 1u)
    {
        int add = lane >= offset ? g_lanes[lane - offset] : 0;
        GroupMemoryBarrierWithGroupSync();
        g_lanes[lane] += add;
        GroupMemoryBarrierWithGroupSync();
    }
    total = g_lanes[WG_SIZE - 1u];
    int inclusive = g_lanes[lane];
    GroupMemoryBarrierWithGroupSync();
    return inclusive - value;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group_id: SV_GroupID, uint3 local_id: SV_GroupThreadID)
{
    if (group_id.x != 0u || group_id.y != 0u)
        return;
    uint n_blocks = gTree.n_node_blocks;
    uint lane = local_id.x;
    int carry = 0;
    for (uint chunk = 0u; chunk < n_blocks; chunk += CHUNK_ROWS)
    {
        uint first = chunk + lane * ROWS_PER_LANE;
        int sum = 0;
        for (uint row = 0u; row < ROWS_PER_LANE; ++row)
        {
            if (first + row < n_blocks)
                sum += block_sum[first + row];
        }
        int total;
        int running = carry + workgroup_exclusive(lane, sum, total);
        for (uint row = 0u; row < ROWS_PER_LANE; ++row)
        {
            uint index = first + row;
            if (index < n_blocks)
            {
                block_prefix[index] = running;
                running += block_sum[index];
            }
        }
        carry += total;
    }
}
