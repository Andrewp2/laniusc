// Paper-aligned name radix bucket-base foundation.
//
// GPU-only scheduling contract:
// - Dispatch after type_check_names_radix_00b_bucket_prefix.slang writes
//   radix_bucket_total.
// - This pass performs a GPU prefix scan over radix bucket totals and writes
//   radix_bucket_base for the stable scatter pass.
// - The host only schedules the pass and binds buffers.

struct Params
{
    uint name_count;
    uint source_len;
    uint n_blocks;
    uint radix_byte_offset;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> radix_bucket_total;
RWStructuredBuffer<uint> radix_bucket_base;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = 257u;
static const uint SCAN_SLOTS = 512u;

groupshared uint scan_values[512];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint second = lane + WG_SIZE;
    uint value0 = lane < RADIX_BUCKETS ? radix_bucket_total[lane] : 0u;
    uint value1 = second < RADIX_BUCKETS ? radix_bucket_total[second] : 0u;

    scan_values[lane] = value0;
    scan_values[second] = value1;
    GroupMemoryBarrierWithGroupSync();

    [unroll]
    for (uint offset = 1u; offset < SCAN_SLOTS; offset <<= 1u)
    {
        uint add0 = lane >= offset ? scan_values[lane - offset] : 0u;
        uint add1 = second >= offset ? scan_values[second - offset] : 0u;
        GroupMemoryBarrierWithGroupSync();
        scan_values[lane] += add0;
        scan_values[second] += add1;
        GroupMemoryBarrierWithGroupSync();
    }

    if (lane < RADIX_BUCKETS)
        radix_bucket_base[lane] = scan_values[lane] - value0;
    if (second < RADIX_BUCKETS)
        radix_bucket_base[second] = scan_values[second] - value1;
}
