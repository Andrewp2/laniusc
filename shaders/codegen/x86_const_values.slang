// x86_64 const value projection over HIR statement/expression records.
//
// This pass scatters supported const literal values by declaration token. Later
// x86 value consumers can resolve a name through visible_decl and read this
// table directly instead of scanning all HIR statements to rediscover consts.

import gpu_index;
import status;
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
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_stmt_record;

RWStructuredBuffer<uint2> x86_const_value_record;
RWStructuredBuffer<uint> x86_const_value_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
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
static const uint X86_CONST_VALUE_LITERAL = 1u;
static const uint X86_CONST_VALUES_OK = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node)
{
    return valid_index_or_invalid(node, active_hir_node_count(), INVALID);
}

bool valid_token(uint token)
{
    return valid_index_or_invalid(token, gParams.n_tokens, INVALID);
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

uint expr_root_node(uint node)
{
    return valid_node(node) ? hir_expr_result_root_node[node] : INVALID;
}

bool literal_leaf_value(uint value_node, out uint value)
{
    value = 0u;
    value_node = expr_root_node(value_node);
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

    value_node = expr_root_node(value_node);
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
    if (node_i == 0u)
    {
        x86_const_value_status[0u] = X86_CONST_VALUES_OK;
        x86_const_value_status[1u] = 0u;
        x86_const_value_status[2u] = INVALID;
    }

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

    x86_const_value_record[decl_i] = uint2(X86_CONST_VALUE_LITERAL, value);
}
