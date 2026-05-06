struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

RWStructuredBuffer<int> loop_delta;

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
    if (i <= gParams.n_tokens)
        loop_delta[i] = 0;
}
