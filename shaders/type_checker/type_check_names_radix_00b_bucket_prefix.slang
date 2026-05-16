// Paper-aligned name radix bucket-prefix foundation.
//
// GPU-only scheduling contract:
// - Dispatch after type_check_names_radix_00_histogram.slang.
// - Each radix bucket is scanned independently on the GPU to produce the
//   exclusive per-block bucket prefix consumed by stable radix scatter.
// - This first helper supports up to 256 histogram blocks per bucket. It is a
//   GPU scheduling bound with no host-side name inspection.

struct Params
{
    uint name_count;
    uint source_len;
    uint n_blocks;
    uint radix_byte_offset;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> radix_block_histogram;
RWStructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> radix_bucket_total;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = 257u;
static const uint MAX_RADIX_BLOCKS = 256u;

groupshared uint scan_values[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint bucket = gid.x;
    if (bucket >= RADIX_BUCKETS)
        return;

    uint lane = ltid.x;
    uint block_i = lane;
    uint value = block_i < min(gParams.n_blocks, MAX_RADIX_BLOCKS)
                     ? radix_block_histogram[block_i * RADIX_BUCKETS + bucket]
                     : 0u;

    scan_values[lane] = value;
    GroupMemoryBarrierWithGroupSync();

    [unroll]
    for (uint offset = 1u; offset < WG_SIZE; offset <<= 1u)
    {
        uint addend = lane >= offset ? scan_values[lane - offset] : 0u;
        GroupMemoryBarrierWithGroupSync();
        scan_values[lane] += addend;
        GroupMemoryBarrierWithGroupSync();
    }

    if (block_i < min(gParams.n_blocks, MAX_RADIX_BLOCKS))
        radix_block_bucket_prefix[block_i * RADIX_BUCKETS + bucket] = scan_values[lane] - value;

    if (lane == WG_SIZE - 1u)
        radix_bucket_total[bucket] = scan_values[lane];
}
