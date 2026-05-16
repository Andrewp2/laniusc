// HIR-driven named generic argument refs.
//
// This pass runs after type-expression refs have been collected and after any
// declaration binding pass has had a chance to attach the named instance to a
// resolved declaration. It overwrites generic argument refs from parser-owned
// top-level HIR type-argument nodes instead of re-scanning token neighborhoods.

import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;

RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PARENT_WALK = 128u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

static const uint HIR_TYPE = 5u;

static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_TYPE_FORM_PATH = 1u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_ERROR = 4u;

static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool is_hir_type_node(uint node)
{
    return valid_node(node) && hir_kind[node] == HIR_TYPE &&
           hir_type_form[node] != HIR_TYPE_FORM_NONE;
}

uint path_leaf_token_for_type_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint path_node = hir_type_value_node[node];
    uint end = valid_node(path_node) ? hir_token_end[path_node] : INVALID;
    if (end == INVALID || end == 0u || end > gParams.n_tokens)
        return hir_token_pos[node];
    return end - 1u;
}

uint nearest_type_ancestor(uint node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < MAX_PARENT_WALK; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        if (hir_kind[p] == HIR_TYPE)
            return p;
        cur = p;
    }
    return INVALID;
}

bool has_type_args_ancestor_before(uint node, uint stop)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < MAX_PARENT_WALK; guard += 1u)
    {
        if (!valid_node(cur))
            return false;
        uint p = parent[cur];
        if (!valid_node(p) || p == stop)
            return false;
        if (node_kind[p] == PROD_TYPE_ARGS_SOME ||
            node_kind[p] == PROD_TYPE_ARGS_AFTER_COMMA_MORE)
            return true;
        cur = p;
    }
    return false;
}

bool is_top_level_type_arg_for(uint candidate, uint root)
{
    return is_hir_type_node(candidate) && candidate != root &&
           nearest_type_ancestor(candidate) == root &&
           has_type_args_ancestor_before(candidate, root);
}

uint arg_ref_index(uint instance_i, uint slot)
{
    return instance_i * TYPE_INSTANCE_ARG_REF_STRIDE + slot;
}

void clear_arg_refs(uint instance_i)
{
    type_instance_arg_start[instance_i] = INVALID;
    [unroll]
    for (uint slot = 0u; slot < TYPE_INSTANCE_ARG_REF_STRIDE; slot += 1u)
    {
        uint out_i = arg_ref_index(instance_i, slot);
        type_instance_arg_ref_tag[out_i] = TYPE_REF_INVALID;
        type_instance_arg_ref_payload[out_i] = INVALID;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = linear_thread_id(dtid);
    if (!is_hir_type_node(root) || hir_type_form[root] != HIR_TYPE_FORM_PATH)
        return;

    uint leaf_token = path_leaf_token_for_type_node(root);
    if (!valid_token(leaf_token))
        return;

    uint slot = 0u;
    clear_arg_refs(leaf_token);
    type_instance_arg_start[leaf_token] = arg_ref_index(leaf_token, 0u);

    uint active = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < active; node += 1u)
    {
        if (!is_top_level_type_arg_for(node, root))
            continue;
        if (slot >= TYPE_INSTANCE_ARG_REF_STRIDE)
        {
            type_instance_state[leaf_token] = TYPE_INSTANCE_UNSUPPORTED;
            return;
        }

        uint arg_token = hir_token_pos[node];
        uint out_i = arg_ref_index(leaf_token, slot);
        if (!valid_token(arg_token) || type_expr_ref_tag[arg_token] == TYPE_REF_INVALID)
        {
            type_instance_arg_ref_tag[out_i] = TYPE_REF_ERROR;
            type_instance_arg_ref_payload[out_i] = leaf_token;
            type_instance_state[leaf_token] = TYPE_INSTANCE_UNSUPPORTED;
            return;
        }

        type_instance_arg_ref_tag[out_i] = type_expr_ref_tag[arg_token];
        type_instance_arg_ref_payload[out_i] = type_expr_ref_payload[arg_token];
        slot += 1u;
    }

    if (slot == 0u)
        type_instance_arg_start[leaf_token] = INVALID;
}
