// Inserts exact prefix-pair keys into an open-addressed GPU table.
//
// Each atomically published table value is the source row plus one. The pair
// is reconstructed from immutable round inputs, so no separately written key
// payload has to become visible to another workgroup after publication.

import atomics;
import gpu_index;
import type_checker.modules.path_prefix_common;

struct Params { uint segment_capacity; uint step; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_segment_count_out;
StructuredBuffer<uint> path_prefix_base;
StructuredBuffer<uint> path_prefix_id_in;
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

    uint capacity = rows * 2u;
    uint2 key = path_prefix_pair(row, gParams.step, path_prefix_base, path_prefix_id_in);
    uint first = path_prefix_first_slot(key.x, key.y, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = (first + probe) % capacity;
        uint state = path_prefix_table_state[slot];
        if (state != PATH_PREFIX_TABLE_EMPTY)
        {
            uint owner = path_prefix_table_owner(state);
            uint2 occupied_key = path_prefix_pair(
                owner,
                gParams.step,
                path_prefix_base,
                path_prefix_id_in);
            if (occupied_key.x == key.x && occupied_key.y == key.y)
                return;
            continue;
        }

        uint prior = atomic_u32_compare_exchange(
            path_prefix_table_state,
            slot,
            PATH_PREFIX_TABLE_EMPTY,
            path_prefix_table_state_for_owner(row));
        if (prior == PATH_PREFIX_TABLE_EMPTY)
            return;

        uint prior_owner = path_prefix_table_owner(prior);
        uint2 prior_key = path_prefix_pair(
            prior_owner,
            gParams.step,
            path_prefix_base,
            path_prefix_id_in);
        if (prior_key.x == key.x && prior_key.y == key.y)
            return;
    }
}
