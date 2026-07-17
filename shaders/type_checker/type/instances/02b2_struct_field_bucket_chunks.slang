// Exclusive scan of per-chunk struct-field radix totals.

import prefix_scan;
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
RWStructuredBuffer<uint> radix_block_histogram;
RWStructuredBuffer<uint> radix_bucket_total;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint BLOCKS_PER_CHUNK = 256u;
groupshared uint scan_values[256];

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
    uint bucket = gid.x;
    if (bucket >= RADIX_BUCKETS)
        return;
    uint chunk_count = (active_block_count() + BLOCKS_PER_CHUNK - 1u) / BLOCKS_PER_CHUNK;
    uint chunk = ltid.x;
    uint first_block = chunk * BLOCKS_PER_CHUNK;
    uint value = chunk < chunk_count
        ? radix_block_histogram[radix_histogram_slot(first_block, bucket, RADIX_BUCKETS)]
        : 0u;
    uint inclusive = prefix_scan_inclusive<uint, PrefixScanU32Add, 256>(
        ltid.x, value, scan_values);
    if (chunk < chunk_count)
        radix_block_histogram[radix_histogram_slot(first_block, bucket, RADIX_BUCKETS)] =
            inclusive - value;
    if (ltid.x == WG_SIZE - 1u)
        radix_bucket_total[bucket] = inclusive;
}
