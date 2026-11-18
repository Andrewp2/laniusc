// Publish each function's compact parameter segment base.
//
// The parameter worklist is produced by a prefix scan over parameter flags and
// is ordered by HIR row. Owner resolution has already run logarithmically over
// the previous-parameter links. This pass records the first compact row for
// each resolved owner so the following pass can assign source-order segment
// offsets without carrying ranks through the link jump.

import atomics;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirParam;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_param_owner_a;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;

RWStructuredBuffer<uint> hir_param_rank_b;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirParam.uses_status_count != 0u ? min(gHirParam.n, tree_count_status[5u]) : gHirParam.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= gHirParam.n || row >= hir_list_rank_count[0u])
        return;

    uint node = hir_list_rank_node[row];
    if (!valid_node(node))
        return;

    uint owner = hir_param_owner_a[node];
    if (valid_node(owner))
        atomic_u32_min(hir_param_rank_b, owner, row);
}
