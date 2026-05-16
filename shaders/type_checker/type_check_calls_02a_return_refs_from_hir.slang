// HIR function return type-reference projection.
//
// This pass consumes parser-owned function item/type records and writes
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
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;

RWStructuredBuffer<uint> fn_return_ref_tag;
RWStructuredBuffer<uint> fn_return_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;

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

bool function_item_kind(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_FN || item_kind == HIR_ITEM_KIND_EXTERN_FN;
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

uint direct_child_with_production(uint node, uint prod)
{
    uint child = first_child_node(node);
    [loop]
    for (uint guard = 0u; guard < 32u && valid_node(child); guard += 1u)
    {
        if (node_kind[child] == prod)
            return child;
        child = next_sibling_node(child);
    }
    return INVALID;
}

uint return_type_node(uint fn_node)
{
    uint ret_node = direct_child_with_production(fn_node, PROD_RET_TYPE);
    return first_child_node(ret_node);
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
    if (node >= active_hir_node_count())
        return;
    if (!function_item_kind(hir_item_kind[node]))
        return;

    publish_function_return_ref(node);
}
