// Clear per-owner parameter segment bases before segmented ordinal assignment.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirParam;

RWStructuredBuffer<uint> hir_param_rank_b;

static const uint INVALID = 0xffffffffu;
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
    uint node = linear_thread_id(dtid);
    if (node < gHirParam.n)
        hir_param_rank_b[node] = INVALID;
}
