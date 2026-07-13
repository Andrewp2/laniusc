import radix;

struct Params
{
    uint n_sc;
    uint n_layers;
    uint n_blocks;
    uint key_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> partial_parse_status;
StructuredBuffer<int> depths_out;
StructuredBuffer<uint> radix_block_histogram;
RWStructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> radix_bucket_total;

static const uint RADIX_BUCKETS = 256u;
static const uint SMALL_PAIR_CAPACITY = 2048u;
groupshared uint lane_totals[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint n = min(gParams.n_sc, partial_parse_status[4u]);
    uint maxKey = (uint)max(depths_out[2], 0) * 2u + 1u;
    bool keyStepActive = gParams.key_step == 0u || (maxKey >> (gParams.key_step * 8u)) != 0u;
    uint activeBuckets = min((maxKey >> (gParams.key_step * 8u)) + 1u, RADIX_BUCKETS);
    if (n <= SMALL_PAIR_CAPACITY || !keyStepActive || gid.x >= activeBuckets)
        return;
    uint active_blocks = min((n + 255u) / 256u, gParams.n_blocks);
    uint blocks_per_lane = (active_blocks + 255u) / 256u;
    uint begin = min(ltid.x * blocks_per_lane, active_blocks);
    uint end = min(begin + blocks_per_lane, active_blocks);

    uint lane_sum = 0u;
    for (uint block_i = begin; block_i < end; block_i += 1u)
        lane_sum += radix_block_histogram[
            radix_histogram_slot(block_i, gid.x, RADIX_BUCKETS)];
    lane_totals[ltid.x] = lane_sum;
    GroupMemoryBarrierWithGroupSync();

    for (uint offset = 1u; offset < 256u; offset <<= 1u)
    {
        uint addend = ltid.x >= offset ? lane_totals[ltid.x - offset] : 0u;
        GroupMemoryBarrierWithGroupSync();
        lane_totals[ltid.x] += addend;
        GroupMemoryBarrierWithGroupSync();
    }

    uint running = ltid.x == 0u ? 0u : lane_totals[ltid.x - 1u];
    for (uint block_i = begin; block_i < end; block_i += 1u)
    {
        uint slot = radix_histogram_slot(block_i, gid.x, RADIX_BUCKETS);
        radix_block_bucket_prefix[slot] = running;
        running += radix_block_histogram[slot];
    }
    if (ltid.x == 255u)
        radix_bucket_total[gid.x] = lane_totals[255u];
}
