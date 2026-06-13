// Publish pointer-jumped struct field owners, ordinals, counts, and links.

import atomics;
import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirStruct;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_struct_field_owner_a;
StructuredBuffer<uint> hir_struct_field_rank_a;
StructuredBuffer<uint> hir_struct_lit_field_owner_a;
StructuredBuffer<uint> hir_struct_lit_field_rank_a;
StructuredBuffer<uint> hir_struct_lit_field_previous;

RWStructuredBuffer<uint> hir_struct_field_parent_struct;
RWStructuredBuffer<uint> hir_struct_field_ordinal;
RWStructuredBuffer<uint> hir_struct_decl_field_start;
RWStructuredBuffer<uint> hir_struct_decl_field_count;
RWStructuredBuffer<uint> hir_struct_lit_field_start;
RWStructuredBuffer<uint> hir_struct_lit_field_count;
RWStructuredBuffer<uint> hir_struct_lit_field_parent_lit;
RWStructuredBuffer<uint> hir_struct_lit_field_next;

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

void publish_struct_field(uint node)
{
    uint owner = hir_struct_field_owner_a[node];
    if (!valid_node(owner))
        return;

    uint ordinal = hir_struct_field_rank_a[node];
    hir_struct_field_parent_struct[node] = owner;
    hir_struct_field_ordinal[node] = ordinal;
    atomic_u32_min(hir_struct_decl_field_start, owner, node);
    atomic_u32_max(hir_struct_decl_field_count, owner, ordinal + 1u);
}

void publish_literal_field(uint node)
{
    uint owner = hir_struct_lit_field_owner_a[node];
    if (!valid_node(owner))
        return;

    uint ordinal = hir_struct_lit_field_rank_a[node];
    uint previous = hir_struct_lit_field_previous[node];
    hir_struct_lit_field_parent_lit[node] = owner;
    atomic_u32_min(hir_struct_lit_field_start, owner, node);
    atomic_u32_max(hir_struct_lit_field_count, owner, ordinal + 1u);
    if (valid_node(previous))
        hir_struct_lit_field_next[previous] = node;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirStruct.n || !valid_node(node))
        return;

    uint prod = node_kind[node];
    if (prod == PROD_STRUCT_FIELD)
        publish_struct_field(node);
    else if (prod == PROD_STRUCT_LIT_FIELD)
        publish_literal_field(node);
}
