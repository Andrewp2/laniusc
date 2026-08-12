// Follow bounded runs of enum variant and payload links.

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

void jump_variant(uint node)
{
    uint owner = hir_variant_owner_in[node];
    uint link = hir_variant_link_in[node];
    uint rank = hir_variant_rank_in[node];

    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        hir_variant_owner_out[node] = valid_node(owner) ? owner : INVALID;
        hir_variant_link_out[node] = INVALID;
        hir_variant_rank_out[node] = rank;
        return;
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
    hir_variant_owner_out[node] = valid_node(owner) ? owner : INVALID;
    hir_variant_rank_out[node] = rank;
    hir_variant_link_out[node] = link;
}

void jump_payload(uint node)
{
    uint owner = hir_variant_payload_owner_in[node];
    uint link = hir_variant_payload_link_in[node];
    uint rank = hir_variant_payload_rank_in[node];

    if (valid_node(owner) || !valid_node(link) || link == node)
    {
        hir_variant_payload_owner_out[node] =
            valid_node(owner) ? owner : INVALID;
        hir_variant_payload_link_out[node] = INVALID;
        hir_variant_payload_rank_out[node] = rank;
        return;
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
    hir_variant_payload_owner_out[node] = valid_node(owner) ? owner : INVALID;
    hir_variant_payload_rank_out[node] = rank;
    hir_variant_payload_link_out[node] = link;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= gHirEnum.n || row >= hir_enum_rank_count[0u])
        return;

    uint node = hir_enum_rank_node[row];
    if (node >= gHirEnum.n)
        return;

    if (!parser_feature_enabled(token_feature_flags, PARSER_FEATURE_ENUMS))
    {
        hir_variant_owner_out[node] = INVALID;
        hir_variant_link_out[node] = INVALID;
        hir_variant_rank_out[node] = 0u;
        hir_variant_payload_owner_out[node] = INVALID;
        hir_variant_payload_link_out[node] = INVALID;
        hir_variant_payload_rank_out[node] = 0u;
        return;
    }

    if (!valid_node(node))
    {
        hir_variant_owner_out[node] = INVALID;
        hir_variant_link_out[node] = INVALID;
        hir_variant_rank_out[node] = 0u;
        hir_variant_payload_owner_out[node] = INVALID;
        hir_variant_payload_link_out[node] = INVALID;
        hir_variant_payload_rank_out[node] = 0u;
        return;
    }

    jump_variant(node);
    jump_payload(node);
}
