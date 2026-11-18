import gpu_index;
import type_checker.modules.decl_lookup;

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> decl_lookup_state;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
    if (row < decl_lookup_capacity(gParams.decl_capacity))
        decl_lookup_state[row] = DECL_LOOKUP_EMPTY;
}
