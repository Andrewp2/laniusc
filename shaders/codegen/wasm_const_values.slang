// WASM const value projection over HIR statement/expression records.
//
// This mirrors the x86 const projection: const declarations are scattered by
// declaration token so later WASM lowering can resolve names through
// visible_decl and consume a small value table instead of rediscovering syntax.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_stmt_record;

RWStructuredBuffer<uint2> wasm_const_value_record;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_NEG = 13u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
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

uint stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(node))
            return INVALID;
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        node = expr_left(node);
    }
    return INVALID;
}

bool literal_leaf_value(uint value_node, out uint value)
{
    value = 0u;
    value_node = resolve_expr(value_node);
    if (!valid_node(value_node))
        return false;

    uint form = expr_form(value_node);
    if (form == HIR_EXPR_INT)
    {
        value = hir_expr_int_value[value_node];
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    return false;
}

bool literal_expr_value(uint value_node, out uint value)
{
    value = 0u;
    if (literal_leaf_value(value_node, value))
        return true;

    value_node = resolve_expr(value_node);
    if (!valid_node(value_node))
        return false;

    uint form = expr_form(value_node);
    if (form == HIR_EXPR_NEG)
    {
        uint inner = 0u;
        if (!literal_leaf_value(expr_left(value_node), inner))
            return false;
        value = 0u - inner;
        return true;
    }
    if (form == HIR_EXPR_NOT)
    {
        uint inner = 0u;
        if (!literal_leaf_value(expr_left(value_node), inner))
            return false;
        value = inner == 0u ? 1u : 0u;
        return true;
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i >= active_hir_node_count())
        return;
    if (stmt_record_slot(node_i, 0u) != STMT_RECORD_KIND_CONST)
        return;

    uint decl_i = stmt_record_slot(node_i, 1u);
    if (!valid_token(decl_i))
        return;

    uint value = 0u;
    uint expr_node = stmt_record_slot(node_i, 2u);
    if (!literal_expr_value(expr_node, value))
        return;

    wasm_const_value_record[decl_i] = uint2(WASM_CONST_VALUE_LITERAL, value);
}
