// Adds the scanned chunk prefix to each struct-field radix block prefix.

import gpu_index;
import radix;

struct Params
{
    uint hir_node_capacity;
    uint token_capacity;
    uint n_blocks;
    uint key_step;
    uint radix_bytes;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<uint> radix_block_histogram;
RWStructuredBuffer<uint> radix_block_bucket_prefix;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint BLOCKS_PER_CHUNK = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_block_count()
{
    return radix_active_block_count(
        min(compact_field_count[0u], gParams.hir_node_capacity),
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
