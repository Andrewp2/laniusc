// x86_64 local literal projection over HIR statement/expression records.
//
// This pass projects immediately available scalar literal/constant let bindings
// by declaration token. It is a best-effort acceleration table:
// consumers must still be able to lower ordinary local values through generic
// virtual load/store instructions when a local has no projected literal.

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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint2> x86_const_value_record;
StructuredBuffer<uint> x86_const_value_status;

RWStructuredBuffer<uint> x86_local_literal_record;
RWStructuredBuffer<uint> x86_local_literal_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint X86_LOCAL_LITERALS_OK = 1u;
static const uint X86_LOCAL_LITERAL_STRIDE = 3u;
static const uint X86_CONST_VALUES_OK = 1u;
static const uint X86_CONST_VALUE_LITERAL = 1u;

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

uint expr_right(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_RIGHT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint owning_function_node(uint node)
{
    return valid_node(node) ? x86_node_func[node] : INVALID;
}

bool const_values_ok()
{
    return x86_const_value_status[0u] == X86_CONST_VALUES_OK &&
           x86_const_value_status[1u] == 0u;
}

uint local_literal_word(uint decl_token, uint slot)
{
    if (!valid_token(decl_token) || slot >= X86_LOCAL_LITERAL_STRIDE)
        return INVALID;
    return x86_local_literal_record[
        row_major_slot(decl_token, X86_LOCAL_LITERAL_STRIDE, slot)];
}

uint local_literal_owner(uint decl_token)
{
    return local_literal_word(decl_token, 0u);
}

uint local_literal_let_node(uint decl_token)
{
    return local_literal_word(decl_token, 1u);
}

uint local_literal_value(uint decl_token)
{
    return local_literal_word(decl_token, 2u);
}

void write_local_literal_record(uint decl_token, uint fn_node, uint let_node, uint value)
{
    row_major_store<uint>(
        x86_local_literal_record,
        decl_token,
        X86_LOCAL_LITERAL_STRIDE,
        0u,
        fn_node);
    row_major_store<uint>(
        x86_local_literal_record,
        decl_token,
        X86_LOCAL_LITERAL_STRIDE,
        1u,
        let_node);
    row_major_store<uint>(
        x86_local_literal_record,
        decl_token,
        X86_LOCAL_LITERAL_STRIDE,
        2u,
        value);
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
    if (form == HIR_EXPR_FLOAT)
    {
        value = hir_expr_float_bits[value_node];
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    return false;
}

bool const_atom_value(uint token_i, out uint value)
{
    value = 0u;
    if (!const_values_ok() || !valid_token(token_i))
        return false;

    uint decl_i = visible_decl[token_i];
    if (!valid_token(decl_i))
        return false;

    uint2 record = x86_const_value_record[decl_i];
    if (record.x != X86_CONST_VALUE_LITERAL)
        return false;

    value = record.y;
    return true;
}

bool local_atom_value(
    uint token_i,
    uint fn_node,
    out uint value)
{
    value = 0u;
    if (!valid_token(token_i) || !valid_node(fn_node))
        return false;

    uint decl_i = visible_decl[token_i];
    if (!valid_token(decl_i))
        return false;

    if (local_literal_owner(decl_i) != fn_node ||
        local_literal_let_node(decl_i) == INVALID)
        return false;

    value = local_literal_value(decl_i);
    return true;
}

bool expr_leaf_value(
    uint value_node,
    uint fn_node,
    uint before_node,
    out uint value)
{
    value = 0u;
    value_node = resolve_expr(value_node);
    if (literal_leaf_value(value_node, value))
        return true;
    if (!valid_node(value_node))
        return false;

    if (expr_form(value_node) == HIR_EXPR_NAME)
    {
        uint token_i = expr_value_token(value_node);
        if (const_atom_value(token_i, value))
            return true;
        return local_atom_value(token_i, fn_node, value);
    }
    return false;
}

bool scalar_projection_value(
    uint root,
    uint fn_node,
    uint before_node,
    out uint value)
{
    value = 0u;
    root = resolve_expr(root);
    if (!valid_node(root))
        return false;

    if (expr_leaf_value(root, fn_node, before_node, value))
        return true;

    uint form = expr_form(root);
    if (form != HIR_EXPR_NEG && form != HIR_EXPR_NOT)
        return false;

    uint operand = 0u;
    if (!expr_leaf_value(expr_left(root), fn_node, before_node, operand))
        return false;

    value = form == HIR_EXPR_NEG ? 0u - operand : (operand == 0u ? 1u : 0u);
    return true;
}

void scatter_local_literal(uint let_node)
{
    if (stmt_record_slot(let_node, 0u) != STMT_RECORD_KIND_LET)
        return;

    uint fn_node = owning_function_node(let_node);
    if (!valid_node(fn_node))
        return;

    uint decl_i = stmt_record_slot(let_node, 1u);
    if (!valid_token(decl_i))
        return;

    uint value = 0u;
    uint expr_node = stmt_record_slot(let_node, 2u);
    if (!scalar_projection_value(expr_node, fn_node, let_node, value))
        return;

    write_local_literal_record(decl_i, fn_node, let_node, value);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i >= active_hir_node_count())
        return;

    scatter_local_literal(node_i);
}
