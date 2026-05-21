// Pointer-jump nearest type-alias owner values over dense semantic-HIR rows.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirTypeAliasOwner;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_type_alias_owner_link_in;
StructuredBuffer<uint> hir_type_alias_owner_value_in;

RWStructuredBuffer<uint> hir_type_alias_owner_link_out;
RWStructuredBuffer<uint> hir_type_alias_owner_value_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirTypeAliasOwner.uses_ll1 != 0u ? min(gHirTypeAliasOwner.n, ll1_status[5u])
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
    if (valid_semantic_row(link, semantic_count))
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
