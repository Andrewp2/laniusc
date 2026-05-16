// Derive parser-owned struct declaration and struct literal metadata.
//
// This pass consumes production ids plus inverted tree arrays. It stays under
// the WebGPU 16 storage-buffer limit and does not inspect source bytes or token
// neighborhoods.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirStruct;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> hir_struct_field_parent_struct;
RWStructuredBuffer<uint> hir_struct_field_ordinal;
RWStructuredBuffer<uint> hir_struct_field_type_node;
RWStructuredBuffer<uint> hir_struct_decl_field_start;
RWStructuredBuffer<uint> hir_struct_decl_field_count;
RWStructuredBuffer<uint> hir_struct_lit_head_node;
RWStructuredBuffer<uint> hir_struct_lit_field_start;
RWStructuredBuffer<uint> hir_struct_lit_field_count;
RWStructuredBuffer<uint> hir_struct_lit_field_parent_lit;
RWStructuredBuffer<uint> hir_struct_lit_field_value_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirStruct.uses_ll1 != 0u ? min(gHirStruct.n, ll1_status[5u]) : gHirStruct.n;
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint first_child_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint child = i + 1u;
    return valid_node(child) && parent[child] == i ? child : INVALID;
}

uint previous_sibling_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint p = parent[i];
    if (!valid_node(p))
        return INVALID;

    uint child = first_child_node(p);
    uint prev = INVALID;
    [loop]
    for (uint guard = 0u; guard < 256u && valid_node(child) && parent[child] == p &&
                          child < i;
         guard += 1u)
    {
        prev = child;
        child = subtree_end[child];
    }
    return prev;
}

uint ancestor_with_production(uint i, uint prod)
{
    uint cur = i;
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        uint p = parent[cur];
        if (!valid_node(p))
            return INVALID;
        if (node_kind[p] == prod)
            return p;
        cur = p;
    }
    return INVALID;
}

uint first_hir_type_child(uint i)
{
    uint end = valid_node(i) ? min(subtree_end[i], active_node_count()) : INVALID;
    [loop]
    for (uint j = i + 1u; j < end; j += 1u)
    {
        if (hir_kind[j] == HIR_TYPE && parent[j] == i)
            return j;
    }
    return INVALID;
}

void clear_fields(uint i)
{
    hir_struct_field_parent_struct[i] = INVALID;
    hir_struct_field_ordinal[i] = INVALID;
    hir_struct_field_type_node[i] = INVALID;
    hir_struct_decl_field_start[i] = INVALID;
    hir_struct_decl_field_count[i] = 0u;
    hir_struct_lit_head_node[i] = INVALID;
    hir_struct_lit_field_start[i] = INVALID;
    hir_struct_lit_field_count[i] = 0u;
    hir_struct_lit_field_parent_lit[i] = INVALID;
    hir_struct_lit_field_value_node[i] = INVALID;
}

void publish_struct_decl(uint i)
{
    uint first_field = INVALID;
    uint field_count = 0u;
    uint end = min(subtree_end[i], active_node_count());
    [loop]
    for (uint j = i + 1u; j < end; j += 1u)
    {
        if (node_kind[j] == PROD_STRUCT_FIELD && ancestor_with_production(j, PROD_STRUCT) == i)
        {
            if (first_field == INVALID)
                first_field = j;
            field_count += 1u;
        }
    }

    hir_struct_decl_field_start[i] = first_field;
    hir_struct_decl_field_count[i] = field_count;
}

void publish_struct_field(uint i)
{
    uint struct_i = ancestor_with_production(i, PROD_STRUCT);
    if (!valid_node(struct_i))
        return;

    uint ordinal = 0u;
    [loop]
    for (uint j = 0u; j < i; j += 1u)
    {
        if (valid_node(j) && node_kind[j] == PROD_STRUCT_FIELD &&
            ancestor_with_production(j, PROD_STRUCT) == struct_i)
            ordinal += 1u;
    }

    hir_struct_field_parent_struct[i] = struct_i;
    hir_struct_field_ordinal[i] = ordinal;
    hir_struct_field_type_node[i] = first_hir_type_child(i);
}

void publish_struct_literal(uint i)
{
    uint prev = previous_sibling_node(i);
    if (valid_node(prev) && node_kind[prev] == PROD_PATH)
        hir_struct_lit_head_node[i] = prev;

    uint first_field = INVALID;
    uint field_count = 0u;
    uint end = min(subtree_end[i], active_node_count());
    [loop]
    for (uint j = i + 1u; j < end; j += 1u)
    {
        if (node_kind[j] == PROD_STRUCT_LIT_FIELD &&
            ancestor_with_production(j, PROD_STRUCT_LIT) == i)
        {
            if (first_field == INVALID)
                first_field = j;
            field_count += 1u;
        }
    }

    hir_struct_lit_field_start[i] = first_field;
    hir_struct_lit_field_count[i] = field_count;
}

void publish_struct_literal_field(uint i)
{
    uint literal_i = ancestor_with_production(i, PROD_STRUCT_LIT);
    if (!valid_node(literal_i))
        return;

    hir_struct_lit_field_parent_lit[i] = literal_i;
    hir_struct_lit_field_value_node[i] = first_child_node(i);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gHirStruct.n)
        return;

    clear_fields(i);

    if (!valid_node(i))
        return;

    uint prod = node_kind[i];
    if (prod == PROD_STRUCT)
        publish_struct_decl(i);
    else if (prod == PROD_STRUCT_FIELD)
        publish_struct_field(i);
    else if (prod == PROD_STRUCT_LIT)
        publish_struct_literal(i);
    else if (prod == PROD_STRUCT_LIT_FIELD)
        publish_struct_literal_field(i);
}
