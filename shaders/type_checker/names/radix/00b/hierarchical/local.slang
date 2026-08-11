// Per-chunk exclusive prefixes for a radix histogram.

import gpu_index;
import prefix_scan;
import radix;

struct Params
{
    uint item_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> radix_count;
RWStructuredBuffer<uint> radix_block_histogram;
RWStructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> radix_bucket_total;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint BLOCKS_PER_CHUNK = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared uint scan_values[256];

uint active_block_count()
{
    return radix_active_block_count(
        min(radix_count[0u], gParams.item_capacity),
        gParams.n_blocks,
        WG_SIZE,
        gParams.n_blocks);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group = linear_group_id_2d(gid, MAX_GROUPS_X);
    uint bucket = group % RADIX_BUCKETS;
    uint chunk = group / RADIX_BUCKETS;
    uint block = chunk * BLOCKS_PER_CHUNK + ltid.x;
    uint block_count = active_block_count();
    uint value = block < block_count
        ? radix_block_histogram[radix_histogram_slot(block, bucket, RADIX_BUCKETS)]
        : 0u;
    uint inclusive = prefix_scan_inclusive<uint, PrefixScanU32Add, 256>(
        ltid.x, value, scan_values);
    if (block < block_count)
        radix_block_bucket_prefix[radix_histogram_slot(block, bucket, RADIX_BUCKETS)] =
            inclusive - value;
    if (ltid.x == WG_SIZE - 1u)
    {
        uint first_block = chunk * BLOCKS_PER_CHUNK;
        if (first_block < gParams.n_blocks)
            radix_block_histogram[radix_histogram_slot(first_block, bucket, RADIX_BUCKETS)] =
                inclusive;
        if (chunk == 0u)
            radix_bucket_total[bucket] = 0u;
    }
}
