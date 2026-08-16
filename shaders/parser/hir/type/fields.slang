// Derive parser-owned type expression metadata from production ids and tree edges.
//
// The pass records syntax facts needed by future array/slice/reference semantics
// and seeds the independent path-leaf relation while the same tree row is hot.
// Follow-up path/type-argument passes publish list-derived metadata with pointer
// jumping.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> hir_type_form;
RWStructuredBuffer<uint> hir_type_value_node;
RWStructuredBuffer<uint> hir_type_len_token;
RWStructuredBuffer<uint> hir_type_path_leaf_node;
RWStructuredBuffer<uint> hir_bound_path_owner_by_leaf;
RWStructuredBuffer<uint> hir_type_arg_start;
RWStructuredBuffer<uint> hir_type_arg_count;
RWStructuredBuffer<uint> hir_type_arg_next;
RWStructuredBuffer<uint> hir_type_path_leaf_link_a;
RWStructuredBuffer<uint> hir_type_path_leaf_value_a;

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
    return gHirType.uses_status_count != 0u ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

bool valid_type_node(uint i)
{
    return valid_node(i) && hir_kind[i] == HIR_TYPE;
}

uint first_child_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint child = first_child[i];
    return valid_node(child) ? child : INVALID;
}

uint next_sibling_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint sibling = next_sibling[i];
    return valid_node(sibling) ? sibling : INVALID;
}

void clear_type(uint i)
{
    hir_type_form[i] = HIR_TYPE_FORM_NONE;
    hir_type_value_node[i] = INVALID;
    hir_type_len_token[i] = INVALID;
    hir_type_path_leaf_node[i] = INVALID;
    // Production stores this sparse reverse relation by the leaf's distinct
    // token anchor and uses zero as its job-clear sentinel. Debug parsing
    // retains the historical raw-node row and INVALID sentinel.
    if (gHirType.retain_debug_rows != 0u)
        hir_bound_path_owner_by_leaf[i] = INVALID;
    if (gHirType.retain_debug_rows != 0u)
    {
        hir_type_arg_start[i] = INVALID;
        hir_type_arg_count[i] = 0u;
        hir_type_arg_next[i] = INVALID;
    }
}

void publish_path_type(uint i)
{
    // The path root can be separated from this semantic type row by grammar
    // forwarding nodes. The path-leaf scatter joins it to its nearest semantic
    // owner after the path pointer jump has completed.
    hir_type_form[i] = HIR_TYPE_FORM_PATH;
}

void publish_ref_type(uint i)
{
    uint target = first_child_node(i);
    if (!valid_type_node(target))
        return;

    hir_type_form[i] = HIR_TYPE_FORM_REF;
    hir_type_value_node[i] = target;
}

void publish_array_or_slice_type(uint i)
{
    uint elem = first_child_node(i);
    uint tail = next_sibling_node(elem);
    if (!valid_type_node(elem) || !valid_node(tail))
        return;

    uint tail_prod = node_kind[tail];
    if (tail_prod == PROD_TYPE_ARRAY_TAIL)
    {
        uint len_node = first_child_node(tail);
        if (!valid_node(len_node) ||
            (node_kind[len_node] != PROD_TYPE_ARRAY_LEN_INT &&
             node_kind[len_node] != PROD_TYPE_ARRAY_LEN_NAME))
            return;

        hir_type_form[i] = HIR_TYPE_FORM_ARRAY;
        hir_type_value_node[i] = elem;
        hir_type_len_token[i] = hir_token_pos[len_node];
    }
    else if (tail_prod == PROD_TYPE_SLICE_TAIL)
    {
        hir_type_form[i] = HIR_TYPE_FORM_SLICE;
        hir_type_value_node[i] = elem;
        hir_type_len_token[i] = INVALID;
    }
}

bool is_path_container(uint prod)
{
    return prod == PROD_PATH || prod == PROD_PATH_MORE ||
           prod == PROD_TYPE_PATH || prod == PROD_TYPE_PATH_MORE ||
           prod == PROD_BOUND_TYPE_PATH || prod == PROD_BOUND_TYPE_PATH_MORE;
}

bool is_type_path_segment(uint prod)
{
    return prod == PROD_TYPE_PATH_IDENT ||
           prod == PROD_PATH_IDENT ||
           prod == PROD_PATH_IDENT_ARGS ||
           prod == PROD_BOUND_TYPE_PATH_IDENT;
}

bool is_type_path_tail(uint prod)
{
    return prod == PROD_TYPE_PATH_MORE ||
           prod == PROD_PATH_MORE ||
           prod == PROD_BOUND_TYPE_PATH_MORE;
}

void seed_type_path_leaf(uint node)
{
    hir_type_path_leaf_link_a[node] = INVALID;
    hir_type_path_leaf_value_a[node] = INVALID;

    if (!is_path_container(node_kind[node]))
        return;

    uint segment = first_child_node(node);
    if (!valid_node(segment) || !is_type_path_segment(node_kind[segment]))
        return;

    hir_type_path_leaf_value_a[node] = segment;
    uint tail = next_sibling_node(segment);
    if (valid_node(tail) && is_type_path_tail(node_kind[tail]))
        hir_type_path_leaf_link_a[node] = tail;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gHirType.n)
        return;

    seed_type_path_leaf(i);
    clear_type(i);

    if (!valid_node(i) || hir_kind[i] != HIR_TYPE)
        return;

    uint prod = node_kind[i];
    if (prod == PROD_TYPE_IDENT || prod == PROD_BOUND_TYPE_IDENT)
        publish_path_type(i);
    else if (prod == PROD_TYPE_ARRAY)
        publish_array_or_slice_type(i);
    else if (prod == PROD_TYPE_REF || prod == PROD_BOUND_TYPE_REF)
        publish_ref_type(i);
}
