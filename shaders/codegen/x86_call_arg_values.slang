// x86_64 call-argument value projection over HIR expression records.
//
// This pass owns bounded argument expression discovery for direct calls. ABI
// projection consumes argument identity only; later vreg planning consumes the
// value/eval rows.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

struct StatusRecord
{
    uint state;
    uint error;
    uint detail;
    uint count;
};

ConstantBuffer<Params> gParams;
ConstantBuffer<StatusRecord> x86_param_reg_status;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint4> x86_const_value_record;
StructuredBuffer<uint> x86_const_value_status;
StructuredBuffer<uint4> x86_param_reg_record;
StructuredBuffer<uint4> x86_local_literal_record;
StructuredBuffer<uint> x86_local_literal_status;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_ordinal;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint> call_record_status;

RWStructuredBuffer<uint4> x86_call_arg_value_record;
RWStructuredBuffer<uint4> x86_call_arg_eval_record;
RWStructuredBuffer<uint> call_arg_value_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_EXPR_FORWARD = 1u;
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
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ARG_VALUES_OK = 1u;
static const uint X86_CONST_VALUES_OK = 1u;
static const uint X86_CONST_VALUE_LITERAL = 1u;
static const uint X86_PARAM_REGS_OK = 1u;
static const uint X86_LOCAL_LITERALS_OK = 1u;
static const uint X86_LOCAL_LITERAL_TOP_LEVEL = 1u;
static const uint X86_CALL_ARG_VALUE_SCALAR = 1u;
static const uint X86_CALL_ARG_VALUE_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_VALUE_PARAM = 3u;
static const uint X86_CALL_ARG_EVAL_SCALAR_IMM = 1u;
static const uint X86_CALL_ARG_EVAL_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_EVAL_PARAM_REG = 3u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
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

bool call_records_ok()
{
    return call_record_status[0u] == X86_CALL_RECORDS_OK && call_record_status[1u] == 0u;
}

bool const_values_ok()
{
    return x86_const_value_status[0u] == X86_CONST_VALUES_OK &&
           x86_const_value_status[1u] == 0u;
}

bool param_regs_ok()
{
    return x86_param_reg_status.state == X86_PARAM_REGS_OK &&
           x86_param_reg_status.error == 0u;
}

bool local_literals_ok()
{
    return x86_local_literal_status[0u] == X86_LOCAL_LITERALS_OK &&
           x86_local_literal_status[1u] == 0u;
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return record.x != INVALID || record.y != INVALID ||
           record.z != INVALID || record.w != INVALID;
}

