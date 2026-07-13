// Lower-workgroup-storage fallback for stable bracket-pair radix scatter.
// The native fast path uses virtual-warp histograms; this path performs eight
// stable binary partitions with parallel prefix scans and fits WebGPU-baseline
// workgroup storage limits.

import gpu_index;
import prefix_scan;
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
groupshared uint local_radix_keys_a[WG_SIZE];
groupshared uint local_radix_keys_b[WG_SIZE];
groupshared uint local_radix_values_a[WG_SIZE];
groupshared uint local_radix_values_b[WG_SIZE];
groupshared uint local_radix_scan[WG_SIZE];
groupshared uint local_radix_bucket_start[RADIX_BUCKETS];

uint pair_active_count()
{
    return min(gParams.n_sc, partial_parse_status[4u]);
}

uint pair_key(uint row)
{
    uint kind = (sc_stream[row] & 1u) == 1u ? 0u : 1u;
    return layer[row] * 2u + kind;
}

void stable_sort_block_byte(uint lane, uint key, uint value)
{
    local_radix_keys_a[lane] = key;
    local_radix_values_a[lane] = value;
    GroupMemoryBarrierWithGroupSync();

    for (uint bit = 0u; bit < 8u; bit += 1u)
    {
        bool read_a = (bit & 1u) == 0u;
        uint bit_key = read_a ? local_radix_keys_a[lane] : local_radix_keys_b[lane];
        uint bit_value = read_a ? local_radix_values_a[lane] : local_radix_values_b[lane];
        uint zero = ((bit_key >> bit) & 1u) == 0u ? 1u : 0u;
        uint inclusive_zero = prefix_scan_inclusive<
            uint,
            PrefixScanU32Add,
            WG_SIZE>(lane, zero, local_radix_scan);
        uint exclusive_zero = inclusive_zero - zero;
        uint zeros_total = local_radix_scan[WG_SIZE - 1u];
        uint ones_before = lane - exclusive_zero;
        uint dst = zero != 0u ? exclusive_zero : zeros_total + ones_before;
        if (read_a)
        {
            local_radix_keys_b[dst] = bit_key;
            local_radix_values_b[dst] = bit_value;
        }
        else
        {
            local_radix_keys_a[dst] = bit_key;
            local_radix_values_a[dst] = bit_value;
        }
        GroupMemoryBarrierWithGroupSync();
    }
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
    uint max_key = (uint)max(depths_out[2], 0) * 2u + 1u;
    bool key_step_active =
        gParams.key_step == 0u || (max_key >> (gParams.key_step * 8u)) != 0u;
    uint block_idx = linear_group_id_2d(gid, MAX_GROUPS_X);
    uint order_i = block_idx * WG_SIZE + ltid.x;
    if (!key_step_active)
    {
        if (order_i < n)
        {
            uint value = order_in[order_i];
            order_out[order_i] = value;
            if (gParams.key_step == 3u)
                slot_for_index[value] = order_i;
        }
        return;
    }
    if (block_idx >= gParams.n_blocks)
        return;

    uint value = order_i < n ? order_in[order_i] : INVALID;
    uint key = order_i < n ? radix_byte_key(pair_key(value), gParams.key_step) : INVALID;
    stable_sort_block_byte(ltid.x, key, value);

    key = local_radix_keys_a[ltid.x];
    value = local_radix_values_a[ltid.x];
    local_radix_bucket_start[ltid.x] = INVALID;
    GroupMemoryBarrierWithGroupSync();
    if (value != INVALID &&
        (ltid.x == 0u || key != local_radix_keys_a[ltid.x - 1u]))
        local_radix_bucket_start[key] = ltid.x;
    GroupMemoryBarrierWithGroupSync();
    if (value == INVALID)
        return;

    uint local_rank = ltid.x - local_radix_bucket_start[key];
    uint prefix_slot = radix_block_bucket_slot(block_idx, key, RADIX_BUCKETS);
    uint dst = stable_radix_dst(
        radix_bucket_base[key],
        radix_block_bucket_prefix[prefix_slot],
        local_rank);
    scatter_emit<uint, PairOrderSink>(dst, n, value);
}
