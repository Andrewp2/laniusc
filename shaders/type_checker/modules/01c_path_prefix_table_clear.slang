// Clears one exact-prefix interning table round. One active row clears two
// slots, giving the table a load factor of at most one half even when every
// row races to publish a duplicate entry.

import gpu_index;

struct Params { uint segment_capacity; uint step; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_segment_count_out;
RWStructuredBuffer<uint> path_prefix_table_state;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
    uint rows = min(path_segment_count_out[0u], gParams.segment_capacity);
    if (row >= rows)
        return;
    path_prefix_table_state[row] = 0u;
    path_prefix_table_state[row + rows] = 0u;
}
