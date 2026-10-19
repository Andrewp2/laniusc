// Follow bounded runs of enum variant and payload links.
// Rounds after the walk converges return at once (hir_walk_state).

import hir_walk_state;

import token_features;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirEnum;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_variant_owner_in;
StructuredBuffer<uint> hir_variant_link_in;
StructuredBuffer<uint> hir_variant_rank_in;
StructuredBuffer<uint> hir_variant_payload_owner_in;
StructuredBuffer<uint> hir_variant_payload_link_in;
StructuredBuffer<uint> hir_variant_payload_rank_in;
StructuredBuffer<uint> token_feature_flags;
StructuredBuffer<uint> hir_enum_rank_node;
StructuredBuffer<uint> hir_enum_rank_count;

RWStructuredBuffer<uint> hir_variant_owner_out;
RWStructuredBuffer<uint> hir_variant_link_out;
RWStructuredBuffer<uint> hir_variant_rank_out;
RWStructuredBuffer<uint> hir_variant_payload_owner_out;
RWStructuredBuffer<uint> hir_variant_payload_link_out;
RWStructuredBuffer<uint> hir_variant_payload_rank_out;
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
    return gHirEnum.uses_status_count != 0u ? min(gHirEnum.n, tree_count_status[5u])
                                   : gHirEnum.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

// Each jump writes one relation row and reports whether it differs from the
// row's input.
bool jump_variant(uint node)
{
    uint owner_in = hir_variant_owner_in[node];
    uint link_in = hir_variant_link_in[node];
    uint rank_in = hir_variant_rank_in[node];
    uint owner = owner_in;
    uint link = link_in;
    uint rank = rank_in;

    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        owner = valid_node(owner) ? owner : INVALID;
        hir_variant_owner_out[node] = owner;
        hir_variant_link_out[node] = INVALID;
        hir_variant_rank_out[node] = rank;
        return owner != owner_in || link_in != INVALID;
    }

    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        if (valid_node(owner) || !valid_node(link) || link == node) break;
        rank += hir_variant_rank_in[link];
        uint ancestor_owner = hir_variant_owner_in[link];
        uint ancestor_link = hir_variant_link_in[link];
        if (valid_node(ancestor_owner))
        {
            owner = ancestor_owner;
            link = INVALID;
            break;
        }
        link = valid_node(ancestor_link) ? ancestor_link : INVALID;
    }
    owner = valid_node(owner) ? owner : INVALID;
    hir_variant_owner_out[node] = owner;
    hir_variant_rank_out[node] = rank;
    hir_variant_link_out[node] = link;
    return owner != owner_in || link != link_in || rank != rank_in;
}

bool jump_payload(uint node)
{
    uint owner_in = hir_variant_payload_owner_in[node];
    uint link_in = hir_variant_payload_link_in[node];
    uint rank_in = hir_variant_payload_rank_in[node];
    uint owner = owner_in;
    uint link = link_in;
    uint rank = rank_in;

    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        owner = valid_node(owner) ? owner : INVALID;
        hir_variant_payload_owner_out[node] = owner;
        hir_variant_payload_link_out[node] = INVALID;
        hir_variant_payload_rank_out[node] = rank;
        return owner != owner_in || link_in != INVALID;
    }

    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        if (valid_node(owner) || !valid_node(link) || link == node) break;
        rank += hir_variant_payload_rank_in[link];
        uint ancestor_owner = hir_variant_payload_owner_in[link];
        uint ancestor_link = hir_variant_payload_link_in[link];
        if (valid_node(ancestor_owner))
        {
            owner = ancestor_owner;
            link = INVALID;
            break;
        }
        link = valid_node(ancestor_link) ? ancestor_link : INVALID;
    }
    owner = valid_node(owner) ? owner : INVALID;
    hir_variant_payload_owner_out[node] = owner;
    hir_variant_payload_rank_out[node] = rank;
    hir_variant_payload_link_out[node] = link;
    return owner != owner_in || link != link_in || rank != rank_in;
}

bool clear_row(uint node)
{
    bool changed = hir_variant_owner_in[node] != INVALID || hir_variant_link_in[node] != INVALID
        || hir_variant_rank_in[node] != 0u || hir_variant_payload_owner_in[node] != INVALID
        || hir_variant_payload_link_in[node] != INVALID || hir_variant_payload_rank_in[node] != 0u;
    hir_variant_owner_out[node] = INVALID;
    hir_variant_link_out[node] = INVALID;
    hir_variant_rank_out[node] = 0u;
    hir_variant_payload_owner_out[node] = INVALID;
    hir_variant_payload_link_out[node] = INVALID;
    hir_variant_payload_rank_out[node] = 0u;
    return changed;
}

// Advances one worklist row and reports whether its node's output differs
// from its input.
bool advance(uint row)
{
    if (row >= gHirEnum.n || row >= hir_enum_rank_count[0u])
        return false;

    uint node = hir_enum_rank_node[row];
    if (node >= gHirEnum.n)
        return false;

    if (!parser_feature_enabled(token_feature_flags, PARSER_FEATURE_ENUMS) || !valid_node(node))
        return clear_row(node);

    bool variant_changed = jump_variant(node);
    bool payload_changed = jump_payload(node);
    return variant_changed || payload_changed;
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
