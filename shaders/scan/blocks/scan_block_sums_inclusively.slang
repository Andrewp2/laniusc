// Inclusive scan over precomputed block sums, in one workgroup.
//
// Each lane sums ROWS_PER_LANE consecutive block sums of a chunk, the
// workgroup scans the lane sums, and each lane then writes its rows from
// its offset. Chunks run in order and carry the running total, so a
// capacity of n blocks takes ceil(n / 2048) chunk steps in one dispatch.

struct Params
{
    uint n_blocks;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gBlockScan;
StructuredBuffer<uint> block_sum;
RWStructuredBuffer<uint> block_prefix;

static const uint WG_SIZE = 256u;
static const uint ROWS_PER_LANE = 8u;
static const uint CHUNK_ROWS = WG_SIZE * ROWS_PER_LANE;

groupshared uint g_lanes[WG_SIZE];

// The sum of the values of the lanes before `lane`; `total` is the sum of
// every lane's value. Every lane of the workgroup calls it.
uint workgroup_exclusive(uint lane, uint value, out uint total)
{
    g_lanes[lane] = value;
    GroupMemoryBarrierWithGroupSync();
    for (uint offset = 1u; offset < WG_SIZE; offset <<= 1u)
    {
        uint add = lane >= offset ? g_lanes[lane - offset] : 0u;
        GroupMemoryBarrierWithGroupSync();
        g_lanes[lane] += add;
        GroupMemoryBarrierWithGroupSync();
    }
    total = g_lanes[WG_SIZE - 1u];
    uint inclusive = g_lanes[lane];
    GroupMemoryBarrierWithGroupSync();
    return inclusive - value;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group_id: SV_GroupID, uint3 local_id: SV_GroupThreadID)
{
    if (group_id.x != 0u || group_id.y != 0u)
        return;
    uint n_blocks = gBlockScan.n_blocks;
    uint lane = local_id.x;
    uint carry = 0u;
    for (uint chunk = 0u; chunk < n_blocks; chunk += CHUNK_ROWS)
    {
        uint first = chunk + lane * ROWS_PER_LANE;
        uint sum = 0u;
        for (uint row = 0u; row < ROWS_PER_LANE; ++row)
        {
            if (first + row < n_blocks)
                sum += block_sum[first + row];
        }
        uint total;
        uint running = carry + workgroup_exclusive(lane, sum, total);
        for (uint row = 0u; row < ROWS_PER_LANE; ++row)
        {
            uint index = first + row;
            if (index < n_blocks)
            {
                running += block_sum[index];
                block_prefix[index] = running;
            }
        }
        carry += total;
    }
}
