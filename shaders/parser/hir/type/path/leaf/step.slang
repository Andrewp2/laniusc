// Follow a bounded run of type-path links per dispatch. Each round compresses
// the remaining chain by up to 16x, preserving arbitrary path lengths without
// paying one device-wide barrier for every binary-doubling step. Rounds after
// the walk converges return at once (hir_walk_state).

import hir_walk_state;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_type_path_leaf_link_in;
StructuredBuffer<uint> hir_type_path_leaf_value_in;

RWStructuredBuffer<uint> hir_type_path_leaf_link_out;
RWStructuredBuffer<uint> hir_type_path_leaf_value_out;
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
    return gHirType.uses_status_count != 0u ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool write_row(uint node, uint link, uint value)
{
    hir_type_path_leaf_link_out[node] = link;
    hir_type_path_leaf_value_out[node] = value;
    return link != hir_type_path_leaf_link_in[node] || value != hir_type_path_leaf_value_in[node];
}

// Advances one node and reports whether its output differs from its input.
bool advance(uint node)
{
    if (node >= gHirType.n)
        return false;

    if (!valid_node(node))
        return write_row(node, INVALID, INVALID);

    uint link = hir_type_path_leaf_link_in[node];
    uint value = hir_type_path_leaf_value_in[node];
    if (!valid_node(link) || link == node)
        return write_row(node, INVALID, value);

    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        if (!valid_node(link) || link == node)
        {
            link = INVALID;
            break;
        }

        uint linked_value = hir_type_path_leaf_value_in[link];
        if (valid_node(linked_value))
            value = linked_value;
        uint linked_link = hir_type_path_leaf_link_in[link];
        link = valid_node(linked_link) ? linked_link : INVALID;
    }
    return write_row(node, link, value);
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
