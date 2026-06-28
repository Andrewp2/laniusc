// HIR declaration type-reference projection.
//
// This pass publishes declaration-token keyed type refs for local lets,
// constants, and named parameters. Later semantic passes consume these records
// instead of deriving declaration type heads from token offsets.

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
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_param_type_node;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint HIR_PARAM = 4u;
static const uint HIR_STMT = 7u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_ERROR = 4u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint result_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

uint name_or_path_token_for_node(uint node)
{
    if (!valid_node(node) ||
        (hir_kind[node] != HIR_NAME_EXPR && hir_kind[node] != HIR_PATH_EXPR))
        return INVALID;

    uint token = expr_slot(node, EXPR_RECORD_VALUE_TOKEN);
    return valid_token(token) ? token : hir_token_pos[node];
}

uint name_token_for_expr(uint root)
{
    uint token = name_or_path_token_for_node(root);
    if (valid_token(token))
        return token;

    return name_or_path_token_for_node(result_expr(root));
}

uint stmt_type_node(uint stmt_node)
{
    if (!valid_node(stmt_node))
        return INVALID;
    uint type_node = hir_stmt_record[stmt_slot(stmt_node, 3u)];
    return valid_node(type_node) ? type_node : INVALID;
}

uint param_type_node(uint param_node)
{
    return valid_node(param_node) ? hir_param_type_node[param_node] : INVALID;
}

void publish_decl_ref(uint decl_token, uint type_node)
{
    if (!valid_token(decl_token) || !valid_node(type_node))
        return;

    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return;

    uint tag = type_expr_ref_tag[type_token];
    uint payload = type_expr_ref_payload[type_token];
    if (tag == TYPE_REF_INVALID)
        return;

    decl_type_ref_tag[decl_token] = tag;
    decl_type_ref_payload[decl_token] = payload;
}

void publish_decl_ref_value(uint decl_token, uint tag, uint payload)
{
    if (!valid_token(decl_token))
        return;
    if (tag == TYPE_REF_INVALID || tag == TYPE_REF_ERROR || payload == INVALID)
        return;

    decl_type_ref_tag[decl_token] = tag;
    decl_type_ref_payload[decl_token] = payload;
}

void publish_stmt_decl_ref(uint node)
{
    uint kind = hir_stmt_record[stmt_slot(node, 0u)];
    if (kind != STMT_RECORD_KIND_LET && kind != STMT_RECORD_KIND_CONST)
        return;

    uint decl_token = hir_stmt_record[stmt_slot(node, 1u)];
    publish_decl_ref(decl_token, stmt_type_node(node));
}

void publish_for_decl_ref(uint node)
{
    if (!valid_node(node) ||
        (hir_kind[node] != HIR_STMT && hir_kind[node] != HIR_FOR_STMT))
        return;

    uint kind = hir_stmt_record[stmt_slot(node, 0u)];
    if (kind != STMT_RECORD_KIND_FOR)
        return;

    uint decl_token = hir_stmt_record[stmt_slot(node, 1u)];
    uint iterable_node = hir_stmt_record[stmt_slot(node, 2u)];
    uint iterable_token = name_token_for_expr(iterable_node);
    uint iterable_decl = valid_token(iterable_token) ? visible_decl[iterable_token] : INVALID;
    if (!valid_token(iterable_decl))
        return;

    uint instance = decl_type_ref_payload[iterable_decl];
    if (decl_type_ref_tag[iterable_decl] != TYPE_REF_INSTANCE || !valid_token(instance))
        return;

    uint instance_kind = type_instance_kind[instance];
    if (instance_kind != TYPE_INSTANCE_ARRAY && instance_kind != TYPE_INSTANCE_SLICE)
        return;

    publish_decl_ref_value(
        decl_token,
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
}

void publish_param_decl_ref(uint node)
{
    if (hir_kind[node] != HIR_PARAM)
        return;

    uint4 record = hir_param_record[node];
    uint decl_token = record.z;
    publish_decl_ref(decl_token, param_type_node(node));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    publish_stmt_decl_ref(node);
    publish_for_decl_ref(node);
    publish_param_decl_ref(node);
}
