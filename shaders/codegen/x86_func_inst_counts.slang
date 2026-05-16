// x86_64 per-function instruction-count planning.
//
// This pass counts the current entry function's already-lowered vreg graph.
// It intentionally does not count callee body shapes. Function calls must be
// restored through Pareas-style node-local instruction counts, not by
// classifying whole callee return expressions.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

struct RegallocStatus
{
    uint state;
    uint error;
    uint detail;
    uint count;
};

struct FuncMeta
{
    uint func_count;
    uint main_count;
    uint reserved0;
    uint reserved1;
    uint main_node;
    uint reserved2;
    uint reserved3;
    uint reserved4;
};

ConstantBuffer<Params> gParams;
ConstantBuffer<RegallocStatus> regalloc_status;
ConstantBuffer<FuncMeta> x86_func_meta;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint4> x86_const_value_record;
StructuredBuffer<uint4> x86_call_abi_record;
StructuredBuffer<uint4> x86_call_arg_lookup_record;
StructuredBuffer<uint4> x86_call_arg_eval_record;
StructuredBuffer<uint4> x86_func_return_stmt_record;
StructuredBuffer<uint4> x86_terminal_if_record;
StructuredBuffer<uint4> x86_param_reg_record;
StructuredBuffer<uint4> x86_intrinsic_call_record;
StructuredBuffer<uint> x86_intrinsic_call_status;
StructuredBuffer<uint> x86_vreg_kind;
StructuredBuffer<uint> x86_vreg_op;
StructuredBuffer<uint> x86_vreg_value;
StructuredBuffer<uint4> x86_vreg_args;
StructuredBuffer<uint> x86_return_vreg;

RWStructuredBuffer<uint4> x86_func_inst_count_record;
RWStructuredBuffer<uint> x86_func_inst_count_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_VREGS = 8u;
static const uint MAX_X86_INSTS = 256u;
static const uint X86_REGALLOC_OK = 1u;
static const uint X86_FUNC_INST_COUNT_OK = 1u;
static const uint X86_ERR_UNSUPPORTED_RETURN = 3u;
static const uint X86_VREG_IMM_I32 = 1u;
static const uint X86_VREG_BINARY_I32 = 2u;
static const uint X86_VREG_BRANCH_I32 = 3u;
static const uint X86_VREG_COMPARE_I32 = 4u;
static const uint X86_VREG_CALL_I32 = 5u;
static const uint X86_OP_ADD_I32 = 1u;
static const uint X86_OP_SUB_I32 = 2u;
static const uint X86_OP_MUL_I32 = 3u;
static const uint X86_OP_AND_BOOL = 4u;
static const uint X86_OP_OR_BOOL = 5u;
static const uint X86_OP_MOD_I32 = 6u;
static const uint X86_OP_DIV_I32 = 7u;
static const uint X86_OP_BIT_AND_I32 = 8u;
static const uint X86_OP_BIT_OR_I32 = 9u;
static const uint X86_OP_BIT_XOR_I32 = 10u;
static const uint X86_OP_SHL_I32 = 11u;
static const uint X86_OP_SHR_I32 = 12u;
static const uint X86_CMP_LT = 1u;
static const uint X86_CMP_GT = 2u;
static const uint X86_CMP_LE = 3u;
static const uint X86_CMP_GE = 4u;
static const uint X86_CMP_EQ = 5u;
static const uint X86_CMP_NE = 6u;
static const uint X86_CMP_UNSIGNED_FLAG = 0x80u;

static const uint X86_SELECT_SHAPE_LITERAL = 1u;
static const uint X86_SELECT_SHAPE_BINARY = 2u;
static const uint X86_SELECT_SHAPE_COMPARE = 3u;
static const uint X86_SELECT_SHAPE_BRANCH = 4u;
static const uint X86_SELECT_SHAPE_CALL = 5u;

static const uint HIR_FN = 3u;
static const uint HIR_IF_STMT = 10u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint X86_FUNC_LAYOUT_CALLER = 1u;
static const uint X86_FUNC_LAYOUT_CALLEE = 2u;
static const uint FUNC_META_MAIN_COUNT = 1u;
static const uint FUNC_META_MAIN_NODE = 4u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
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
static const uint X86_FUNC_RETURN_STMT_TOP_LEVEL = 1u;
static const uint X86_CALL_ARG_VALUE_SCALAR = 1u;
static const uint X86_CALL_ARG_VALUE_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_VALUE_PARAM = 3u;
static const uint X86_CALL_ARG_EVAL_SCALAR_IMM = 1u;
static const uint X86_CALL_ARG_EVAL_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_EVAL_PARAM_REG = 3u;
static const uint X86_INTRINSIC_CALLS_OK = 1u;
static const uint X86_INTRINSIC_TEXT_WRITE = 1u;
static const uint X86_INTRINSIC_TEXT_WRITE_CODE_ROWS = 5u;
static const uint X86_INTRINSIC_TEXT_WRITE_DATA_ROWS = 1u;
static const uint X86_INTRINSIC_IF_TEXT_WRITE_CODE_ROWS = 14u;
static const uint X86_INTRINSIC_IF_TEXT_WRITE_DATA_ROWS = 2u;
static const uint X86_INTRINSIC_IF_TEXT_WRITE_RELOCS = 2u;
static const uint X86_INTRINSIC_IF_THEN_TEXT_WRITE_CODE_ROWS = 8u;
static const uint X86_INTRINSIC_IF_THEN_TEXT_WRITE_DATA_ROWS = 1u;
static const uint X86_INTRINSIC_IF_THEN_TEXT_WRITE_RELOCS = 1u;
static const uint X86_CONST_VALUE_LITERAL = 1u;
static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDX = 2u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

