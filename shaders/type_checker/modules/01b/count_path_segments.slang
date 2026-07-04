// GPU path segment count pass.
//
// Scheduling contract:
// - Dispatch after type_check_modules_01_scatter_paths.slang.
// - Count parser-owned path segment nodes for each compact path record.
// - A GPU counted prefix scan over path_segment_count must produce
//   path_segment_base before the segment scatter pass runs.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_item_path_node;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> path_segment_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 9u;
static const uint PATH_TOO_DEEP_SENTINEL = MAX_PATH_SEGMENTS + 1u;

static const uint HIR_TYPE = 5u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_PATH_EXPR = 33u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
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
    return valid_node(sibling) ? sibling : INVALID;
}

bool is_path_container(uint prod)
{
    return prod == PROD_PATH ||
           prod == PROD_PATH_MORE ||
           prod == PROD_TYPE_PATH ||
           prod == PROD_TYPE_PATH_MORE ||
           prod == PROD_BOUND_TYPE_PATH ||
           prod == PROD_BOUND_TYPE_PATH_MORE;
}

bool is_path_segment(uint prod)
{
    return prod == PROD_PATH_IDENT ||
           prod == PROD_PATH_IDENT_ARGS ||
           prod == PROD_TYPE_PATH_IDENT ||
           prod == PROD_BOUND_TYPE_PATH_IDENT;
}

bool is_path_tail(uint prod)
{
    return prod == PROD_PATH_MORE ||
           prod == PROD_TYPE_PATH_MORE ||
           prod == PROD_BOUND_TYPE_PATH_MORE;
}

uint path_root_for_owner(uint owner_hir)
{
    if (!valid_node(owner_hir))
        return INVALID;

    uint owner_kind = hir_kind[owner_hir];
    uint root = INVALID;
    if (owner_kind == HIR_PATH_EXPR)
        root = owner_hir;
    else if (owner_kind == HIR_TYPE)
        root = hir_type_value_node[owner_hir];
    else if (owner_kind == HIR_MODULE_ITEM || owner_kind == HIR_IMPORT_ITEM)
        root = hir_item_path_node[owner_hir];

    return valid_node(root) && is_path_container(node_kind[root]) ? root : INVALID;
}

uint segment_token(uint segment)
{
    if (!valid_node(segment))
        return INVALID;
    uint token = hir_token_pos[segment];
    return token < gParams.n_tokens && name_id_by_token[token] != INVALID ? token : INVALID;
}

uint count_segments(uint root)
{
    if (!valid_node(root))
        return 0u;

    uint count = 0u;
    uint container = root;
    for (uint segment_i = 0u; segment_i < PATH_TOO_DEEP_SENTINEL; segment_i += 1u)
    {
        if (!valid_node(container) || !is_path_container(node_kind[container]))
            break;

        uint segment = first_child_node(container);
        if (!valid_node(segment) || !is_path_segment(node_kind[segment]) ||
            segment_token(segment) == INVALID)
            break;

        count += 1u;

        uint tail = next_sibling_node(segment);
        if (!valid_node(tail) || !is_path_tail(node_kind[tail]))
            break;
        container = tail;
    }
    return count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_slot = linear_thread_id(dtid);
    if (path_slot >= active_path_count())
        return;

    uint root = path_root_for_owner(path_owner_hir[path_slot]);
    path_segment_count[path_slot] = count_segments(root);
}
