// Adds each scanned chunk prefix to its radix block prefixes.

import gpu_index;
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
StructuredBuffer<uint> radix_block_histogram;
RWStructuredBuffer<uint> radix_block_bucket_prefix;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint BLOCKS_PER_CHUNK = 256u;
static const uint MAX_GROUPS_X = 65535u;

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
    if (block >= active_block_count())
        return;
    uint chunk_prefix = radix_block_histogram[
        radix_histogram_slot(chunk * BLOCKS_PER_CHUNK, bucket, RADIX_BUCKETS)];
    uint slot = radix_histogram_slot(block, bucket, RADIX_BUCKETS);
    radix_block_bucket_prefix[slot] += chunk_prefix;
}
