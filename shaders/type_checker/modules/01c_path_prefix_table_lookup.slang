// Canonicalizes exact prefix pairs after the insertion dispatch. All equal
// pairs choose the first equal occupied slot in their common probe sequence;
// unequal pairs remain distinct even when their placement hashes collide.

import gpu_index;
import status;
import type_checker.modules.path_prefix_common;

struct Params { uint segment_capacity; uint step; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_segment_count_out;
StructuredBuffer<uint> path_prefix_base;
StructuredBuffer<uint> path_prefix_id_in;
StructuredBuffer<uint> path_prefix_table_state;
StructuredBuffer<uint> path_prefix_table_left;
StructuredBuffer<uint> path_prefix_table_right;
RWStructuredBuffer<uint> path_prefix_id_out;
RWStructuredBuffer<uint> status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint ERR_PATH_PREFIX_TABLE = 58u;

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
        if (state == PATH_PREFIX_TABLE_EMPTY)
            break;
        if (state == PATH_PREFIX_TABLE_OCCUPIED &&
            path_prefix_table_left[slot] == key.x &&
            path_prefix_table_right[slot] == key.y)
        {
            path_prefix_id_out[row] = slot;
            return;
        }
    }

    path_prefix_id_out[row] = PATH_PREFIX_INVALID;
    record_min_token_error(status, row, ERR_PATH_PREFIX_TABLE, gParams.step);
}
