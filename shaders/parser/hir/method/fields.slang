// Publish parser-owned method declaration rows.
//
// This pass consumes the parser/HIR relations that already establish dense HIR
// rows, nearest semantic parents, and parameter owner/rank records. Typecheck
// consumers should read these rows instead of walking parse-tree ancestors or
// child lists to rediscover method ownership.

import atomics;
import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirMethod;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_node_dense_id;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint4> hir_param_record;

RWStructuredBuffer<uint> hir_method_owner_node;
RWStructuredBuffer<uint> hir_method_impl_node;
RWStructuredBuffer<uint> hir_method_name_token;
RWStructuredBuffer<uint> hir_method_first_param_token;
RWStructuredBuffer<uint> hir_method_receiver_mode;
RWStructuredBuffer<uint> hir_method_visibility;
RWStructuredBuffer<uint> hir_method_impl_receiver_type_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;

static const uint METHOD_RECEIVER_NONE = 0u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint METHOD_RECEIVER_EXPLICIT = 3u;

static const uint METHOD_VIS_PRIVATE = 0u;
static const uint METHOD_VIS_PUBLIC = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirMethod.uses_status_count != 0u ? min(gHirMethod.n, tree_count_status[5u]) : gHirMethod.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool valid_semantic_row(uint row)
{
    return row != INVALID && row < active_semantic_count();
}

uint semantic_row_node(uint row)
{
    if (!valid_semantic_row(row))
        return INVALID;
    uint node = hir_semantic_dense_node[row];
    return valid_node(node) ? node : INVALID;
}

uint parent_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint p = parent[node];
    return valid_node(p) ? p : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    return valid_node(sibling) && parent_node(sibling) == parent_node(node)
        ? sibling
        : INVALID;
}

uint semantic_row_for_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint row = hir_node_dense_id[node];
    return valid_semantic_row(row) && hir_semantic_dense_node[row] == node ? row : INVALID;
}

bool is_impl_method_wrapper(uint prod)
{
    return prod == PROD_IMPL_METHOD || prod == PROD_IMPL_METHOD_PUB;
}

bool is_impl_item_wrapper(uint prod)
{
    return prod == PROD_ITEM_IMPL || prod == PROD_PUB_IMPL;
}

bool is_impl_owner_node(uint prod)
{
    return prod == PROD_IMPL_INHERENT || prod == PROD_IMPL_TRAIT;
}

uint impl_owner_child(uint node)
{
    uint child = first_child_node(node);
    [loop]
    for (uint guard = 0u; guard < 8u && valid_node(child); guard += 1u)
    {
        if (is_impl_owner_node(node_kind[child]))
            return child;
        child = next_sibling_node(child);
    }
    return INVALID;
}

uint impl_owner_from_item_list(uint node)
{
    uint child = first_child_node(node);
    [loop]
    for (uint guard = 0u; guard < 16u && valid_node(child); guard += 1u)
    {
        if (is_impl_item_wrapper(node_kind[child]))
        {
            uint owner = impl_owner_child(child);
            if (valid_node(owner))
                return owner;
        }
        child = next_sibling_node(child);
    }
    return INVALID;
}

bool is_trait_method_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint prod = node_kind[node];
    return prod == PROD_TRAIT_METHOD || prod == PROD_TRAIT_METHOD_PUB;
}

uint trait_owner_node_for_method(uint method_node)
{
    if (!is_trait_method_node(method_node))
        return INVALID;

    uint method_row = semantic_row_for_node(method_node);
    if (!valid_semantic_row(method_row))
        return INVALID;

    uint trait_row = hir_semantic_parent[method_row];
    uint trait_node = semantic_row_node(trait_row);
    return valid_node(trait_node) && node_kind[trait_node] == PROD_TRAIT ? trait_node : INVALID;
}

uint method_impl_node_for_fn(uint fn_node)
{
    if (!valid_node(fn_node) || hir_kind[fn_node] != HIR_FN || node_kind[fn_node] != PROD_IMPL_FN)
        return INVALID;

    bool saw_method_wrapper = false;
    uint ancestor = parent_node(fn_node);
    [loop]
    for (uint guard = 0u; guard < 32u && valid_node(ancestor); guard += 1u)
    {
        uint prod = node_kind[ancestor];
        if (is_impl_method_wrapper(prod))
            saw_method_wrapper = true;
        if (saw_method_wrapper && is_impl_owner_node(prod))
            return ancestor;
        if (saw_method_wrapper && prod == PROD_IMPL_METHODS_SOME)
        {
            uint owner = impl_owner_from_item_list(parent_node(ancestor));
            if (valid_node(owner))
                return owner;
        }
        ancestor = parent_node(ancestor);
    }

    uint fn_row = semantic_row_for_node(fn_node);
    if (!valid_semantic_row(fn_row))
        return INVALID;

    uint row = hir_semantic_parent[fn_row];
    [loop]
    for (uint depth = 0u; depth < 8u && valid_semantic_row(row); depth += 1u)
    {
        uint node = semantic_row_node(row);
        if (valid_node(node) && is_impl_owner_node(node_kind[node]))
            return node;

        if (valid_node(node) && is_impl_item_wrapper(node_kind[node]))
        {
            uint owner = impl_owner_child(node);
            if (valid_node(owner))
                return owner;
        }

        row = hir_semantic_parent[row];
    }
    return INVALID;
}

