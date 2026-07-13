import gpu_index;
import radix;
import scatter;

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
StructuredBuffer<uint> sc_stream;
StructuredBuffer<uint> layer;
StructuredBuffer<uint> order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> order_out;
RWStructuredBuffer<uint> slot_for_index;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = 256u;
static const uint SMALL_PAIR_CAPACITY = 2048u;
static const uint WG_SIZE = 256u;
static const uint VIRTUAL_WARP_SIZE = 32u;
static const uint VIRTUAL_WARP_COUNT = WG_SIZE / VIRTUAL_WARP_SIZE;
groupshared uint local_radix_warp_pop[VIRTUAL_WARP_COUNT][RADIX_BUCKETS];
groupshared uint local_radix_digits[WG_SIZE];

uint pair_active_count()
{
    return min(gParams.n_sc, partial_parse_status[4u]);
}

uint pair_key(uint row)
{
    uint kind = (sc_stream[row] & 1u) == 1u ? 0u : 1u;
    return layer[row] * 2u + kind;
}

uint stable_local_rank(uint lane, uint key, bool active)
{
    // This is the proven layout used by the renderer radix sort in
    // ~/code/game: each lane clears one bucket for all eight virtual warps,
    // then active lanes atomically publish their per-warp digit population.
    [unroll]
    for (uint warp = 0u; warp < VIRTUAL_WARP_COUNT; warp += 1u)
        local_radix_warp_pop[warp][lane] = 0u;
    GroupMemoryBarrierWithGroupSync();

    uint virtual_warp = lane / VIRTUAL_WARP_SIZE;
    uint warp_lane = lane & (VIRTUAL_WARP_SIZE - 1u);
    if (active)
    {
        uint prior = 0u;
        InterlockedAdd(local_radix_warp_pop[virtual_warp][key], 1u, prior);
    }
    local_radix_digits[lane] = active ? key : INVALID;
    GroupMemoryBarrierWithGroupSync();

    if (!active)
        return 0u;
    uint rank_in_warp = 0u;
    uint warp_base = virtual_warp * VIRTUAL_WARP_SIZE;
    for (uint prior_lane = 0u; prior_lane < warp_lane; prior_lane += 1u)
        rank_in_warp += uint(local_radix_digits[warp_base + prior_lane] == key);

    uint rank_in_prior_warps = 0u;
    [unroll]
    for (uint warp = 0u; warp < virtual_warp; warp += 1u)
        rank_in_prior_warps += local_radix_warp_pop[warp][key];
    return rank_in_prior_warps + rank_in_warp;
}

public struct PairOrderSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        order_out[dst] = value;
        if (gParams.key_step == 3u)
            slot_for_index[value] = dst;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint n = pair_active_count();
    if (n <= SMALL_PAIR_CAPACITY)
        return;
    uint maxKey = (uint)max(depths_out[2], 0) * 2u + 1u;
    bool keyStepActive = gParams.key_step == 0u || (maxKey >> (gParams.key_step * 8u)) != 0u;
    if (!keyStepActive)
    {
        uint orderI = linear_group_id_2d(gid, MAX_GROUPS_X) * 256u + ltid.x;
        if (orderI < n)
        {
            uint value = order_in[orderI];
            order_out[orderI] = value;
            if (gParams.key_step == 3u)
                slot_for_index[value] = orderI;
        }
        return;
    }
    uint block_idx = linear_group_id_2d(gid, MAX_GROUPS_X);
    if (block_idx >= gParams.n_blocks)
        return;
    uint order_i = block_idx * WG_SIZE + ltid.x;
    bool active = order_i < n;
    uint value = active ? order_in[order_i] : INVALID;
    uint key = active ? radix_byte_key(pair_key(value), gParams.key_step) : INVALID;
    uint local_rank = stable_local_rank(ltid.x, key, active);
    if (!active)
        return;

    uint prefix_slot = radix_block_bucket_slot(block_idx, key, RADIX_BUCKETS);
    uint dst = stable_radix_dst(
        radix_bucket_base[key],
        radix_block_bucket_prefix[prefix_slot],
        local_rank);
    scatter_emit<uint, PairOrderSink>(dst, n, value);
}
