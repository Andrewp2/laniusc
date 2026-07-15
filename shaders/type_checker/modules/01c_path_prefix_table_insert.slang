// Inserts exact prefix-pair keys into an open-addressed GPU table.
//
// Hashes select probe positions only. Keys are always retained in full. A
// claimed slot is skipped rather than waited on, avoiding cross-workgroup
// spin waits; a following lookup pass canonicalizes any duplicate inserts.

import atomics;
import gpu_index;
import type_checker.modules.path_prefix_common;

struct Params { uint segment_capacity; uint step; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_segment_count_out;
StructuredBuffer<uint> path_prefix_base;
StructuredBuffer<uint> path_prefix_id_in;
RWStructuredBuffer<uint> path_prefix_table_state;
RWStructuredBuffer<uint> path_prefix_table_left;
RWStructuredBuffer<uint> path_prefix_table_right;

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
        if (state == PATH_PREFIX_TABLE_OCCUPIED)
        {
            if (path_prefix_table_left[slot] == key.x &&
                path_prefix_table_right[slot] == key.y)
                return;
            continue;
        }
        if (state != PATH_PREFIX_TABLE_EMPTY)
            continue;

        uint prior = atomic_u32_compare_exchange(
            path_prefix_table_state,
            slot,
            PATH_PREFIX_TABLE_EMPTY,
            PATH_PREFIX_TABLE_CLAIMED);
        if (prior != PATH_PREFIX_TABLE_EMPTY)
            continue;

        path_prefix_table_left[slot] = key.x;
        path_prefix_table_right[slot] = key.y;
        DeviceMemoryBarrier();
        uint ignored;
        InterlockedExchange(
            path_prefix_table_state[slot],
            PATH_PREFIX_TABLE_OCCUPIED,
            ignored);
        return;
    }
}
