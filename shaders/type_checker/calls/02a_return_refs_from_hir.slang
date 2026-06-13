// HIR function return type-reference projection.
//
// This pass consumes parser-owned function return-type records and writes
// declaration-token keyed return references for regular and extern functions.
// It does not inspect token spelling, source bytes, value names, or function
// bodies.

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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_fn_return_type_node;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;

RWStructuredBuffer<uint> fn_return_ref_tag;
RWStructuredBuffer<uint> fn_return_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_FN = 3u;

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

bool function_item_kind(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_FN || item_kind == HIR_ITEM_KIND_EXTERN_FN;
}

bool function_decl_node(uint node)
{
    return function_item_kind(hir_item_kind[node]) ||
           (hir_kind[node] == HIR_FN && node_kind[node] == PROD_IMPL_FN);
}

uint return_type_node(uint fn_node)
{
    if (!valid_node(fn_node))
        return INVALID;
    uint type_node = hir_fn_return_type_node[fn_node];
    return valid_node(type_node) ? type_node : INVALID;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

void publish_function_return_ref(uint fn_node)
{
    uint decl_token = hir_token_pos[fn_node];
    if (!valid_token(decl_token))
        return;

    fn_return_ref_tag[decl_token] = TYPE_REF_INVALID;
    fn_return_ref_payload[decl_token] = INVALID;

    uint type_node = return_type_node(fn_node);
    if (!valid_node(type_node))
        return;

    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return;

    fn_return_ref_tag[decl_token] = type_expr_ref_tag[type_token];
    fn_return_ref_payload[decl_token] = type_expr_ref_payload[type_token];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    if (!function_decl_node(node) && !valid_node(return_type_node(node)))
        return;

    publish_function_return_ref(node);
}
