import utils;

// Direct x86 value lowering over GPU-owned semantic/backend records.
//
// This pass consumes function metadata, per-function return statement rows,
// declaration-token keyed local literal rows, terminal if/else rows, and call
// argument vreg rows. It does not rediscover let/return/if structure by walking
// HIR statements.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

struct ConstValueStatus
{
    uint state;
    uint error;
    uint detail;
    uint count;
};

struct LocalLiteralStatus
{
    uint state;
    uint error;
    uint detail;
    uint count;
};

struct FuncReturnStmtStatus
{
    uint state;
    uint error;
    uint detail;
    uint count;
};

struct TerminalIfStatus
{
    uint state;
    uint error;
    uint detail;
    uint count;
};

struct ReturnCallStatus
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
ConstantBuffer<ConstValueStatus> x86_const_value_status;
ConstantBuffer<LocalLiteralStatus> x86_local_literal_status;
ConstantBuffer<FuncReturnStmtStatus> x86_func_return_stmt_status;
ConstantBuffer<TerminalIfStatus> x86_terminal_if_status;
ConstantBuffer<ReturnCallStatus> x86_return_call_status;
ConstantBuffer<FuncMeta> x86_func_meta;

StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint4> x86_const_value_record;
StructuredBuffer<uint4> x86_local_literal_record;
StructuredBuffer<uint4> x86_func_return_stmt_record;
StructuredBuffer<uint4> x86_terminal_if_record;
StructuredBuffer<uint4> x86_return_call_record;

RWStructuredBuffer<uint> x86_vreg_kind;
RWStructuredBuffer<uint> x86_vreg_value;
RWStructuredBuffer<uint4> x86_vreg_args;
RWStructuredBuffer<uint> x86_vreg_op;
RWStructuredBuffer<uint> x86_expr_vreg;
RWStructuredBuffer<uint> x86_return_vreg;
RWStructuredBuffer<uint> lower_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint MAX_X86_VREGS = 8u;
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

static const uint X86_CMP_LT = 1u;
static const uint X86_CMP_GT = 2u;
static const uint X86_CMP_LE = 3u;
static const uint X86_CMP_GE = 4u;
static const uint X86_CMP_EQ = 5u;
static const uint X86_CMP_NE = 6u;

static const uint X86_LOWER_OK = 1u;
static const uint X86_CONST_VALUES_OK = 1u;
static const uint X86_CONST_VALUE_LITERAL = 1u;
static const uint X86_LOCAL_LITERALS_OK = 1u;
static const uint X86_LOCAL_LITERAL_TOP_LEVEL = 1u;
static const uint X86_FUNC_RETURN_STMTS_OK = 1u;
static const uint X86_FUNC_RETURN_STMT_TOP_LEVEL = 1u;
static const uint X86_TERMINAL_IFS_OK = 1u;
static const uint X86_RETURN_CALLS_OK = 1u;
static const uint X86_ERR_MISSING_MAIN = 2u;
static const uint X86_ERR_UNSUPPORTED_RETURN = 3u;

static const uint X86_VREG_IMM_I32 = 1u;
static const uint X86_VREG_BINARY_I32 = 2u;
static const uint X86_VREG_BRANCH_I32 = 3u;
static const uint X86_VREG_COMPARE_I32 = 4u;
static const uint X86_VREG_CALL_I32 = 5u;

static const uint X86_REG_EDI = 7u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDX = 2u;
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
    return gParams.n_hir_nodes;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint i)
{
    return i != INVALID && i < gParams.n_tokens;
}

