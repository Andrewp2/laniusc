// Seeds predicate key orders before the GPU radix passes.
//
// Scheduling contract:
// - Dispatch after type_check_predicates_01_collect.slang has written predicate
//   rows.
// - The host binds either the owner-bound order or the impl-bound order. Both
//   are simple HIR-node orderings before sorting.

import gpu_index;

struct Params
{
    uint predicate_capacity;
    uint token_capacity;
    uint n_blocks;
    uint key_step;
    uint mode;
    uint reserved;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> predicate_count_in;
RWStructuredBuffer<uint> predicate_key_order;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_predicate_count()
{
    return min(predicate_count_in[0], gParams.predicate_capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (i < active_predicate_count())
        predicate_key_order[i] = i;
}
