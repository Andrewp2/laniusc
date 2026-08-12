// Follow a bounded run of nearest type-alias owner links per dispatch.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirTypeAliasOwner;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_type_alias_owner_link_in;
StructuredBuffer<uint> hir_type_alias_owner_value_in;

RWStructuredBuffer<uint> hir_type_alias_owner_link_out;
RWStructuredBuffer<uint> hir_type_alias_owner_value_out;

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
    return gHirTypeAliasOwner.uses_status_count != 0u ? min(gHirTypeAliasOwner.n, tree_count_status[5u])
                                             : gHirTypeAliasOwner.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_semantic_row(uint row, uint semantic_count)
{
    return row != INVALID && row < semantic_count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = active_semantic_count();
    if (row >= semantic_count)
        return;

    uint link = hir_type_alias_owner_link_in[row];
    uint value = hir_type_alias_owner_value_in[row];
    for (uint hop = 0u;
         hop < LINKS_PER_STEP && valid_semantic_row(link, semantic_count);
         ++hop)
    {
        if (value == INVALID)
        {
            uint parent_value = hir_type_alias_owner_value_in[link];
            if (parent_value != INVALID)
                value = parent_value;
        }
        uint parent_link = hir_type_alias_owner_link_in[link];
        link = valid_semantic_row(parent_link, semantic_count) ? parent_link : INVALID;
    }

    hir_type_alias_owner_link_out[row] = link;
    hir_type_alias_owner_value_out[row] = value;
}