bool has_later_direct_impl_type_sibling(uint type_node)
{
    uint sibling = next_sibling_node(type_node);
    return valid_node(sibling) && hir_kind[sibling] == HIR_TYPE &&
           is_impl_owner_node(node_kind[parent_node(type_node)]);
}

uint method_visibility_for_fn(uint fn_node)
{
    uint method_wrapper = parent_node(fn_node);
    return valid_node(method_wrapper) && node_kind[method_wrapper] == PROD_IMPL_METHOD_PUB
        ? METHOD_VIS_PUBLIC
        : METHOD_VIS_PRIVATE;
}

uint method_owner_node_for_decl(uint method_node)
{
    if (valid_node(method_node) && node_kind[method_node] == PROD_IMPL_FN)
        return method_impl_node_for_fn(method_node);
    if (is_trait_method_node(method_node))
        return trait_owner_node_for_method(method_node);
    return INVALID;
}

uint receiver_mode_for_param(uint param_node)
{
    uint prod = valid_node(param_node) ? node_kind[param_node] : INVALID;
    if (prod == PROD_PARAM_SELF)
        return METHOD_RECEIVER_SELF;
    if (prod == PROD_PARAM_SELF_REF)
        return METHOD_RECEIVER_REF_SELF;
    if (prod == PROD_PARAM_NAMED)
        return METHOD_RECEIVER_EXPLICIT;
    return METHOD_RECEIVER_NONE;
}

uint impl_method_name_token(uint fn_node)
{
    uint start = valid_node(fn_node) ? hir_token_pos[fn_node] : INVALID;
    return start == INVALID ? INVALID : start + 1u;
}

void publish_method_function(uint fn_node)
{
    uint impl_node = method_impl_node_for_fn(fn_node);
    if (!valid_node(impl_node))
        return;

    uint name_token = impl_method_name_token(fn_node);
    if (name_token == INVALID)
        return;

    hir_method_owner_node[fn_node] = impl_node;
    hir_method_impl_node[fn_node] = impl_node;
    hir_method_name_token[fn_node] = name_token;
    hir_method_visibility[fn_node] = method_visibility_for_fn(fn_node);

    uint method_end = hir_token_end[fn_node];
    if (method_end != INVALID)
        atomic_u32_max(hir_token_end, impl_node, method_end);
}

void publish_trait_method(uint method_node)
{
    uint owner = trait_owner_node_for_method(method_node);
    if (!valid_node(owner))
        return;

    uint start = hir_token_pos[method_node];
    if (start == INVALID)
        return;

    uint name_token = node_kind[method_node] == PROD_TRAIT_METHOD_PUB ? start + 2u : start + 1u;
    hir_method_owner_node[method_node] = owner;
    hir_method_name_token[method_node] = name_token;
    hir_method_visibility[method_node] =
        node_kind[method_node] == PROD_TRAIT_METHOD_PUB ? METHOD_VIS_PUBLIC : METHOD_VIS_PRIVATE;
}

void publish_method_first_param(uint param_node)
{
    uint4 record = hir_param_record[param_node];
    uint owner_fn = record.x;
    uint rank = record.y;
    uint name_token = record.z;
    if (rank != 0u || !valid_node(owner_fn) || name_token == INVALID)
        return;

    if (!valid_node(method_owner_node_for_decl(owner_fn)))
        return;

    hir_method_first_param_token[owner_fn] = name_token;
    hir_method_receiver_mode[owner_fn] = receiver_mode_for_param(param_node);
}

void publish_impl_receiver_type(uint type_node)
{
    uint impl_node = parent_node(type_node);
    if (!valid_node(impl_node))
        return;

    uint prod = node_kind[impl_node];
    if (prod == PROD_IMPL_INHERENT)
        hir_method_impl_receiver_type_node[impl_node] = type_node;
    else if (prod == PROD_IMPL_TRAIT && !has_later_direct_impl_type_sibling(type_node))
        hir_method_impl_receiver_type_node[impl_node] = type_node;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node == INVALID)
        return;

    uint kind = hir_kind[node];
    if (kind == HIR_FN)
        publish_method_function(node);
    else if (kind == HIR_PARAM)
        publish_method_first_param(node);
    else if (kind == HIR_TYPE)
        publish_impl_receiver_type(node);
    if (is_trait_method_node(node))
        publish_trait_method(node);
}
