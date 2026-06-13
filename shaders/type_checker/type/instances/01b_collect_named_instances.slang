// HIR-driven named generic type-instance collection.
//
// This pass identifies type nodes with top-level type arguments from
// parser-owned HIR type records. It publishes the owner type expression as an
// instance and creates the token-indexed named instance record keyed by the
// path leaf token.

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
StructuredBuffer<uint> hir_type_arg_count;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_head_token;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

static const uint HIR_TYPE = 5u;

static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_TYPE_FORM_PATH = 1u;

static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_UNRESOLVED = 2u;
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

uint top_level_type_arg_count(uint root)
{
    return valid_node(root) ? hir_type_arg_count[root] : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!is_hir_type_node(node) || hir_type_form[node] != HIR_TYPE_FORM_PATH)
        return;

    uint owner_token = hir_token_pos[node];
    if (!valid_token(owner_token))
        return;

    uint leaf_token = path_leaf_token_for_type_node(node);
    if (!valid_token(leaf_token))
        return;

    uint arg_count = top_level_type_arg_count(node);
    if (arg_count == 0u)
        return;

    type_expr_ref_tag[owner_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[owner_token] = leaf_token;
    type_expr_ref_tag[leaf_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[leaf_token] = leaf_token;
    type_instance_kind[leaf_token] = TYPE_INSTANCE_NAMED;
    type_instance_head_token[leaf_token] = leaf_token;
    type_instance_arg_count[leaf_token] = arg_count;
    type_instance_state[leaf_token] = arg_count <= TYPE_INSTANCE_ARG_REF_STRIDE
                                       ? TYPE_INSTANCE_UNRESOLVED
                                       : TYPE_INSTANCE_UNSUPPORTED;
}