uint main_fn_node()
{
    return x86_func_meta.main_count == 1u ? x86_func_meta.main_node : INVALID;
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

bool const_values_ok()
{
    return x86_const_value_status.state == X86_CONST_VALUES_OK &&
           x86_const_value_status.error == 0u;
}

bool local_literals_ok()
{
    return x86_local_literal_status.state == X86_LOCAL_LITERALS_OK &&
           x86_local_literal_status.error == 0u;
}

bool return_stmts_ok()
{
    return x86_func_return_stmt_status.state == X86_FUNC_RETURN_STMTS_OK &&
           x86_func_return_stmt_status.error == 0u;
}

bool terminal_ifs_ok()
{
    return x86_terminal_if_status.state == X86_TERMINAL_IFS_OK &&
           x86_terminal_if_status.error == 0u;
}

bool return_calls_ok()
{
    return x86_return_call_status.state == X86_RETURN_CALLS_OK &&
           x86_return_call_status.error == 0u;
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

bool local_atom_value(uint token_i, uint fn_node, out uint value)
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

bool expr_leaf_value(uint value_node, uint fn_node, uint before_node, out uint value)
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

bool expr_scalar_value(uint value_node, uint fn_node, uint before_node, out uint value)
{
    value = 0u;
    value_node = resolve_expr(value_node);
    if (expr_leaf_value(value_node, fn_node, before_node, value))
        return true;
    if (!valid_node(value_node))
        return false;

    uint form = expr_form(value_node);
    if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
    {
        uint operand = 0u;
        if (!expr_leaf_value(expr_left(value_node), fn_node, before_node, operand))
            return false;
        value = form == HIR_EXPR_NEG ? 0u - operand : (operand == 0u ? 1u : 0u);
        return true;
    }
    return false;
}

void write_vreg(uint vreg, uint kind, uint value, uint4 args, uint op)
{
    x86_vreg_kind[vreg] = kind;
    x86_vreg_value[vreg] = value;
    x86_vreg_args[vreg] = args;
    x86_vreg_op[vreg] = op;
}

bool allocate_expr_vreg(
    uint expr_node,
    uint kind,
    uint value,
    uint4 args,
    uint op,
    inout uint next_vreg,
    out uint vreg)
{
    vreg = INVALID;
    expr_node = resolve_expr(expr_node);
    if (!valid_node(expr_node))
        return false;

    uint existing = x86_expr_vreg[expr_node];
    if (existing != INVALID)
    {
        if (existing >= next_vreg || existing >= MAX_X86_VREGS)
            return false;
        vreg = existing;
        return true;
    }

    if (next_vreg >= MAX_X86_VREGS)
        return false;

    vreg = next_vreg;
    next_vreg += 1u;
    write_vreg(vreg, kind, value, args, op);
    x86_expr_vreg[expr_node] = vreg;
    return true;
}

bool allocate_unmapped_vreg(
    uint kind,
    uint value,
    uint4 args,
    uint op,
    inout uint next_vreg,
    out uint vreg)
{
    vreg = INVALID;
    if (next_vreg >= MAX_X86_VREGS)
        return false;

    vreg = next_vreg;
    next_vreg += 1u;
    write_vreg(vreg, kind, value, args, op);
    return true;
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
    if (form == HIR_EXPR_DIV)
        return X86_OP_DIV_I32;
    if (form == HIR_EXPR_BIT_AND)
        return X86_OP_BIT_AND_I32;
    if (form == HIR_EXPR_BIT_OR)
        return X86_OP_BIT_OR_I32;
    if (form == HIR_EXPR_BIT_XOR)
        return X86_OP_BIT_XOR_I32;
    if (form == HIR_EXPR_SHL)
        return X86_OP_SHL_I32;
    if (form == HIR_EXPR_SHR)
        return X86_OP_SHR_I32;
    return 0u;
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

bool materialize_scalar_expr_vreg(
    uint expr_node,
    uint fn_node,
    uint before_node,
    inout uint next_vreg,
    out uint vreg)
{
    vreg = INVALID;
    expr_node = resolve_expr(expr_node);
    if (!valid_node(expr_node))
        return false;

    uint existing = x86_expr_vreg[expr_node];
    if (existing != INVALID)
    {
        if (existing >= next_vreg || existing >= MAX_X86_VREGS ||
            x86_vreg_kind[existing] != X86_VREG_IMM_I32)
            return false;
        vreg = existing;
        return true;
    }

    uint value = 0u;
    if (!expr_scalar_value(expr_node, fn_node, before_node, value))
        return false;

    return allocate_expr_vreg(
        expr_node,
        X86_VREG_IMM_I32,
        value,
        uint4(INVALID, INVALID, INVALID, INVALID),
        0u,
        next_vreg,
        vreg);
}

bool materialize_binary_expr_vreg(
    uint expr_node,
    uint kind,
    uint op,
    uint fn_node,
    uint before_node,
    inout uint next_vreg,
    out uint vreg)
{
    vreg = INVALID;
    uint left_vreg = INVALID;
    uint right_vreg = INVALID;
    if (!materialize_scalar_expr_vreg(
            expr_left(expr_node),
            fn_node,
            before_node,
            next_vreg,
            left_vreg) ||
        !materialize_scalar_expr_vreg(
            expr_right(expr_node),
            fn_node,
            before_node,
            next_vreg,
            right_vreg))
        return false;

    return allocate_expr_vreg(
        expr_node,
        kind,
        0u,
        uint4(left_vreg, right_vreg, INVALID, INVALID),
        op,
        next_vreg,
        vreg);
}

bool materialize_expr_vreg(
    uint expr_node,
    uint fn_node,
    uint before_node,
    inout uint next_vreg,
    out uint vreg)
{
    vreg = INVALID;
    expr_node = resolve_expr(expr_node);
    if (!valid_node(expr_node))
        return false;

    uint existing = x86_expr_vreg[expr_node];
    if (existing != INVALID)
    {
        if (existing >= next_vreg || existing >= MAX_X86_VREGS)
            return false;
        vreg = existing;
        return true;
    }

    uint form = expr_form(expr_node);
    uint binary_op = binary_op_for_expr_form(form);
    if (binary_op != 0u)
        return materialize_binary_expr_vreg(
            expr_node,
            X86_VREG_BINARY_I32,
            binary_op,
            fn_node,
            before_node,
            next_vreg,
            vreg);

    uint compare_op = compare_op_for_expr_form(form);
    if (compare_op != 0u)
        return materialize_binary_expr_vreg(
            expr_node,
            X86_VREG_COMPARE_I32,
            compare_op,
            fn_node,
            before_node,
            next_vreg,
            vreg);

    return materialize_scalar_expr_vreg(
        expr_node,
        fn_node,
        before_node,
        next_vreg,
        vreg);
}

bool top_return_for_main(uint main_node, out uint ret_node, out uint ret_expr)
{
    ret_node = INVALID;
    ret_expr = INVALID;
    if (!return_stmts_ok() || !valid_node(main_node))
        return false;

    uint4 record = x86_func_return_stmt_record[main_node];
    if (record.x != main_node || record.w != X86_FUNC_RETURN_STMT_TOP_LEVEL ||
        !valid_node(record.y) || !valid_node(record.z))
        return false;

    ret_node = record.y;
    ret_expr = record.z;
    return true;
}

bool lower_return_value(uint ret_expr, uint before_node, uint main_node)
{
    uint next_vreg = 0u;
    uint ret_vreg = INVALID;
    if (materialize_expr_vreg(ret_expr, main_node, before_node, next_vreg, ret_vreg))
    {
        x86_return_vreg[0u] = ret_vreg;
        lower_status[3u] = next_vreg;
        lower_status[0u] = X86_LOWER_OK;
        return true;
    }

    return false;
}

bool lower_return_call(uint ret_node, uint main_node)
{
    if (!return_calls_ok() || !valid_node(ret_node) || !valid_node(main_node))
        return false;

    uint4 return_call = x86_return_call_record[ret_node];
    uint call_node = return_call.y;
    if (return_call.x != ret_node || return_call.z != main_node ||
        return_call.w != X86_FUNC_RETURN_STMT_TOP_LEVEL || !valid_node(call_node))
        return false;

    write_vreg(
        0u,
        X86_VREG_CALL_I32,
        call_node,
        uint4(INVALID, INVALID, INVALID, INVALID),
        0u);
    x86_return_vreg[0u] = 0u;
    lower_status[3u] = 1u;
    lower_status[0u] = X86_LOWER_OK;
    return true;
}

bool lower_terminal_if(uint main_node)
{
    if (!terminal_ifs_ok() || !valid_node(main_node))
        return false;

    uint4 record = x86_terminal_if_record[main_node];
    uint if_node = record.x;
    uint cond_node = record.y;
    uint then_expr = record.z;
    uint else_expr = record.w;
    if (!valid_node(if_node) || !valid_node(cond_node) ||
        !valid_node(then_expr) || !valid_node(else_expr))
        return false;

    uint next_vreg = 0u;
    uint cond_vreg = INVALID;
    if (!materialize_expr_vreg(cond_node, main_node, if_node, next_vreg, cond_vreg))
        return false;
    if (x86_vreg_kind[cond_vreg] != X86_VREG_COMPARE_I32)
        return false;

    uint then_vreg = INVALID;
    uint else_vreg = INVALID;
    if (!materialize_expr_vreg(then_expr, main_node, if_node, next_vreg, then_vreg) ||
        !materialize_expr_vreg(else_expr, main_node, if_node, next_vreg, else_vreg))
        return false;
    if (x86_vreg_kind[then_vreg] != X86_VREG_IMM_I32 ||
        x86_vreg_kind[else_vreg] != X86_VREG_IMM_I32)
        return false;

    uint4 cond_args = x86_vreg_args[cond_vreg];
    uint branch_vreg = INVALID;
    if (!allocate_unmapped_vreg(
            X86_VREG_BRANCH_I32,
            0u,
            uint4(cond_args.x, cond_args.y, then_vreg, else_vreg),
            x86_vreg_op[cond_vreg],
            next_vreg,
            branch_vreg))
        return false;

    x86_return_vreg[0u] = branch_vreg;
    lower_status[3u] = next_vreg;
    lower_status[0u] = X86_LOWER_OK;
    return true;
}

void mark_unsupported_return(uint detail)
{
    lower_status[1u] = X86_ERR_UNSUPPORTED_RETURN;
    uint old_detail = 0u;
    InterlockedMin(lower_status[2u], detail, old_detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (linear_dispatch_id(tid) != 0u)
        return;

    uint main_node = main_fn_node();
    if (!valid_node(main_node))
    {
        lower_status[1u] = X86_ERR_MISSING_MAIN;
        lower_status[2u] = x86_func_meta.func_count;
        return;
    }

    uint ret_node = INVALID;
    uint ret_expr = INVALID;
    if (top_return_for_main(main_node, ret_node, ret_expr))
    {
        if (!lower_return_value(ret_expr, ret_node, main_node) &&
            !lower_return_call(ret_node, main_node))
            mark_unsupported_return(ret_node);
        return;
    }

    if (lower_terminal_if(main_node))
        return;

    mark_unsupported_return(main_node);
}