bool valid_vreg(uint vreg, uint vreg_count)
{
    return vreg != INVALID && vreg < vreg_count;
}

bool is_imm_vreg(uint vreg, uint vreg_count)
{
    return valid_vreg(vreg, vreg_count) && x86_vreg_kind[vreg] == X86_VREG_IMM_I32;
}

bool valid_binary_op(uint op)
{
    return op >= X86_OP_ADD_I32 && op <= X86_OP_SHR_I32;
}

bool is_compare_op(uint op)
{
    uint base = op & ~X86_CMP_UNSIGNED_FLAG;
    return base == X86_CMP_LT || base == X86_CMP_GT || base == X86_CMP_LE ||
           base == X86_CMP_GE || base == X86_CMP_EQ || base == X86_CMP_NE;
}

bool valid_function_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_active_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint stmt_record_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

bool intrinsic_calls_ok()
{
    return x86_intrinsic_call_status[0u] == X86_INTRINSIC_CALLS_OK &&
           x86_intrinsic_call_status[1u] == 0u;
}

uint parent_node(uint node)
{
    uint p = valid_active_node(node) ? parent[node] : INVALID;
    return valid_active_node(p) ? p : INVALID;
}

uint owning_function_node(uint node)
{
    if (!valid_active_node(node))
        return INVALID;
    if (hir_kind[node] == HIR_FN)
        return node;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent_node(cur);
        if (p == INVALID || p == cur)
            return INVALID;
        if (hir_kind[p] == HIR_FN)
            return p;
        cur = p;
    }
    return INVALID;
}

bool has_if_ancestor_before_function(uint node)
{
    if (!valid_active_node(node))
        return false;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent_node(cur);
        if (p == INVALID || p == cur || hir_kind[p] == HIR_FN)
            return false;
        if (hir_kind[p] == HIR_IF_STMT)
            return true;
        cur = p;
    }
    return false;
}

bool node_has_ancestor(uint node, uint ancestor)
{
    if (!valid_active_node(node) || !valid_active_node(ancestor))
        return false;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (cur == ancestor)
            return true;
        uint p = parent_node(cur);
        if (p == INVALID || p == cur || hir_kind[p] == HIR_FN)
            return false;
        cur = p;
    }
    return false;
}

uint expr_record_slot(uint node, uint slot)
{
    return hir_expr_record[node * EXPR_RECORD_STRIDE + slot];
}

uint expr_form(uint node)
{
    return valid_function_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_function_node(node) ? expr_record_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_right(uint node)
{
    return valid_function_node(node) ? expr_record_slot(node, EXPR_RECORD_RIGHT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_function_node(node) ? expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_function_node(node))
            return INVALID;
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        node = expr_left(node);
    }
    return INVALID;
}

