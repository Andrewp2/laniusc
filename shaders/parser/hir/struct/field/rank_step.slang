// Follow bounded runs of struct declaration and literal field links.
// Rounds after the walk converges return at once (hir_walk_state).

import hir_walk_state;

import token_features;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirStruct;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_struct_field_owner_in;
StructuredBuffer<uint> hir_struct_field_link_in;
StructuredBuffer<uint> hir_struct_field_rank_in;
StructuredBuffer<uint> hir_struct_lit_field_owner_in;
StructuredBuffer<uint> hir_struct_lit_field_link_in;
StructuredBuffer<uint> hir_struct_lit_field_rank_in;
StructuredBuffer<uint> token_feature_flags;
StructuredBuffer<uint> hir_struct_rank_node;
StructuredBuffer<uint> hir_struct_rank_count;

RWStructuredBuffer<uint> hir_struct_field_owner_out;
RWStructuredBuffer<uint> hir_struct_field_link_out;
RWStructuredBuffer<uint> hir_struct_field_rank_out;
RWStructuredBuffer<uint> hir_struct_lit_field_owner_out;
RWStructuredBuffer<uint> hir_struct_lit_field_link_out;
RWStructuredBuffer<uint> hir_struct_lit_field_rank_out;
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
    return gHirStruct.uses_status_count != 0u ? min(gHirStruct.n, tree_count_status[5u])
                                     : gHirStruct.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

// Writes one relation row and reports whether it differs from the row's input.
bool jump_one(
    uint node,
    StructuredBuffer<uint> owner_in,
    StructuredBuffer<uint> link_in,
    StructuredBuffer<uint> rank_in,
    RWStructuredBuffer<uint> owner_out,
    RWStructuredBuffer<uint> link_out,
    RWStructuredBuffer<uint> rank_out)
{
    uint start_owner = owner_in[node];
    uint start_link = link_in[node];
    uint start_rank = rank_in[node];
    uint owner = start_owner;
    uint link = start_link;
    uint rank = start_rank;

    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        owner = valid_node(owner) ? owner : INVALID;
        owner_out[node] = owner;
        link_out[node] = INVALID;
        rank_out[node] = rank;
        return owner != start_owner || start_link != INVALID;
    }

    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        if (valid_node(owner) || !valid_node(link) || link == node) break;
        rank += rank_in[link];
        uint ancestor_owner = owner_in[link];
        uint ancestor_link = link_in[link];
        if (valid_node(ancestor_owner))
        {
            owner = ancestor_owner;
            link = INVALID;
            break;
        }
        link = valid_node(ancestor_link) ? ancestor_link : INVALID;
    }
    owner = valid_node(owner) ? owner : INVALID;
    owner_out[node] = owner;
    rank_out[node] = rank;
    link_out[node] = link;
    return owner != start_owner || link != start_link || rank != start_rank;
}

bool clear_row(uint node)
{
    bool changed = hir_struct_field_owner_in[node] != INVALID
        || hir_struct_field_link_in[node] != INVALID || hir_struct_field_rank_in[node] != 0u
        || hir_struct_lit_field_owner_in[node] != INVALID
        || hir_struct_lit_field_link_in[node] != INVALID
        || hir_struct_lit_field_rank_in[node] != 0u;
    hir_struct_field_owner_out[node] = INVALID;
    hir_struct_field_link_out[node] = INVALID;
    hir_struct_field_rank_out[node] = 0u;
    hir_struct_lit_field_owner_out[node] = INVALID;
    hir_struct_lit_field_link_out[node] = INVALID;
    hir_struct_lit_field_rank_out[node] = 0u;
    return changed;
}

// Advances one worklist row and reports whether its node's output differs
// from its input.
bool advance(uint row)
{
    if (row >= gHirStruct.n || row >= hir_struct_rank_count[0u])
        return false;

    uint node = hir_struct_rank_node[row];
    if (node >= gHirStruct.n)
        return false;

    if (!parser_feature_enabled(token_feature_flags, PARSER_FEATURE_STRUCTS) || !valid_node(node))
        return clear_row(node);

    bool field_changed = jump_one(
        node,
        hir_struct_field_owner_in,
        hir_struct_field_link_in,
        hir_struct_field_rank_in,
        hir_struct_field_owner_out,
        hir_struct_field_link_out,
        hir_struct_field_rank_out);
    bool literal_changed = jump_one(
        node,
        hir_struct_lit_field_owner_in,
        hir_struct_lit_field_link_in,
        hir_struct_lit_field_rank_in,
        hir_struct_lit_field_owner_out,
        hir_struct_lit_field_link_out,
        hir_struct_lit_field_rank_out);
    return field_changed || literal_changed;
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
