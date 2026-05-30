// HIR-driven named generic argument refs.
//
// This pass runs after type-expression refs have been collected and after any
// declaration binding pass has had a chance to attach the named instance to a
// resolved declaration. It overwrites generic argument refs from parser-owned
// top-level HIR type-argument nodes instead of re-scanning token neighborhoods.

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
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_type_arg_start;
StructuredBuffer<uint> hir_type_arg_count;
StructuredBuffer<uint> hir_type_arg_next;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
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
    uint leaf_node = valid_node(node) ? hir_type_path_leaf_node[node] : INVALID;
    return valid_node(leaf_node) ? hir_token_pos[leaf_node] : INVALID;
}

uint arg_ref_index(uint instance_i, uint slot)
{
    return instance_i * TYPE_INSTANCE_ARG_REF_STRIDE + slot;
}

void clear_arg_refs(uint instance_i)
{
    type_instance_arg_start[instance_i] = INVALID;
    uint out_0 = arg_ref_index(instance_i, 0u);
    uint out_1 = arg_ref_index(instance_i, 1u);
    uint out_2 = arg_ref_index(instance_i, 2u);
    uint out_3 = arg_ref_index(instance_i, 3u);
    type_instance_arg_ref_tag[out_0] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[out_0] = INVALID;
    type_instance_arg_ref_tag[out_1] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[out_1] = INVALID;
    type_instance_arg_ref_tag[out_2] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[out_2] = INVALID;
    type_instance_arg_ref_tag[out_3] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[out_3] = INVALID;
}

void mark_instance_unsupported(uint root, uint leaf_token)
{
    clear_arg_refs(leaf_token);
    type_instance_state[leaf_token] = TYPE_INSTANCE_UNSUPPORTED;

    uint owner_token = valid_node(root) ? hir_token_pos[root] : INVALID;
    if (valid_token(owner_token))
    {
        type_expr_ref_tag[owner_token] = TYPE_REF_ERROR;
        type_expr_ref_payload[owner_token] = leaf_token;
    }
    if (valid_token(leaf_token))
    {
        type_expr_ref_tag[leaf_token] = TYPE_REF_ERROR;
        type_expr_ref_payload[leaf_token] = leaf_token;
    }
}

bool publish_arg_ref_slot(uint leaf_token, uint slot, uint node, out uint next_node)
{
    next_node = INVALID;
    if (!valid_node(node))
        return false;

    uint arg_token = hir_token_pos[node];
    uint out_i = arg_ref_index(leaf_token, slot);
    if (!valid_token(arg_token) || type_expr_ref_tag[arg_token] == TYPE_REF_INVALID)
    {
        type_instance_arg_ref_tag[out_i] = TYPE_REF_ERROR;
        type_instance_arg_ref_payload[out_i] = leaf_token;
        return false;
    }

    type_instance_arg_ref_tag[out_i] = type_expr_ref_tag[arg_token];
    type_instance_arg_ref_payload[out_i] = type_expr_ref_payload[arg_token];
    next_node = hir_type_arg_next[node];
    return true;
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

    uint arg_count = hir_type_arg_count[root];
    if (arg_count > TYPE_INSTANCE_ARG_REF_STRIDE)
    {
        mark_instance_unsupported(root, leaf_token);
        return;
    }

    uint node = hir_type_arg_start[root];
    uint next_node = INVALID;
    if (arg_count > 0u)
    {
        if (!publish_arg_ref_slot(leaf_token, 0u, node, next_node))
        {
            mark_instance_unsupported(root, leaf_token);
            return;
        }
        slot += 1u;
        node = next_node;
    }
    if (arg_count > 1u)
    {
        if (!publish_arg_ref_slot(leaf_token, 1u, node, next_node))
        {
            mark_instance_unsupported(root, leaf_token);
            return;
        }
        slot += 1u;
        node = next_node;
    }
    if (arg_count > 2u)
    {
        if (!publish_arg_ref_slot(leaf_token, 2u, node, next_node))
        {
            mark_instance_unsupported(root, leaf_token);
            return;
        }
        slot += 1u;
        node = next_node;
    }
    if (arg_count > 3u)
    {
        if (!publish_arg_ref_slot(leaf_token, 3u, node, next_node))
        {
            mark_instance_unsupported(root, leaf_token);
            return;
        }
        slot += 1u;
        node = next_node;
    }

    if (arg_count == 0u)
        type_instance_arg_start[leaf_token] = INVALID;

    if (slot != arg_count || valid_node(node))
    {
        mark_instance_unsupported(root, leaf_token);
        return;
    }
}