bool literal_or_unary_literal_expr(uint node)
{
    node = resolve_expr(node);
    if (!valid_function_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_INT || form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return true;
    if (form == HIR_EXPR_NAME)
    {
        uint token_i = expr_value_token(node);
        if (!valid_token(token_i))
            return false;
        uint decl_token = visible_decl[token_i];
        if (!valid_token(decl_token))
            return false;
        return x86_const_value_record[decl_token].x == X86_CONST_VALUE_LITERAL;
    }
    if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
    {
        uint operand = resolve_expr(expr_left(node));
        if (!valid_function_node(operand))
            return false;
        uint operand_form = expr_form(operand);
        bool operand_const = false;
        if (operand_form == HIR_EXPR_NAME)
        {
            uint token_i = expr_value_token(operand);
            uint decl_token = valid_token(token_i) ? visible_decl[token_i] : INVALID;
            operand_const = valid_token(decl_token) &&
                            x86_const_value_record[decl_token].x == X86_CONST_VALUE_LITERAL;
        }
        return operand_form == HIR_EXPR_INT ||
               operand_form == HIR_EXPR_TRUE ||
               operand_form == HIR_EXPR_FALSE ||
               operand_const;
    }
    return false;
}

bool param_reg_expr(uint node, uint fn_node, out uint arg_reg)
{
    arg_reg = INVALID;
    node = resolve_expr(node);
    if (!valid_function_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_value_token(node);
    if (!valid_token(name_token))
        return false;

    uint decl_token = visible_decl[name_token];
    if (!valid_token(decl_token))
        return false;

    uint4 record = x86_param_reg_record[decl_token];
    if (record.x != fn_node || record.z == INVALID)
        return false;

    arg_reg = record.z;
    return true;
}

bool param_expr(uint node, uint fn_node)
{
    uint arg_reg = INVALID;
    return param_reg_expr(node, fn_node, arg_reg);
}

bool scalar_return_expr(uint node, uint fn_node)
{
    return literal_or_unary_literal_expr(node) || param_expr(node, fn_node);
}

bool value_to_eax_inst_count(uint node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    node = resolve_expr(node);
    if (!valid_function_node(node))
        return false;

    if (literal_or_unary_literal_expr(node) || param_expr(node, fn_node))
    {
        inst_count = 1u;
        return true;
    }

    uint form = expr_form(node);
    if (form == HIR_EXPR_NEG)
    {
        uint arg_reg = INVALID;
        if (param_reg_expr(expr_left(node), fn_node, arg_reg))
        {
            inst_count = 2u;
            return true;
        }
    }

    uint call_count = 0u;
    uint target_fn = INVALID;
    if (call_value_to_eax_inst_count(node, fn_node, call_count, target_fn))
    {
        inst_count = call_count;
        return true;
    }

    return false;
}

uint binary_op_for_expr_form(uint form)
{
    if (form == HIR_EXPR_ADD)
        return X86_OP_ADD_I32;
    if (form == HIR_EXPR_SUB)
        return X86_OP_SUB_I32;
    if (form == HIR_EXPR_MUL)
        return X86_OP_MUL_I32;
    if (form == HIR_EXPR_AND)
        return X86_OP_AND_BOOL;
    if (form == HIR_EXPR_OR)
        return X86_OP_OR_BOOL;
    if (form == HIR_EXPR_MOD)
        return X86_OP_MOD_I32;
    return 0u;
}

bool binary_return_expr(uint node, uint fn_node)
{
    node = resolve_expr(node);
    if (!valid_function_node(node))
        return false;

    uint op = binary_op_for_expr_form(expr_form(node));
    if (op == 0u || op == X86_OP_MOD_I32)
        return false;

    uint right_reg = INVALID;
    bool right_literal = literal_or_unary_literal_expr(expr_right(node));
    bool right_param_esi = param_reg_expr(expr_right(node), fn_node, right_reg) &&
                           right_reg == X86_REG_ESI;
    return scalar_return_expr(expr_left(node), fn_node) &&
           (right_literal || right_param_esi);
}

bool compare_return_expr(uint node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    node = resolve_expr(node);
    if (!valid_function_node(node))
        return false;

    uint op = compare_op_for_expr_form(expr_form(node));
    if (op == 0u)
        return false;

    uint left_count = 0u;
    if (!value_to_eax_inst_count(expr_left(node), fn_node, left_count))
        return false;

    uint right_reg = INVALID;
    if (!literal_or_unary_literal_expr(expr_right(node)) &&
        !param_reg_expr(expr_right(node), fn_node, right_reg))
        return false;
    if (right_reg == X86_REG_EDI)
        return false;

    inst_count = left_count + 4u;
    return true;
}

bool not_return_expr(uint node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    node = resolve_expr(node);
    if (!valid_function_node(node) || expr_form(node) != HIR_EXPR_NOT)
        return false;

    uint value_count = 0u;
    if (!value_to_eax_inst_count(expr_left(node), fn_node, value_count))
        return false;

    inst_count = value_count + 4u;
    return true;
}

bool compare_bool_binary_return_expr(uint node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    node = resolve_expr(node);
    if (!valid_function_node(node))
        return false;

    uint op = binary_op_for_expr_form(expr_form(node));
    if (op != X86_OP_AND_BOOL && op != X86_OP_OR_BOOL)
        return false;

    uint left_count = 0u;
    uint right_count = 0u;
    if (!compare_return_expr(expr_left(node), fn_node, left_count) ||
        !compare_return_expr(expr_right(node), fn_node, right_count))
        return false;

    inst_count = (left_count - 1u) + (right_count - 1u) + 3u;
    return true;
}

bool expression_is_structural_operator(uint node)
{
    node = resolve_expr(node);
    if (!valid_function_node(node))
        return true;

    uint form = expr_form(node);
    return form == HIR_EXPR_NOT ||
           form == HIR_EXPR_EQ ||
           form == HIR_EXPR_NE ||
           form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE ||
           form == HIR_EXPR_NEG ||
           form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL ||
           form == HIR_EXPR_AND ||
           form == HIR_EXPR_OR ||
           form == HIR_EXPR_MOD;
}

bool owned_call_value_to_eax_inst_count(
    uint fn_node,
    out uint call_node,
    out uint inst_count,
    out uint target_fn)
{
    call_node = INVALID;
    inst_count = 0u;
    target_fn = INVALID;

    [loop]
    for (uint node = 0u; node < gParams.n_hir_nodes; node += 1u)
    {
        uint4 call_abi = x86_call_abi_record[call_abi_base_row(node)];
        if (call_abi.x != fn_node || !valid_function_node(call_abi.y))
            continue;

        uint call_count = 0u;
        uint candidate_target = INVALID;
        if (call_value_to_eax_inst_count(
                node,
                fn_node,
                call_count,
                candidate_target))
        {
            call_node = node;
            inst_count = call_count;
            target_fn = candidate_target;
            return true;
        }
    }

    return false;
}

uint compare_op_for_expr_form(uint form)
{
    if (form == HIR_EXPR_LT)
        return X86_CMP_LT;
    if (form == HIR_EXPR_GT)
        return X86_CMP_GT;
    if (form == HIR_EXPR_LE)
        return X86_CMP_LE;
    if (form == HIR_EXPR_GE)
        return X86_CMP_GE;
    if (form == HIR_EXPR_EQ)
        return X86_CMP_EQ;
    if (form == HIR_EXPR_NE)
        return X86_CMP_NE;
    return 0u;
}

bool condition_compare_inst_count(uint node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    node = resolve_expr(node);
    if (!valid_function_node(node))
        return false;

    uint form = expr_form(node);
    uint compare_op = compare_op_for_expr_form(form);
    if (compare_op != 0u)
    {
        uint left_count = 0u;
        if (!value_to_eax_inst_count(expr_left(node), fn_node, left_count))
            return false;

        uint right_reg = INVALID;
        if (!literal_or_unary_literal_expr(expr_right(node)) &&
            !param_reg_expr(expr_right(node), fn_node, right_reg))
            return false;
        if (right_reg == X86_REG_EDI)
            return false;
        inst_count = left_count + 1u;
        return true;
    }

    if (param_expr(node, fn_node) || literal_or_unary_literal_expr(node))
    {
        inst_count = 2u;
        return true;
    }

    return false;
}

bool callee_terminal_if_inst_count(uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    uint body_count = 0u;
    if (!terminal_if_value_inst_count(fn_node, fn_node, body_count))
        return false;

    inst_count = body_count + 1u;
    return true;
}

bool terminal_if_record_at(
    uint key_node,
    out uint cond_node,
    out uint then_expr,
    out uint else_expr)
{
    cond_node = INVALID;
    then_expr = INVALID;
    else_expr = INVALID;
    if (!valid_function_node(key_node))
        return false;

    uint4 record = x86_terminal_if_record[key_node];
    if (!valid_function_node(record.x) || !valid_function_node(record.y) ||
        !valid_function_node(record.z) || !valid_function_node(record.w))
        return false;

    cond_node = record.y;
    then_expr = record.z;
    else_expr = record.w;
    return true;
}

bool flat_terminal_if_value_inst_count(uint key_node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (!terminal_if_record_at(key_node, cond_node, then_expr, else_expr))
        return false;

    uint cond_count = 0u;
    uint then_count = 0u;
    uint else_count = 0u;
    if (!condition_compare_inst_count(cond_node, fn_node, cond_count) ||
        !value_to_eax_inst_count(then_expr, fn_node, then_count) ||
        !value_to_eax_inst_count(else_expr, fn_node, else_count))
        return false;

    inst_count = cond_count + then_count + else_count + 2u;
    return true;
}

bool terminal_if_value_inst_count(uint key_node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (!terminal_if_record_at(key_node, cond_node, then_expr, else_expr))
        return false;

    uint cond_count = 0u;
    uint then_count = 0u;
    uint else_count = 0u;
    if (!condition_compare_inst_count(cond_node, fn_node, cond_count) ||
        !value_to_eax_inst_count(then_expr, fn_node, then_count))
        return false;
    if (!value_to_eax_inst_count(else_expr, fn_node, else_count) &&
        !flat_terminal_if_value_inst_count(else_expr, fn_node, else_count))
        return false;

    inst_count = cond_count + then_count + else_count + 2u;
    return true;
}

bool callee_return_inst_count(uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    if (!valid_function_node(fn_node))
        return false;

    if (callee_terminal_if_inst_count(fn_node, inst_count))
        return true;

    uint4 record = x86_func_return_stmt_record[fn_node];
    if (record.x != fn_node || record.w != X86_FUNC_RETURN_STMT_TOP_LEVEL ||
        !valid_function_node(record.z))
        return false;

    uint ret_expr = record.z;
    uint value_count = 0u;
    if (value_to_eax_inst_count(ret_expr, fn_node, value_count))
    {
        inst_count = value_count + 1u;
        return true;
    }
    if (binary_return_expr(ret_expr, fn_node))
    {
        inst_count = 3u;
        return true;
    }
    if (compare_return_expr(ret_expr, fn_node, inst_count))
        return true;
    if (not_return_expr(ret_expr, fn_node, inst_count))
        return true;
    if (compare_bool_binary_return_expr(ret_expr, fn_node, inst_count))
        return true;
    uint call_node = INVALID;
    uint call_count = 0u;
    uint call_target_fn = INVALID;
    if (!expression_is_structural_operator(ret_expr) &&
        owned_call_value_to_eax_inst_count(
            fn_node,
            call_node,
            call_count,
            call_target_fn))
    {
        inst_count = call_count + 1u;
        return true;
    }
    return false;
}

uint call_arg_lookup_slot(uint call_node, uint ordinal)
{
    return call_node * X86_SYSV_MAX_INTEGER_ARGS + ordinal;
}

uint call_abi_base_row(uint call_node)
{
    return call_node * 2u;
}

uint sysv_integer_arg_reg(uint ordinal)
{
    if (ordinal == 0u) return X86_REG_EDI;
    if (ordinal == 1u) return X86_REG_ESI;
    if (ordinal == 2u) return X86_REG_EDX;
    return INVALID;
}

uint call_arg_count_for_call(uint call_node)
{
    if (!valid_function_node(call_node))
        return 0u;
    uint4 call_abi = x86_call_abi_record[call_abi_base_row(call_node)];
    return call_abi.z;
}

bool call_arg_lookup_record_at(
    uint call_node,
    uint ordinal,
    out uint arg_node,
    out uint value_kind,
    out uint4 eval)
{
    arg_node = INVALID;
    value_kind = 0u;
    eval = uint4(0u, 0u, 0u, 0u);
    uint4 lookup = x86_call_arg_lookup_record[call_arg_lookup_slot(call_node, ordinal)];
    if (lookup.x != call_node || lookup.y != ordinal || lookup.z == INVALID)
        return false;

    arg_node = lookup.z;
    value_kind = lookup.w;
    eval = x86_call_arg_eval_record[arg_node];
    return true;
}

bool param_call_arg_regs(
    uint call_node,
    uint ordinal,
    out uint source_reg,
    out uint target_reg)
{
    source_reg = INVALID;
    target_reg = sysv_integer_arg_reg(ordinal);
    uint arg_node = INVALID;
    uint value_kind = 0u;
    uint4 eval = uint4(0u, 0u, 0u, 0u);
    if (!call_arg_lookup_record_at(call_node, ordinal, arg_node, value_kind, eval))
        return false;
    if (target_reg == INVALID ||
        value_kind != X86_CALL_ARG_VALUE_PARAM ||
        eval.x != X86_CALL_ARG_EVAL_PARAM_REG)
        return false;

    source_reg = eval.y;
    return source_reg != INVALID;
}

bool call_arg_writes_target_reg(uint call_node, uint ordinal, out uint target_reg)
{
    target_reg = sysv_integer_arg_reg(ordinal);
    uint arg_node = INVALID;
    uint value_kind = 0u;
    uint4 eval = uint4(0u, 0u, 0u, 0u);
    if (target_reg == INVALID ||
        !call_arg_lookup_record_at(call_node, ordinal, arg_node, value_kind, eval))
        return false;

    if (value_kind == X86_CALL_ARG_VALUE_PARAM &&
        eval.x == X86_CALL_ARG_EVAL_PARAM_REG)
        return eval.y != target_reg;

    return value_kind == X86_CALL_ARG_VALUE_SCALAR ||
           value_kind == X86_CALL_ARG_VALUE_BINARY_IMM;
}

bool serial_param_move_safe(
    uint call_node,
    uint ordinal,
    uint arg_count,
    uint source_reg,
    uint target_reg)
{
    if (source_reg == target_reg)
        return true;

    [loop]
    for (uint prior = 0u; prior < X86_SYSV_MAX_INTEGER_ARGS; prior += 1u)
    {
        if (prior >= ordinal)
            break;
        uint prior_target = INVALID;
        if (call_arg_writes_target_reg(call_node, prior, prior_target) &&
            prior_target == source_reg)
            return false;
    }

    [loop]
    for (uint later = ordinal + 1u; later < X86_SYSV_MAX_INTEGER_ARGS; later += 1u)
    {
        if (later >= arg_count)
            break;
        uint later_source = INVALID;
        uint later_target = INVALID;
        if (param_call_arg_regs(call_node, later, later_source, later_target) &&
            later_source == target_reg)
            return false;
    }

    return true;
}

bool call_arg_inst_count(uint call_node, uint ordinal, out uint inst_count)
{
    inst_count = 0u;
    uint4 lookup = x86_call_arg_lookup_record[call_arg_lookup_slot(call_node, ordinal)];
    if (lookup.x != call_node || lookup.y != ordinal || lookup.z == INVALID)
        return false;

    uint arg_node = lookup.z;
    uint value_kind = lookup.w;
    uint4 eval = x86_call_arg_eval_record[arg_node];
    if (value_kind == X86_CALL_ARG_VALUE_SCALAR && eval.x == X86_CALL_ARG_EVAL_SCALAR_IMM)
    {
        if (ordinal > 2u)
            return false;
        inst_count = 1u;
        return true;
    }
    if (value_kind == X86_CALL_ARG_VALUE_BINARY_IMM && eval.x == X86_CALL_ARG_EVAL_BINARY_IMM)
    {
        if (ordinal > 1u || eval.w == X86_OP_MOD_I32 || eval.w == X86_OP_DIV_I32)
            return false;
        inst_count = 3u;
        return true;
    }
    if (value_kind == X86_CALL_ARG_VALUE_PARAM && eval.x == X86_CALL_ARG_EVAL_PARAM_REG)
    {
        uint target_reg = sysv_integer_arg_reg(ordinal);
        if (target_reg == INVALID)
            return false;
        if (eval.y == target_reg)
        {
            inst_count = 0u;
            return true;
        }
        if (!serial_param_move_safe(
                call_node,
                ordinal,
                call_arg_count_for_call(call_node),
                eval.y,
                target_reg))
            return false;
        inst_count = 1u;
        return true;
    }
    return false;
}

bool eval_binary_i32_value(uint op, uint left, uint right, out uint value)
{
    value = 0u;
    if (op == X86_OP_ADD_I32)
    {
        value = left + right;
        return true;
    }
    if (op == X86_OP_SUB_I32)
    {
        value = left - right;
        return true;
    }
    if (op == X86_OP_MUL_I32)
    {
        value = left * right;
        return true;
    }
    if (op == X86_OP_AND_BOOL || op == X86_OP_BIT_AND_I32)
    {
        value = op == X86_OP_AND_BOOL ? ((left != 0u && right != 0u) ? 1u : 0u) :
                                        (left & right);
        return true;
    }
    if (op == X86_OP_OR_BOOL || op == X86_OP_BIT_OR_I32)
    {
        value = op == X86_OP_OR_BOOL ? ((left != 0u || right != 0u) ? 1u : 0u) :
                                       (left | right);
        return true;
    }
    if (op == X86_OP_BIT_XOR_I32)
    {
        value = left ^ right;
        return true;
    }
    if (op == X86_OP_MOD_I32)
    {
        if (right == 0u)
            return false;
        value = left % right;
        return true;
    }
    if (op == X86_OP_DIV_I32)
    {
        if (right == 0u)
            return false;
        value = left / right;
        return true;
    }
    return false;
}

bool intrinsic_output_arg_value(uint arg_node, out uint value)
{
    value = 0u;
    if (!valid_function_node(arg_node))
        return false;

    uint4 eval = x86_call_arg_eval_record[arg_node];
    if (eval.x == X86_CALL_ARG_EVAL_SCALAR_IMM)
    {
        value = eval.y;
        return true;
    }
    if (eval.x == X86_CALL_ARG_EVAL_BINARY_IMM)
        return eval_binary_i32_value(eval.w, eval.y, eval.z, value);
    return false;
}

bool intrinsic_text_write_call_value(uint call_node, out uint value)
{
    value = 0u;
    if (!valid_active_node(call_node))
        return false;

    uint4 record = x86_intrinsic_call_record[call_node];
    if (record.y != call_node || record.w != X86_INTRINSIC_TEXT_WRITE)
        return false;
    uint arg_node = record.z;
    return intrinsic_output_arg_value(arg_node, value);
}

bool branch_text_write_call(
    uint block_node,
    uint fn_node,
    out uint call_node,
    out uint arg_node)
{
    call_node = INVALID;
    arg_node = INVALID;
    if (!valid_active_node(block_node) || !valid_active_node(fn_node))
        return false;

    uint count = 0u;
    [loop]
    for (uint node = 0u; node < gParams.n_hir_nodes; node += 1u)
    {
        uint4 record = x86_intrinsic_call_record[node];
        if (record.x != fn_node ||
            record.y != node ||
            record.w != X86_INTRINSIC_TEXT_WRITE ||
            !node_has_ancestor(node, block_node))
            continue;

        uint value = 0u;
        if (!intrinsic_text_write_call_value(node, value))
            return false;

        count += 1u;
        call_node = node;
        arg_node = record.z;
    }

    return count == 1u;
}

bool top_level_text_write_call(uint call_node, uint fn_node, out uint value)
{
    value = 0u;
    if (!valid_active_node(call_node))
        return false;

    uint4 record = x86_intrinsic_call_record[call_node];
    if (record.x != fn_node ||
        record.y != call_node ||
        record.w != X86_INTRINSIC_TEXT_WRITE ||
        has_if_ancestor_before_function(call_node))
        return false;

    return intrinsic_text_write_call_value(call_node, value);
}

uint owned_intrinsic_call_count(uint fn_node)
{
    uint count = 0u;
    [loop]
    for (uint node = 0u; node < gParams.n_hir_nodes; node += 1u)
    {
        uint4 record = x86_intrinsic_call_record[node];
        if (record.x == fn_node &&
            record.y == node &&
            record.w == X86_INTRINSIC_TEXT_WRITE)
            count += 1u;
    }
    return count;
}

bool intrinsic_output_plan_for_fn(
    uint fn_node,
    out uint code_count,
    out uint data_count,
    out uint reloc_count,
    out uint failure_node)
{
    code_count = 0u;
    data_count = 0u;
    reloc_count = 0u;
    failure_node = INVALID;
    if (!valid_active_node(fn_node) || !intrinsic_calls_ok())
        return false;

    uint accounted_calls = 0u;
    [loop]
    for (uint node = 0u; node < gParams.n_hir_nodes; node += 1u)
    {
        uint top_value = 0u;
        if (top_level_text_write_call(node, fn_node, top_value))
        {
            code_count += X86_INTRINSIC_TEXT_WRITE_CODE_ROWS;
            data_count += X86_INTRINSIC_TEXT_WRITE_DATA_ROWS;
            accounted_calls += 1u;
            continue;
        }

        if (hir_kind[node] != HIR_IF_STMT ||
            stmt_record_slot(node, 0u) != STMT_RECORD_KIND_IF ||
            owning_function_node(node) != fn_node ||
            has_if_ancestor_before_function(node))
            continue;

        uint cond_node = stmt_record_slot(node, 1u);
        uint then_block = stmt_record_slot(node, 2u);
        uint else_block = stmt_record_slot(node, 3u);
        uint then_call = INVALID;
        uint then_arg = INVALID;
        uint else_call = INVALID;
        uint else_arg = INVALID;
        if (!valid_active_node(cond_node) ||
            !branch_text_write_call(then_block, fn_node, then_call, then_arg))
        {
            failure_node = node;
            return false;
        }

        if (branch_text_write_call(else_block, fn_node, else_call, else_arg))
        {
            code_count += X86_INTRINSIC_IF_TEXT_WRITE_CODE_ROWS;
            data_count += X86_INTRINSIC_IF_TEXT_WRITE_DATA_ROWS;
            reloc_count += X86_INTRINSIC_IF_TEXT_WRITE_RELOCS;
            accounted_calls += 2u;
        }
        else
        {
            code_count += X86_INTRINSIC_IF_THEN_TEXT_WRITE_CODE_ROWS;
            data_count += X86_INTRINSIC_IF_THEN_TEXT_WRITE_DATA_ROWS;
            reloc_count += X86_INTRINSIC_IF_THEN_TEXT_WRITE_RELOCS;
            accounted_calls += 1u;
        }
    }

    uint owned_calls = owned_intrinsic_call_count(fn_node);
    if (accounted_calls != owned_calls)
    {
        failure_node = fn_node;
        return false;
    }
    return true;
}

bool caller_call_inst_count(uint call_node, uint arg_count, out uint inst_count)
{
    inst_count = 0u;
    if (!valid_function_node(call_node) || arg_count > X86_SYSV_MAX_INTEGER_ARGS)
        return false;

    [loop]
    for (uint ordinal = 0u; ordinal < X86_SYSV_MAX_INTEGER_ARGS; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;
        uint arg_inst_count = 0u;
        if (!call_arg_inst_count(call_node, ordinal, arg_inst_count))
            return false;
        inst_count += arg_inst_count;
    }
    inst_count += 4u;
    return true;
}

bool call_value_to_eax_inst_count(
    uint call_node,
    uint fn_node,
    out uint inst_count,
    out uint target_fn)
{
    inst_count = 0u;
    target_fn = INVALID;
    call_node = resolve_expr(call_node);
    if (!valid_function_node(call_node))
        return false;

    uint4 call_abi = x86_call_abi_record[call_abi_base_row(call_node)];
    target_fn = call_abi.y;
    uint arg_count = call_abi.z;
    if (call_abi.x != fn_node ||
        !valid_function_node(target_fn) ||
        arg_count > X86_SYSV_MAX_INTEGER_ARGS)
        return false;

    [loop]
    for (uint ordinal = 0u; ordinal < X86_SYSV_MAX_INTEGER_ARGS; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;
        uint arg_inst_count = 0u;
        if (!call_arg_inst_count(call_node, ordinal, arg_inst_count))
            return false;
        inst_count += arg_inst_count;
    }
    inst_count += 1u;
    return true;
}

bool direct_call_target_from_value(
    uint node,
    uint fn_node,
    out uint call_node,
    out uint target_fn)
{
    call_node = INVALID;
    target_fn = INVALID;
    node = resolve_expr(node);
    if (!valid_function_node(node))
        return false;

    uint call_count = 0u;
    if (!call_value_to_eax_inst_count(node, fn_node, call_count, target_fn))
        return false;

    call_node = node;
    return true;
}

bool nested_call_target_from_value(
    uint node,
    uint fn_node,
    out uint call_node,
    out uint target_fn)
{
    call_node = INVALID;
    target_fn = INVALID;
    node = resolve_expr(node);
    if (!valid_function_node(node))
        return false;

    if (direct_call_target_from_value(node, fn_node, call_node, target_fn))
        return true;

    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (terminal_if_record_at(node, cond_node, then_expr, else_expr))
    {
        if (direct_call_target_from_value(then_expr, fn_node, call_node, target_fn))
            return true;
        if (direct_call_target_from_value(else_expr, fn_node, call_node, target_fn))
            return true;
    }

    return false;
}

bool nested_call_target_from_callee(
    uint fn_node,
    out uint call_node,
    out uint target_fn)
{
    call_node = INVALID;
    target_fn = INVALID;
    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (terminal_if_record_at(fn_node, cond_node, then_expr, else_expr))
    {
        if (nested_call_target_from_value(then_expr, fn_node, call_node, target_fn))
            return true;
        if (nested_call_target_from_value(else_expr, fn_node, call_node, target_fn))
            return true;
    }

    uint4 record = x86_func_return_stmt_record[fn_node];
    if (record.x == fn_node && record.w == X86_FUNC_RETURN_STMT_TOP_LEVEL &&
        valid_function_node(record.z))
    {
        if (nested_call_target_from_value(record.z, fn_node, call_node, target_fn))
            return true;
        uint call_count = 0u;
        if (!expression_is_structural_operator(record.z) &&
            owned_call_value_to_eax_inst_count(
                fn_node,
                call_node,
                call_count,
                target_fn))
            return true;
    }

    return false;
}

void write_count_record(uint fn_node, uint inst_count, uint role, uint payload)
{
    if (valid_function_node(fn_node))
        x86_func_inst_count_record[fn_node] = uint4(fn_node, inst_count, role, payload);
}

void publish_counts(
    bool ok,
    uint error,
    uint detail,
    uint total_inst_count,
    uint owner_fn,
    uint nested_call_node,
    uint shape,
    uint return_vreg,
    uint vreg_count)
{
    x86_func_inst_count_status[0u] = ok ? X86_FUNC_INST_COUNT_OK : 0u;
    x86_func_inst_count_status[1u] = ok ? 0u : error;
    x86_func_inst_count_status[2u] = ok ? INVALID : detail;
    x86_func_inst_count_status[3u] = ok ? total_inst_count : 0u;
    x86_func_inst_count_status[4u] = ok ? owner_fn : INVALID;
    x86_func_inst_count_status[5u] = ok ? nested_call_node : INVALID;
    x86_func_inst_count_status[6u] = ok ? shape : 0u;
    x86_func_inst_count_status[7u] = ok ? return_vreg : INVALID;
    x86_func_inst_count_status[8u] = ok ? vreg_count : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (linear_dispatch_id(tid) != 0u)
        return;

    uint vreg_count = regalloc_status.count;
    uint return_vreg = x86_return_vreg[0u];
    bool valid_return = valid_vreg(return_vreg, vreg_count);
    uint return_kind = valid_return ? x86_vreg_kind[return_vreg] : 0u;
    uint return_op = valid_return ? x86_vreg_op[return_vreg] : 0u;
    uint4 return_args = valid_return ?
                        x86_vreg_args[return_vreg] :
                        uint4(INVALID, INVALID, INVALID, INVALID);
    uint arg0 = return_args.x;
    uint arg1 = return_args.y;
    uint arg2 = return_args.z;
    uint arg3 = return_args.w;
    uint owner_fn = x86_func_meta.main_node;
    uint output_code_count = 0u;
    uint output_data_count = 0u;
    uint output_reloc_count = 0u;
    uint output_failure_detail = INVALID;
    bool output_ok = intrinsic_output_plan_for_fn(
        owner_fn,
        output_code_count,
        output_data_count,
        output_reloc_count,
        output_failure_detail);
    uint output_inst_count = output_code_count + output_data_count;

    bool literal_ok = return_kind == X86_VREG_IMM_I32;
    bool binary_ok = return_kind == X86_VREG_BINARY_I32 &&
                     is_imm_vreg(arg0, vreg_count) && is_imm_vreg(arg1, vreg_count) &&
                     valid_binary_op(return_op);
    bool compare_ok = return_kind == X86_VREG_COMPARE_I32 &&
                      is_imm_vreg(arg0, vreg_count) && is_imm_vreg(arg1, vreg_count) &&
                      is_compare_op(return_op);
    bool branch_ok = return_kind == X86_VREG_BRANCH_I32 &&
                     is_imm_vreg(arg0, vreg_count) && is_imm_vreg(arg1, vreg_count) &&
                     is_imm_vreg(arg2, vreg_count) && is_imm_vreg(arg3, vreg_count) &&
                     is_compare_op(return_op);
    bool call_ok = false;
    uint call_node = return_kind == X86_VREG_CALL_I32 ? x86_vreg_value[return_vreg] : INVALID;
    uint target_fn = INVALID;
    uint call_arg_count = 0u;
    uint caller_inst_count = 0u;
    uint callee_inst_count = 0u;
    uint nested_call_node = INVALID;
    uint nested_target_fn = INVALID;
    uint nested_callee_inst_count = 0u;
    bool nested_call_present = false;
    bool nested_call_ok = true;
    uint call_failure_detail = call_node;
    if (return_kind == X86_VREG_CALL_I32 && valid_function_node(call_node))
    {
        uint4 call_abi = x86_call_abi_record[call_abi_base_row(call_node)];
        target_fn = call_abi.y;
        call_arg_count = call_abi.z;
        bool owner_ok = call_abi.x == owner_fn;
        bool target_ok = valid_function_node(target_fn);
        bool caller_ok = target_ok &&
                         caller_call_inst_count(call_node, call_arg_count, caller_inst_count);
        bool callee_ok = target_ok &&
                         callee_return_inst_count(target_fn, callee_inst_count);
        nested_call_present = target_ok &&
                              nested_call_target_from_callee(
                                  target_fn,
                                  nested_call_node,
                                  nested_target_fn);
        nested_call_ok = !nested_call_present ||
                         (valid_function_node(nested_target_fn) &&
                          nested_target_fn != owner_fn &&
                          nested_target_fn != target_fn &&
                          callee_return_inst_count(
                              nested_target_fn,
                              nested_callee_inst_count));
        call_ok = owner_ok && target_ok && caller_ok && callee_ok && nested_call_ok;
        call_failure_detail = target_ok && !callee_ok ? target_fn :
                              (nested_call_present && !nested_call_ok ?
                               nested_target_fn :
                               call_node);
    }

    uint shape = literal_ok ? X86_SELECT_SHAPE_LITERAL :
                 (binary_ok ? X86_SELECT_SHAPE_BINARY :
                  (compare_ok ? X86_SELECT_SHAPE_COMPARE :
                   (branch_ok ? X86_SELECT_SHAPE_BRANCH :
                    (call_ok ? X86_SELECT_SHAPE_CALL : 0u))));
    uint binary_inst_count = (return_op == X86_OP_MOD_I32 || return_op == X86_OP_DIV_I32) ? 7u : 5u;
    uint total_inst_count = branch_ok ? 8u :
                            (compare_ok ? 6u :
                             (binary_ok ? 5u :
                              (literal_ok ? 3u : 0u)));
    if (binary_ok)
        total_inst_count = binary_inst_count;
    if (call_ok)
        total_inst_count = caller_inst_count + callee_inst_count + nested_callee_inst_count;
    if (shape != 0u)
        total_inst_count += output_inst_count;
    bool ok = regalloc_status.state == X86_REGALLOC_OK &&
              x86_func_meta.main_count == 1u &&
              output_ok &&
              valid_function_node(owner_fn) &&
              valid_return &&
              shape != 0u &&
              total_inst_count != 0u &&
              total_inst_count <= MAX_X86_INSTS;

    if (ok && call_ok)
    {
        write_count_record(
            owner_fn,
            caller_inst_count + output_inst_count,
            X86_FUNC_LAYOUT_CALLER,
            call_node);
        write_count_record(target_fn, callee_inst_count, X86_FUNC_LAYOUT_CALLEE, call_node);
        if (nested_call_present)
            write_count_record(
                nested_target_fn,
                nested_callee_inst_count,
                X86_FUNC_LAYOUT_CALLEE,
                call_node);
    }
    else if (ok)
    {
        write_count_record(owner_fn, total_inst_count, X86_FUNC_LAYOUT_CALLER, INVALID);
    }

    publish_counts(
        ok,
        !output_ok ? X86_ERR_UNSUPPORTED_RETURN :
        (regalloc_status.error == 0u ? X86_ERR_UNSUPPORTED_RETURN : regalloc_status.error),
        !output_ok ? output_failure_detail :
        (regalloc_status.detail != INVALID ? regalloc_status.detail :
         (return_kind == X86_VREG_CALL_I32 ? call_failure_detail : return_vreg)),
        total_inst_count,
        owner_fn,
        nested_call_present ? nested_call_node : INVALID,
        shape,
        return_vreg,
        vreg_count);
}
