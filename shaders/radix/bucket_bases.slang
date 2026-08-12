// Shared radix bucket-base pass.
//
// GPU-only scheduling contract:
// - Dispatch after the shared bucket-prefix pass writes radix_bucket_total.
// - This pass performs a GPU prefix scan over radix bucket totals and writes
//   radix_bucket_base for the stable scatter pass.
// - The host only schedules the pass and binds buffers.

import radix;
import prefix_scan;

struct Params
{
    uint item_capacity;
    uint reserved;
    uint max_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> radix_bucket_total;
RWStructuredBuffer<uint> radix_bucket_base;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = RADIX_U8_BUCKETS;

groupshared uint scan_values[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint value = radix_bucket_total[lane];
    uint inclusive = prefix_scan_inclusive<
        uint,
        PrefixScanU32Add,
        256>(lane, value, scan_values);
    radix_bucket_base[lane] = inclusive - value;
}
