// Paper-aligned radix bucket-prefix foundation.
//
// GPU-only scheduling contract:
// - Dispatch after type_check_names_radix_00_histogram.slang.
// - Each radix bucket is scanned independently on the GPU to produce the
//   exclusive per-block bucket prefix consumed by stable radix scatter.
// - This helper scans four histogram blocks per lane, covering 1024 blocks per
//   bucket without host-side record inspection.

import radix;

struct Params
{
    uint name_count;
    uint source_len;
    uint n_blocks;
    uint radix_byte_offset;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> name_count_in;
StructuredBuffer<uint> radix_block_histogram;
RWStructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> radix_bucket_total;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint MAX_RADIX_BLOCKS = 1024u;
static const uint SCAN_SLOTS = 1024u;

groupshared uint scan_values[1024];

uint active_name_count()
{
    return min(name_count_in[0], gParams.name_count);
}

uint active_block_count()
{
    return radix_active_block_count(
        active_name_count(),
        gParams.n_blocks,
        WG_SIZE,
        MAX_RADIX_BLOCKS);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint bucket = gid.x;
    if (bucket >= RADIX_BUCKETS)
        return;

    radix_bucket_prefix_scan_4<256, 1024>(
        ltid.x,
        bucket,
        active_block_count(),
        RADIX_BUCKETS,
        radix_block_histogram,
        radix_block_bucket_prefix,
        radix_bucket_total,
        scan_values);
}
