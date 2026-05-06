struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<int> block_sum;
StructuredBuffer<int> prefix_in;

RWStructuredBuffer<int> prefix_out;
RWStructuredBuffer<int> block_prefix;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_blocks)
        return;

    if (gParams.scan_step == 0u)
    {
        prefix_out[i] = block_sum[i];
        return;
    }

    if (gParams.scan_step < gParams.n_blocks)
    {
        int sum = prefix_in[i];
        if (i >= gParams.scan_step)
            sum += prefix_in[i - gParams.scan_step];
        prefix_out[i] = sum;
        return;
    }

    block_prefix[i] = i == 0u ? 0 : prefix_in[i - 1u];
}
