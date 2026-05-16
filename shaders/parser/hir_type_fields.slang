// Derive parser-owned type expression metadata from production ids and tree edges.
//
// The pass records syntax facts needed by future array/slice/reference semantics
// without re-reading source text or scanning token neighborhoods.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_file_id;

RWStructuredBuffer<uint> hir_type_form;
RWStructuredBuffer<uint> hir_type_value_node;
RWStructuredBuffer<uint> hir_type_len_token;
RWStructuredBuffer<uint> hir_type_file_id;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;

static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint HIR_TYPE_FORM_REF = 4u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirType.uses_ll1 != 0u ? min(gHirType.n, ll1_status[5u]) : gHirType.n;
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint first_child_node(uint i)
{
    uint child = valid_node(i) ? first_child[i] : INVALID;
    return valid_node(child) ? child : INVALID;
}

uint next_sibling_node(uint i)
{
    uint sibling = valid_node(i) ? next_sibling[i] : INVALID;
    return valid_node(sibling) ? sibling : INVALID;
}

void clear_type(uint i)
{
    hir_type_form[i] = HIR_TYPE_FORM_NONE;
    hir_type_value_node[i] = INVALID;
    hir_type_len_token[i] = INVALID;
    hir_type_file_id[i] = valid_node(i) ? hir_token_file_id[i] : INVALID;
}

void publish_path_type(uint i)
{
    hir_type_form[i] = HIR_TYPE_FORM_PATH;
    hir_type_value_node[i] = first_child_node(i);
}

void publish_ref_type(uint i)
{
    hir_type_form[i] = HIR_TYPE_FORM_REF;
    hir_type_value_node[i] = first_child_node(i);
}

void publish_array_or_slice_type(uint i)
{
    uint elem = first_child_node(i);
    uint tail = next_sibling_node(elem);
    if (!valid_node(elem) || !valid_node(tail))
        return;

    uint tail_prod = node_kind[tail];
    if (tail_prod == PROD_TYPE_ARRAY_TAIL)
    {
        uint len_node = first_child_node(tail);
        hir_type_form[i] = HIR_TYPE_FORM_ARRAY;
        hir_type_value_node[i] = elem;
        hir_type_len_token[i] = valid_node(len_node) ? hir_token_pos[len_node] : INVALID;
    }
    else if (tail_prod == PROD_TYPE_SLICE_TAIL)
    {
        hir_type_form[i] = HIR_TYPE_FORM_SLICE;
        hir_type_value_node[i] = elem;
        hir_type_len_token[i] = INVALID;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gHirType.n)
        return;

    clear_type(i);

    if (!valid_node(i) || hir_kind[i] != HIR_TYPE)
        return;

    uint prod = node_kind[i];
    if (prod == PROD_TYPE_IDENT)
        publish_path_type(i);
    else if (prod == PROD_TYPE_ARRAY)
        publish_array_or_slice_type(i);
    else if (prod == PROD_TYPE_REF)
        publish_ref_type(i);
}
