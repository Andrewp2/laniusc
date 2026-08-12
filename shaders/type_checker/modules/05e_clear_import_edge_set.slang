// Clears the exact resolved-import hash set before one compilation job.

import gpu_index;
import type_checker.modules.import_edge_set;

struct Params
{
    uint import_capacity;
    uint path_capacity;
    uint path_segment_capacity;
    uint module_capacity;
    uint dependency_interfaces_present;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> import_edge_set_state;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
    if (row < import_edge_set_capacity(gParams.import_capacity))
        import_edge_set_state[row] = IMPORT_EDGE_SET_EMPTY;
}
