// Pointer-jump a compact linked list to its owner while summing edge ranks.
// Rounds after the walk converges return at once (hir_walk_state).

import hir_walk_state;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirListRank;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;
StructuredBuffer<uint> list_owner_in;
StructuredBuffer<uint> list_link_in;
StructuredBuffer<uint> list_rank_in;
RWStructuredBuffer<uint> list_owner_out;
RWStructuredBuffer<uint> list_link_out;
RWStructuredBuffer<uint> list_rank_out;
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
    return gHirListRank.uses_status_count != 0u
        ? min(gHirListRank.n, tree_count_status[5u])
        : gHirListRank.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

// Advances one worklist row and reports whether its node's output differs
// from its input.
bool advance(uint row)
{
    if (row >= gHirListRank.n || row >= hir_list_rank_count[0u])
        return false;

    uint node = hir_list_rank_node[row];
    if (!valid_node(node))
        return false;

    uint owner = list_owner_in[node];
    uint link = list_link_in[node];
    uint rank = list_rank_in[node];
    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        if (valid_node(owner) || !valid_node(link) || link == node)
            break;

        rank += list_rank_in[link];
        uint ancestor_owner = list_owner_in[link];
        uint ancestor_link = list_link_in[link];
        if (valid_node(ancestor_owner))
        {
            owner = ancestor_owner;
            link = INVALID;
            break;
        }
        link = valid_node(ancestor_link) ? ancestor_link : INVALID;
    }

    uint owner_out = valid_node(owner) ? owner : INVALID;
    list_owner_out[node] = owner_out;
    list_link_out[node] = link;
    list_rank_out[node] = rank;
    return owner_out != list_owner_in[node] || link != list_link_in[node] || rank != list_rank_in[node];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint group_thread: SV_GroupIndex)
{
    uint row = linear_thread_id(dtid);
    hir_walk_mark_ran(hir_walk_state, gHirWalkRound, row);
    if (hir_walk_round_redundant(hir_walk_state, gHirWalkRound))
        return;

    if (group_thread == 0u)
        g_walk_changed = 0u;
    GroupMemoryBarrierWithGroupSync();
    if (advance(row))
        g_walk_changed = 1u;
    GroupMemoryBarrierWithGroupSync();
    if (group_thread == 0u && g_walk_changed != 0u)
        hir_walk_mark_changed(hir_walk_state, gHirWalkRound);
}
