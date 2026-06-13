// Trim parser-owned range expression spans to their recorded operands.
//
// Range bounds reuse postfix tails after a range-only identifier token. Empty
// postfix-tail rows are anchored at the following token, so the initial tree
// span can include the body opener. This pass consumes expression/root records
// and already-widened postfix spans instead of rediscovering token shape.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExpr;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> hir_token_end;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR = 14u;
static const uint HIR_EXPR_RANGE = 30u;
static const uint HIR_EXPR_RANGE_FROM = 31u;
static const uint HIR_EXPR_RANGE_TO = 32u;
static const uint HIR_EXPR_RANGE_FULL = 33u;
static const uint HIR_EXPR_RANGE_INCLUSIVE = 34u;
static const uint HIR_EXPR_RANGE_TO_INCLUSIVE = 35u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirExpr.uses_status_count != 0u ? min(gHirExpr.n, tree_count_status[5u]) : gHirExpr.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint expr_record(uint node, uint field)
{
    return hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + field];
}

bool is_range_form(uint form)
{
    return form == HIR_EXPR_RANGE ||
           form == HIR_EXPR_RANGE_FROM ||
           form == HIR_EXPR_RANGE_TO ||
           form == HIR_EXPR_RANGE_FULL ||
           form == HIR_EXPR_RANGE_INCLUSIVE ||
           form == HIR_EXPR_RANGE_TO_INCLUSIVE;
}

uint expression_edge_end(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? hir_token_end[root] : hir_token_end[node];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = row;
    if (!valid_node(node))
        return;

    if (!is_range_form(expr_record(node, HIR_EXPR_RECORD_FORM)))
        return;

    uint right = expr_record(node, HIR_EXPR_RECORD_RIGHT);
    uint end = expression_edge_end(right);
    if (end != INVALID)
    {
        hir_token_end[node] = end;
        return;
    }

    uint form = expr_record(node, HIR_EXPR_RECORD_FORM);
    if (form == HIR_EXPR_RANGE_FROM)
    {
        uint left = expr_record(node, HIR_EXPR_RECORD_LEFT);
        uint left_end = expression_edge_end(left);
        if (left_end != INVALID && left_end < hir_token_end[node])
            hir_token_end[node] = left_end + 1u;
        return;
    }

    if (form == HIR_EXPR_RANGE_FULL && hir_token_pos[node] != INVALID &&
        hir_token_pos[node] < hir_token_end[node])
    {
        hir_token_end[node] = hir_token_pos[node] + 1u;
    }
}
