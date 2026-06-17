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
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_rank;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> type_instance_arg_row_start;
RWStructuredBuffer<uint> type_instance_arg_row_count_out;
RWStructuredBuffer<uint> type_instance_arg_row_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_row_ref_payload;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

static const uint HIR_TYPE = 5u;

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
    return valid_node(node) && hir_kind[node] == HIR_TYPE;
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

void mark_instance_unsupported(uint root, uint leaf_token)
{
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

bool publish_arg_ref(uint leaf_token, uint ordinal, uint node)
{
    if (!valid_node(node))
        return false;

    uint row_start = type_instance_arg_row_start[leaf_token];
    uint row_i = row_start == INVALID ? INVALID : row_start + ordinal;
    if (row_i == INVALID || row_i >= type_instance_arg_row_count_out[0u])
        return false;

    uint arg_token = hir_token_pos[node];
    uint tag = TYPE_REF_ERROR;
    uint payload = leaf_token;
    if (!valid_token(arg_token) || type_expr_ref_tag[arg_token] == TYPE_REF_INVALID)
    {
        type_instance_arg_row_ref_tag[row_i] = TYPE_REF_ERROR;
        type_instance_arg_row_ref_payload[row_i] = leaf_token;
        if (ordinal < TYPE_INSTANCE_ARG_REF_STRIDE)
        {
            uint out_i = arg_ref_index(leaf_token, ordinal);
            type_instance_arg_ref_tag[out_i] = TYPE_REF_ERROR;
            type_instance_arg_ref_payload[out_i] = leaf_token;
        }
        return false;
    }

    tag = type_expr_ref_tag[arg_token];
    payload = type_expr_ref_payload[arg_token];
    type_instance_arg_row_ref_tag[row_i] = tag;
    type_instance_arg_row_ref_payload[row_i] = payload;
    if (ordinal < TYPE_INSTANCE_ARG_REF_STRIDE)
    {
        uint out_i = arg_ref_index(leaf_token, ordinal);
        type_instance_arg_ref_tag[out_i] = tag;
        type_instance_arg_ref_payload[out_i] = payload;
    }
    return true;
}

bool row_arg_ref_published(uint leaf_token, uint ordinal)
{
    uint row_start = type_instance_arg_row_start[leaf_token];
    uint row_i = row_start == INVALID ? INVALID : row_start + ordinal;
    return row_i != INVALID &&
           row_i < type_instance_arg_row_count_out[0u] &&
           type_instance_arg_row_ref_tag[row_i] != TYPE_REF_INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!is_hir_type_node(node))
        return;

    uint root = hir_type_arg_owner[node];
    if (!is_hir_type_node(root) || hir_type_form[root] != HIR_TYPE_FORM_PATH)
        return;

    uint leaf_token = path_leaf_token_for_type_node(root);
    if (!valid_token(leaf_token))
        return;

    uint arg_count = hir_type_arg_count[root];
    uint ordinal = hir_type_arg_rank[node];
    if (arg_count == 0u || ordinal >= arg_count ||
        type_instance_arg_count[leaf_token] != arg_count ||
        type_instance_arg_start[leaf_token] == INVALID)
    {
        mark_instance_unsupported(root, leaf_token);
        return;
    }

    if (!publish_arg_ref(leaf_token, ordinal, node) &&
        !row_arg_ref_published(leaf_token, ordinal))
    {
        mark_instance_unsupported(root, leaf_token);
    }
}
