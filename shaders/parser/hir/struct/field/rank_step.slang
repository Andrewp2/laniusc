// Pointer-jump struct declaration and literal field links.

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

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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

void jump_one(
    uint node,
    StructuredBuffer<uint> owner_in,
    StructuredBuffer<uint> link_in,
    StructuredBuffer<uint> rank_in,
    RWStructuredBuffer<uint> owner_out,
    RWStructuredBuffer<uint> link_out,
    RWStructuredBuffer<uint> rank_out)
{
    uint owner = owner_in[node];
    uint link = link_in[node];
    uint rank = rank_in[node];

    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        owner_out[node] = valid_node(owner) ? owner : INVALID;
        link_out[node] = INVALID;
        rank_out[node] = rank;
        return;
    }

    uint ancestor_owner = owner_in[link];
    uint ancestor_link = link_in[link];
    uint ancestor_rank = rank_in[link];
    uint resolved_owner = valid_node(ancestor_owner) ? ancestor_owner : INVALID;

    owner_out[node] = resolved_owner;
    rank_out[node] = rank + ancestor_rank;
    link_out[node] =
        valid_node(resolved_owner) || !valid_node(ancestor_link) ? INVALID : ancestor_link;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= gHirStruct.n || row >= hir_struct_rank_count[0u])
        return;

    uint node = hir_struct_rank_node[row];
    if (node >= gHirStruct.n)
        return;

    if (!parser_feature_enabled(token_feature_flags, PARSER_FEATURE_STRUCTS))
    {
        hir_struct_field_owner_out[node] = INVALID;
        hir_struct_field_link_out[node] = INVALID;
        hir_struct_field_rank_out[node] = 0u;
        hir_struct_lit_field_owner_out[node] = INVALID;
        hir_struct_lit_field_link_out[node] = INVALID;
        hir_struct_lit_field_rank_out[node] = 0u;
        return;
    }

    if (!valid_node(node))
    {
        hir_struct_field_owner_out[node] = INVALID;
        hir_struct_field_link_out[node] = INVALID;
        hir_struct_field_rank_out[node] = 0u;
        hir_struct_lit_field_owner_out[node] = INVALID;
        hir_struct_lit_field_link_out[node] = INVALID;
        hir_struct_lit_field_rank_out[node] = 0u;
        return;
    }

    jump_one(
        node,
        hir_struct_field_owner_in,
        hir_struct_field_link_in,
        hir_struct_field_rank_in,
        hir_struct_field_owner_out,
        hir_struct_field_link_out,
        hir_struct_field_rank_out);
    jump_one(
        node,
        hir_struct_lit_field_owner_in,
        hir_struct_lit_field_link_in,
        hir_struct_lit_field_rank_in,
        hir_struct_lit_field_owner_out,
        hir_struct_lit_field_link_out,
        hir_struct_lit_field_rank_out);
}