uint expr_record_slot(uint node, uint slot)
{
    return hir_expr_record[node * EXPR_RECORD_STRIDE + slot];
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

bool const_atom_value(uint token_i, out uint value)
{
    value = 0u;
    if (!const_values_ok() || !valid_token(token_i))
        return false;

    uint decl_i = visible_decl[token_i];
    if (!valid_token(decl_i))
        return false;

    uint4 record = x86_const_value_record[decl_i];
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
    if (!local_literals_ok() || !valid_token(token_i) || !valid_node(fn_node))
        return false;

    uint decl_i = visible_decl[token_i];
    if (!valid_token(decl_i))
        return false;

    uint4 record = x86_local_literal_record[decl_i];
    if (record.x != fn_node || record.y == INVALID)
        return false;
    if (record.w != X86_LOCAL_LITERAL_TOP_LEVEL)
        return false;

    value = record.z;
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

bool parameter_register_for_decl(uint fn_node, uint decl_token, out uint arg_reg)
{
    arg_reg = INVALID;
    if (!param_regs_ok() || !valid_node(fn_node) || !valid_token(decl_token))
        return false;

    uint4 record = x86_param_reg_record[decl_token];
    if (record.x != fn_node || record.z == INVALID)
        return false;

    arg_reg = record.z;
    return true;
}

bool expr_param_register(uint value_node, uint fn_node, out uint arg_reg)
{
    arg_reg = INVALID;
    value_node = resolve_expr(value_node);
    if (!valid_node(value_node) || expr_form(value_node) != HIR_EXPR_NAME)
        return false;

    uint token_i = expr_value_token(value_node);
    if (!valid_token(token_i))
        return false;

    uint decl_token = visible_decl[token_i];
    return parameter_register_for_decl(fn_node, decl_token, arg_reg);
}

bool expr_unary_or_leaf_value(
    uint value_node,
    uint fn_node,
    uint before_node,
    out uint value)
{
    value = 0u;
    value_node = resolve_expr(value_node);
    if (expr_leaf_value(
            value_node,
            fn_node,
            before_node,
            value))
        return true;
    if (!valid_node(value_node))
        return false;

    uint form = expr_form(value_node);
    if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
    {
        uint operand = 0u;
        if (!expr_leaf_value(
                expr_left(value_node),
                fn_node,
                before_node,
                operand))
            return false;
        value = form == HIR_EXPR_NEG ? 0u - operand : (operand == 0u ? 1u : 0u);
        return true;
    }
    return false;
}

uint binary_value(uint form, uint left, uint right, out bool ok)
{
    ok = true;
    if (form == HIR_EXPR_ADD)
        return left + right;
    if (form == HIR_EXPR_SUB)
        return left - right;
    if (form == HIR_EXPR_MUL)
        return left * right;
    if (form == HIR_EXPR_EQ)
        return left == right ? 1u : 0u;
    if (form == HIR_EXPR_NE)
        return left != right ? 1u : 0u;
    if (form == HIR_EXPR_LT)
        return int(left) < int(right) ? 1u : 0u;
    if (form == HIR_EXPR_GT)
        return int(left) > int(right) ? 1u : 0u;
    if (form == HIR_EXPR_LE)
        return int(left) <= int(right) ? 1u : 0u;
    if (form == HIR_EXPR_GE)
        return int(left) >= int(right) ? 1u : 0u;
    if (form == HIR_EXPR_MOD)
    {
        if (right == 0u)
        {
            ok = false;
            return 0u;
        }
        return left % right;
    }
    if (form == HIR_EXPR_DIV)
    {
        if (right == 0u)
        {
            ok = false;
            return 0u;
        }
        return uint(int(left) / int(right));
    }
    if (form == HIR_EXPR_AND)
        return (left != 0u && right != 0u) ? 1u : 0u;
    if (form == HIR_EXPR_OR)
        return (left != 0u || right != 0u) ? 1u : 0u;
    if (form == HIR_EXPR_BIT_AND)
        return left & right;
    if (form == HIR_EXPR_BIT_OR)
        return left | right;
    if (form == HIR_EXPR_BIT_XOR)
        return left ^ right;
    if (form == HIR_EXPR_SHL)
        return left << (right & 31u);
    if (form == HIR_EXPR_SHR)
        return uint(int(left) >> int(right & 31u));
    ok = false;
    return 0u;
}

uint binary_op_for_expr_form(uint form)
{
    if (form == HIR_EXPR_ADD)
        return 1u;
    if (form == HIR_EXPR_SUB)
        return 2u;
    if (form == HIR_EXPR_MUL)
        return 3u;
    if (form == HIR_EXPR_AND)
        return 4u;
    if (form == HIR_EXPR_OR)
        return 5u;
    if (form == HIR_EXPR_MOD)
        return 6u;
    if (form == HIR_EXPR_DIV)
        return 7u;
    if (form == HIR_EXPR_BIT_AND)
        return 8u;
    if (form == HIR_EXPR_BIT_OR)
        return 9u;
    if (form == HIR_EXPR_BIT_XOR)
        return 10u;
    if (form == HIR_EXPR_SHL)
        return 11u;
    if (form == HIR_EXPR_SHR)
        return 12u;
    return 0u;
}

bool expr_scalar_value(
    uint value_node,
    uint fn_node,
    uint before_node,
    out uint value)
{
    value = 0u;
    value_node = resolve_expr(value_node);
    if (!valid_node(value_node))
        return false;

    uint node_stack[32];
    uint state_stack[32];
    uint left_stack[32];
    uint sp = 1u;
    uint last_value = 0u;
    node_stack[0u] = value_node;
    state_stack[0u] = 0u;
    left_stack[0u] = 0u;

    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (sp == 0u)
        {
            value = last_value;
            return true;
        }

        uint frame = sp - 1u;
        uint node = resolve_expr(node_stack[frame]);
        if (!valid_node(node))
            return false;

        uint state = state_stack[frame];
        uint form = expr_form(node);
        if (state == 0u)
        {
            if (expr_leaf_value(node, fn_node, before_node, last_value))
            {
                sp -= 1u;
                continue;
            }
            if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
            {
                if (sp >= 32u)
                    return false;
                state_stack[frame] = 1u;
                node_stack[sp] = expr_left(node);
                state_stack[sp] = 0u;
                left_stack[sp] = 0u;
                sp += 1u;
                continue;
            }
            bool op_ok = false;
            binary_value(form, 1u, 1u, op_ok);
            if (!op_ok)
                return false;
            if (sp >= 32u)
                return false;
            state_stack[frame] = 2u;
            node_stack[sp] = expr_left(node);
            state_stack[sp] = 0u;
            left_stack[sp] = 0u;
            sp += 1u;
            continue;
        }
        if (state == 1u)
        {
            last_value = form == HIR_EXPR_NEG ? 0u - last_value :
                                                (last_value == 0u ? 1u : 0u);
            sp -= 1u;
            continue;
        }
        if (state == 2u)
        {
            left_stack[frame] = last_value;
            state_stack[frame] = 3u;
            if (sp >= 32u)
                return false;
            node_stack[sp] = expr_right(node);
            state_stack[sp] = 0u;
            left_stack[sp] = 0u;
            sp += 1u;
            continue;
        }
        if (state == 3u)
        {
            bool ok = false;
            uint result = binary_value(form, left_stack[frame], last_value, ok);
            if (!ok)
                return false;
            last_value = result;
            sp -= 1u;
            continue;
        }
        return false;
    }
    return false;
}

bool expr_binary_imm_eval(
    uint value_node,
    uint fn_node,
    uint before_node,
    out uint left,
    out uint right,
    out uint op)
{
    left = 0u;
    right = 0u;
    op = 0u;
    value_node = resolve_expr(value_node);
    if (!valid_node(value_node))
        return false;

    bool op_ok = false;
    binary_value(expr_form(value_node), 0u, 0u, op_ok);
    if (!op_ok)
        return false;

    if (!expr_unary_or_leaf_value(
            expr_left(value_node),
            fn_node,
            before_node,
            left))
        return false;
    if (!expr_unary_or_leaf_value(
            expr_right(value_node),
            fn_node,
            before_node,
            right))
        return false;

    op = binary_op_for_expr_form(expr_form(value_node));
    return op != 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (!call_records_ok() || node_i >= active_hir_node_count())
        return;

    uint call_node = hir_call_arg_parent_call[node_i];
    if (!has_call_record(call_node))
        return;

    uint ordinal = hir_call_arg_ordinal[node_i];
    uint4 call_record = x86_call_record[call_node];
    if (ordinal >= call_record.w)
        return;

    uint arg_reg = INVALID;
    if (expr_param_register(node_i, call_record.x, arg_reg))
    {
        x86_call_arg_value_record[node_i] =
            uint4(call_node, ordinal, X86_CALL_ARG_VALUE_PARAM, arg_reg);
        x86_call_arg_eval_record[node_i] =
            uint4(X86_CALL_ARG_EVAL_PARAM_REG, arg_reg, INVALID, 0u);
        uint old_param_count = 0u;
        InterlockedAdd(call_arg_value_status[3u], 1u, old_param_count);
        return;
    }

    uint left = 0u;
    uint right = 0u;
    uint op = 0u;
    if (expr_binary_imm_eval(
            node_i,
            call_record.x,
            node_i,
            left,
            right,
            op))
    {
        x86_call_arg_value_record[node_i] =
            uint4(call_node, ordinal, X86_CALL_ARG_VALUE_BINARY_IMM, node_i);
        x86_call_arg_eval_record[node_i] =
            uint4(X86_CALL_ARG_EVAL_BINARY_IMM, left, right, op);
        uint old_binary_count = 0u;
        InterlockedAdd(call_arg_value_status[3u], 1u, old_binary_count);
        return;
    }

    uint value = 0u;
    if (!expr_scalar_value(
            node_i,
            call_record.x,
            node_i,
            value))
        return;

    x86_call_arg_value_record[node_i] =
        uint4(call_node, ordinal, X86_CALL_ARG_VALUE_SCALAR, value);
    x86_call_arg_eval_record[node_i] =
        uint4(X86_CALL_ARG_EVAL_SCALAR_IMM, value, INVALID, 0u);
    uint old_count = 0u;
    InterlockedAdd(call_arg_value_status[3u], 1u, old_count);
}
