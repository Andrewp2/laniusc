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
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_param_type_node;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;

RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint HIR_PARAM = 4u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;

static const uint TYPE_REF_INVALID = 0u;

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

void publish_stmt_decl_ref(uint node)
{
    uint kind = hir_stmt_record[stmt_slot(node, 0u)];
    if (kind != STMT_RECORD_KIND_LET && kind != STMT_RECORD_KIND_CONST)
        return;

    uint decl_token = hir_stmt_record[stmt_slot(node, 1u)];
    publish_decl_ref(decl_token, stmt_type_node(node));
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
    publish_param_decl_ref(node);
}
