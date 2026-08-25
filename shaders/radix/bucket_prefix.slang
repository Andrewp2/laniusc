// Shared radix bucket-prefix pass.
//
// GPU-only scheduling contract:
// - Dispatch after the key-specific histogram pass.
// - Each radix bucket is scanned independently on the GPU to produce the
//   exclusive per-block bucket prefix consumed by stable radix scatter.
// - Each lane scans a contiguous share of the active histogram blocks, so the
//   operation has no fixed 4096-block correctness ceiling.

import radix;

struct Params
{
    uint item_capacity;
    uint reserved;
    uint max_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> name_count_in;
StructuredBuffer<uint> radix_block_histogram;
RWStructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> radix_bucket_total;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = RADIX_U8_BUCKETS;
groupshared uint lane_totals[256];

uint active_item_count()
{
    return min(name_count_in[0], gParams.item_capacity);
}

uint active_block_count()
{
    return radix_active_block_count(
        active_item_count(),
        gParams.max_blocks,
        WG_SIZE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint bucket = gid.x;
    if (bucket >= RADIX_BUCKETS)
        return;

    radix_bucket_prefix_scan<256>(
        ltid.x,
        bucket,
        active_block_count(),
        RADIX_BUCKETS,
        radix_block_histogram,
        radix_block_bucket_prefix,
        radix_bucket_total,
        lane_totals);
}
