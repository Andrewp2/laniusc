// Places the dynamically selected final doubling result in prefix-id A.

import gpu_index;

struct Params { uint segment_capacity; uint round_count; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_segment_count_out;
StructuredBuffer<uint> path_max_segment_count;
StructuredBuffer<uint> path_prefix_id_b;
RWStructuredBuffer<uint> path_prefix_id_a;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_round_count(uint max_depth)
{
    uint rounds = 0u;
    uint covered = 1u;
    while (covered < max_depth && rounds < gParams.round_count)
    {
        covered <<= 1u;
        rounds += 1u;
    }
    return rounds;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
    uint rows = min(path_segment_count_out[0u], gParams.segment_capacity);
    if (row >= rows)
        return;
    if ((active_round_count(path_max_segment_count[0u]) & 1u) != 0u)
        path_prefix_id_a[row] = path_prefix_id_b[row];
}
