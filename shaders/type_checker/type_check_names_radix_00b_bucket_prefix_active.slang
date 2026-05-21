// Name-radix bucket-prefix pass.
//
// This is the name-sort variant of type_check_names_radix_00b_bucket_prefix.
// Name sorting keeps a fixed 64-byte ping-pong schedule so the final sorted
// order buffer has stable parity. For byte offsets above the GPU-produced
// maximum name length, histogram/scatter already preserve that parity without
// consulting bucket totals; this pass can return before doing the bucket scans.

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
StructuredBuffer<uint> name_max_len_in;
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
    if (gParams.radix_byte_offset >= name_max_len_in[0u])
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
