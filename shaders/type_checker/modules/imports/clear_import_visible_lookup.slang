// Clears one exact imported-visibility lookup table.

import gpu_index;
import type_checker.modules.import_visible_lookup;

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> import_visible_lookup_state;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
    uint row_capacity = gParams.reserved == 0u ? gParams.capacity : gParams.reserved;
    if (row < import_visible_lookup_capacity(row_capacity))
        import_visible_lookup_state[row] = IMPORT_VISIBLE_LOOKUP_EMPTY;
}
