import gpu_index;

struct Params
{
    uint n_sc;
};

ConstantBuffer<Params> gClear;
StructuredBuffer<uint> partial_parse_status;
RWStructuredBuffer<uint> match_for_index;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint n = min(gClear.n_sc, partial_parse_status[4u]);
    if (i < n)
        match_for_index[i] = INVALID;
}
