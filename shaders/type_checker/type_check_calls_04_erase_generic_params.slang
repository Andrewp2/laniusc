struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> call_param_type;

static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint PARAM_CACHE_STRIDE = 16u;
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
    if (i >= gParams.n_tokens * PARAM_CACHE_STRIDE)
        return;

    if (call_param_type[i] >= TY_GENERIC_BASE)
        call_param_type[i] = TY_UNKNOWN;
}
