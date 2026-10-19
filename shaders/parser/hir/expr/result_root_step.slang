// Follow a bounded run of parser expression result edges into direct roots.
//
// The expression-field pass publishes the local edge relation. This pass
// materializes its transitive result root without exposing wrapper chains to
// consumers. Rounds after the walk converges return at once (hir_walk_state).

import hir_walk_state;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExprResultRoot;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_result_root_in;

RWStructuredBuffer<uint> hir_expr_result_root_out;
ConstantBuffer<HirWalkRound> gHirWalkRound;
RWStructuredBuffer<uint> hir_walk_state;

groupshared uint g_walk_changed;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_STEP = 16u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirExprResultRoot.uses_status_count != 0u
        ? min(gHirExprResultRoot.n, tree_count_status[5u])
        : gHirExprResultRoot.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

// Advances one node and reports whether its output differs from its input.
bool advance(uint node)
{
    if (node >= active_node_count())
        return false;

    uint start = hir_expr_result_root_in[node];
    uint root = start;
    if (!valid_node(root))
    {
        hir_expr_result_root_out[node] = INVALID;
        return start != INVALID;
    }

    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        uint next = hir_expr_result_root_in[root];
        if (!valid_node(next) || next == root)
            break;
        root = next;
    }
    hir_expr_result_root_out[node] = root;
    return root != start;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint group_thread: SV_GroupIndex)
{
    uint node = linear_thread_id(dtid);
    hir_walk_mark_ran(hir_walk_state, gHirWalkRound, node);
    if (hir_walk_round_redundant(hir_walk_state, gHirWalkRound))
        return;

    if (group_thread == 0u)
        g_walk_changed = 0u;
    GroupMemoryBarrierWithGroupSync();
    if (advance(node))
        g_walk_changed = 1u;
    GroupMemoryBarrierWithGroupSync();
    if (group_thread == 0u && g_walk_changed != 0u)
        hir_walk_mark_changed(hir_walk_state, gHirWalkRound);
}
