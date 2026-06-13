// Name-radix bucket-base pass.
//
// This name-sort variant consumes the GPU-produced maximum name length so the
// fixed 64-byte parity schedule can skip bucket-base scans for inactive high
// byte offsets. Scatter still preserves ping-pong parity for those offsets.

import radix;

struct Params
{
    uint name_count;
    uint source_len;
    uint n_blocks;
    uint radix_byte_offset;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> name_max_len_in;
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
    if (gParams.radix_byte_offset >= name_max_len_in[0u])
        return;

    radix_bucket_base_scan_2<256, 512>(
        ltid.x,
        RADIX_BUCKETS,
        radix_bucket_total,
        radix_bucket_base,
        scan_values
    );
}
