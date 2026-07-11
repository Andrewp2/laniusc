import radix;

struct Params
{
    uint n_sc;
    uint n_layers;
    uint n_blocks;
    uint key_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> partial_parse_status;
StructuredBuffer<int> depths_out;
StructuredBuffer<uint> radix_bucket_total;
RWStructuredBuffer<uint> radix_bucket_base;

static const uint RADIX_BUCKETS = 256u;
static const uint SMALL_PAIR_CAPACITY = 2048u;
groupshared uint scan_values[512];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint n = min(gParams.n_sc, partial_parse_status[4u]);
    uint maxKey = (uint)max(depths_out[2], 0) * 2u + 1u;
    bool keyStepActive = gParams.key_step == 0u || (maxKey >> (gParams.key_step * 8u)) != 0u;
    if (n <= SMALL_PAIR_CAPACITY || !keyStepActive)
        return;
    radix_bucket_base_scan_2<256, 512>(
        ltid.x,
        RADIX_BUCKETS,
        radix_bucket_total,
        radix_bucket_base,
        scan_values);
}
