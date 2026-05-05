import retag_closes_common;

ConstantBuffer<LexParams> gParams;
StructuredBuffer<int> block_sum;
RWStructuredBuffer<int> block_prefix;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint n_blocks = (gParams.n + 255u) / 256u;
    if (n_blocks == 0u)
        n_blocks = 1u;
    if (tid.x >= n_blocks)
        return;

    int prefix = 0;
    for (uint b = 0u; b < tid.x; b++)
        prefix += block_sum[b];
    block_prefix[tid.x] = prefix;
}
