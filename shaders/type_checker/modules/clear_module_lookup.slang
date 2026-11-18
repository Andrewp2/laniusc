// Clears the path-prefix workspace before reusing it as the direct module table.

import gpu_index;
import type_checker.modules.module_lookup;

struct Params
{
    uint path_capacity;
    uint path_segment_capacity;
    uint module_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> module_by_canonical_id;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
    if (row < module_lookup_capacity(gParams.path_segment_capacity))
        module_by_canonical_id[row] = 0u;
}
