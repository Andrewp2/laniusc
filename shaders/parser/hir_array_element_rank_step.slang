// Pointer-jump array literal element links.

import token_features;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirArray;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_array_element_owner_in;
StructuredBuffer<uint> hir_array_element_link_in;
StructuredBuffer<uint> hir_array_element_rank_in;
StructuredBuffer<uint> token_feature_flags;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;

RWStructuredBuffer<uint> hir_array_element_owner_out;
RWStructuredBuffer<uint> hir_array_element_link_out;
RWStructuredBuffer<uint> hir_array_element_rank_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirArray.uses_ll1 != 0u ? min(gHirArray.n, ll1_status[5u])
                                    : gHirArray.n;
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
    if (row >= gHirArray.n || row >= hir_list_rank_count[0u])
        return;

    uint node = hir_list_rank_node[row];
    if (node >= gHirArray.n)
        return;

    if (!parser_feature_enabled(token_feature_flags, PARSER_FEATURE_ARRAYS))
    {
        hir_array_element_owner_out[node] = INVALID;
        hir_array_element_link_out[node] = INVALID;
        hir_array_element_rank_out[node] = 0u;
        return;
    }

    if (!valid_node(node))
    {
        hir_array_element_owner_out[node] = INVALID;
        hir_array_element_link_out[node] = INVALID;
        hir_array_element_rank_out[node] = 0u;
        return;
    }

    uint owner = hir_array_element_owner_in[node];
    uint link = hir_array_element_link_in[node];
    uint rank = hir_array_element_rank_in[node];

    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        hir_array_element_owner_out[node] = valid_node(owner) ? owner : INVALID;
        hir_array_element_link_out[node] = INVALID;
        hir_array_element_rank_out[node] = rank;
        return;
    }

    uint ancestor_owner = hir_array_element_owner_in[link];
    uint ancestor_link = hir_array_element_link_in[link];
    uint ancestor_rank = hir_array_element_rank_in[link];
    uint resolved_owner = valid_node(ancestor_owner) ? ancestor_owner : INVALID;

    hir_array_element_owner_out[node] = resolved_owner;
    hir_array_element_rank_out[node] = rank + ancestor_rank;
    hir_array_element_link_out[node] =
        valid_node(resolved_owner) || !valid_node(ancestor_link)
        ? INVALID
        : ancestor_link;
}
