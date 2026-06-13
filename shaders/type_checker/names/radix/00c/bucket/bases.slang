// Paper-aligned radix bucket-base foundation.
//
// GPU-only scheduling contract:
// - Dispatch after type_check_names_radix_00b_bucket_prefix.slang writes
//   radix_bucket_total.
// - This pass performs a GPU prefix scan over radix bucket totals and writes
//   radix_bucket_base for the stable scatter pass.
// - The host only schedules the pass and binds buffers.

import radix;

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
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint SCAN_SLOTS = 512u;

groupshared uint scan_values[512];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    radix_bucket_base_scan_2<256, 512>(
        ltid.x,
        RADIX_BUCKETS,
        radix_bucket_total,
        radix_bucket_base,
        scan_values
    );
}
