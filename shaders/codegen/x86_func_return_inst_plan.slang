// x86_64 callee return instruction planning over HIR/backend records.
//
// This pass materializes instruction rows for non-entry functions selected by
// x86_func_inst_counts. It consumes attributed HIR expression records,
// resolver-backed visible declarations, parameter ABI records, and function
// layout records; it does not inspect source text, token spelling, helper
// names, or whole function-body source patterns.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint4> x86_const_value_record;
StructuredBuffer<uint4> x86_call_abi_record;
StructuredBuffer<uint4> x86_call_arg_lookup_record;
StructuredBuffer<uint4> x86_call_arg_eval_record;
StructuredBuffer<uint4> x86_func_return_stmt_record;
StructuredBuffer<uint4> x86_terminal_if_record;
StructuredBuffer<uint4> x86_param_reg_record;
StructuredBuffer<uint4> x86_func_layout_record;
StructuredBuffer<uint> x86_func_layout_status;

RWStructuredBuffer<uint> x86_planned_inst_kind;
RWStructuredBuffer<uint> x86_planned_inst_arg0;
RWStructuredBuffer<uint> x86_func_return_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FUNC_LAYOUT_OK = 1u;
static const uint X86_FUNC_RETURN_INST_OK = 1u;
static const uint X86_ERR_UNSUPPORTED_RETURN = 3u;

static const uint X86_FUNC_RETURN_STMT_TOP_LEVEL = 1u;
static const uint X86_FUNC_LAYOUT_CALLEE = 2u;

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

static const uint X86_OP_ADD_I32 = 1u;
static const uint X86_OP_SUB_I32 = 2u;
static const uint X86_OP_MUL_I32 = 3u;
static const uint X86_OP_AND_BOOL = 4u;
static const uint X86_OP_OR_BOOL = 5u;
static const uint X86_OP_MOD_I32 = 6u;
static const uint X86_CMP_LT = 1u;
static const uint X86_CMP_GT = 2u;
static const uint X86_CMP_LE = 3u;
static const uint X86_CMP_GE = 4u;
static const uint X86_CMP_EQ = 5u;
static const uint X86_CMP_NE = 6u;
static const uint X86_CMP_UNSIGNED_FLAG = 0x80u;
static const uint TY_UINT = 4u;
static const uint TY_CHAR = 6u;

static const uint X86_REG_EDI = 7u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDX = 2u;
static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;

static const uint X86_CALL_ARG_VALUE_SCALAR = 1u;
static const uint X86_CALL_ARG_VALUE_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_VALUE_PARAM = 3u;
static const uint X86_CALL_ARG_EVAL_SCALAR_IMM = 1u;
static const uint X86_CALL_ARG_EVAL_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_EVAL_PARAM_REG = 3u;
static const uint X86_CONST_VALUE_LITERAL = 1u;

static const uint X86_INST_MOV_EAX_IMM32 = 1u;
static const uint X86_INST_MOV_EDI_IMM32 = 2u;
static const uint X86_INST_ADD_EAX_IMM32 = 4u;
static const uint X86_INST_SUB_EAX_IMM32 = 5u;
static const uint X86_INST_IMUL_EAX_EAX_IMM32 = 6u;
static const uint X86_INST_MOV_EDI_EAX = 7u;
static const uint X86_INST_CMP_EAX_IMM32 = 8u;
static const uint X86_INST_JCC_FALSE_REL32 = 9u;
static const uint X86_INST_JMP_REL32 = 10u;
static const uint X86_INST_SETCC_AL = 11u;
static const uint X86_INST_AND_EAX_IMM32 = 13u;
static const uint X86_INST_OR_EAX_IMM32 = 14u;
static const uint X86_INST_CALL_REL32 = 15u;
static const uint X86_INST_RET = 16u;
static const uint X86_INST_MOV_EAX_EDI = 17u;
static const uint X86_INST_MOV_ESI_IMM32 = 18u;
static const uint X86_INST_ADD_EAX_ESI = 19u;
static const uint X86_INST_SUB_EAX_ESI = 20u;
static const uint X86_INST_IMUL_EAX_ESI = 21u;
static const uint X86_INST_AND_EAX_ESI = 22u;
static const uint X86_INST_OR_EAX_ESI = 23u;
static const uint X86_INST_MOV_ESI_EAX = 24u;
static const uint X86_INST_MOV_EAX_ESI = 25u;
static const uint X86_INST_MOV_EAX_EDX = 26u;
static const uint X86_INST_MOV_EDX_IMM32 = 27u;
static const uint X86_INST_CMP_EAX_ESI = 28u;
static const uint X86_INST_NEG_EAX = 29u;
static const uint X86_INST_MOVZX_EAX_AL = 30u;
static const uint X86_INST_CMP_EAX_EDX = 31u;
static const uint X86_INST_MOV_EDI_EDX = 35u;
static const uint X86_INST_MOV_ECX_EAX = 36u;
static const uint X86_INST_AND_EAX_ECX = 37u;
static const uint X86_INST_OR_EAX_ECX = 38u;
static const uint X86_INST_MOV_ESI_EDI = 43u;
static const uint X86_INST_MOV_EDX_EDI = 44u;
static const uint X86_INST_MOV_EDI_ESI = 45u;
static const uint X86_INST_MOV_EDX_ESI = 46u;
static const uint X86_INST_MOV_ESI_EDX = 47u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

void write_inst(uint inst_i, uint kind, uint arg0)
{
    x86_planned_inst_kind[inst_i] = kind;
    x86_planned_inst_arg0[inst_i] = arg0;
}

bool layout_ok()
{
    return x86_func_layout_status[0u] == X86_FUNC_LAYOUT_OK &&
           x86_func_layout_status[1u] == 0u;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
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

bool literal_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_INT)
    {
        value = hir_expr_int_value[node];
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_NAME)
    {
        uint token_i = expr_value_token(node);
        if (!valid_token(token_i))
            return false;
        uint decl_token = visible_decl[token_i];
        if (!valid_token(decl_token))
            return false;
        uint4 record = x86_const_value_record[decl_token];
        if (record.x != X86_CONST_VALUE_LITERAL)
            return false;
        value = record.y;
        return true;
    }
    return false;
}

bool unary_literal_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (literal_value(node, value))
        return true;
    if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
    {
        uint operand = 0u;
        if (!literal_value(expr_left(node), operand))
            return false;
        value = form == HIR_EXPR_NEG ? 0u - operand : (operand == 0u ? 1u : 0u);
        return true;
    }
    return false;
}

bool param_reg(uint node, uint fn_node, out uint arg_reg)
{
    arg_reg = INVALID;
    node = resolve_expr(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
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

bool param_type(uint node, uint fn_node, out uint ty)
{
    ty = 0u;
    node = resolve_expr(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
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

    ty = record.w;
    return true;
}

uint mov_param_to_eax_inst(uint arg_reg)
{
    if (arg_reg == X86_REG_EDI)
        return X86_INST_MOV_EAX_EDI;
    if (arg_reg == X86_REG_ESI)
        return X86_INST_MOV_EAX_ESI;
    if (arg_reg == X86_REG_EDX)
        return X86_INST_MOV_EAX_EDX;
    return 0u;
}

uint sysv_integer_arg_reg(uint ordinal)
{
    if (ordinal == 0u) return X86_REG_EDI;
    if (ordinal == 1u) return X86_REG_ESI;
    if (ordinal == 2u) return X86_REG_EDX;
    return INVALID;
}

uint call_abi_base_row(uint call_node)
{
    return call_node * 2u;
}

uint call_arg_lookup_slot(uint call_node, uint ordinal)
{
    return call_node * X86_SYSV_MAX_INTEGER_ARGS + ordinal;
}

uint mov_arg_imm_inst_kind(uint ordinal)
{
    if (ordinal == 0u)
        return X86_INST_MOV_EDI_IMM32;
    if (ordinal == 1u)
        return X86_INST_MOV_ESI_IMM32;
    if (ordinal == 2u)
        return X86_INST_MOV_EDX_IMM32;
    return 0u;
}

uint mov_arg_from_eax_inst_kind(uint ordinal)
{
    if (ordinal == 0u)
        return X86_INST_MOV_EDI_EAX;
    if (ordinal == 1u)
        return X86_INST_MOV_ESI_EAX;
    return 0u;
}

uint mov_param_to_arg_inst_kind(uint source_reg, uint target_reg)
{
    if (source_reg == X86_REG_EDI && target_reg == X86_REG_ESI)
        return X86_INST_MOV_ESI_EDI;
    if (source_reg == X86_REG_EDI && target_reg == X86_REG_EDX)
        return X86_INST_MOV_EDX_EDI;
    if (source_reg == X86_REG_ESI && target_reg == X86_REG_EDI)
        return X86_INST_MOV_EDI_ESI;
    if (source_reg == X86_REG_ESI && target_reg == X86_REG_EDX)
        return X86_INST_MOV_EDX_ESI;
    if (source_reg == X86_REG_EDX && target_reg == X86_REG_EDI)
        return X86_INST_MOV_EDI_EDX;
    if (source_reg == X86_REG_EDX && target_reg == X86_REG_ESI)
        return X86_INST_MOV_ESI_EDX;
    return 0u;
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

bool write_scalar_to_eax(uint inst_i, uint expr_node, uint fn_node)
{
    uint value = 0u;
    if (unary_literal_value(expr_node, value))
    {
        write_inst(inst_i, X86_INST_MOV_EAX_IMM32, value);
        return true;
    }

    uint arg_reg = INVALID;
    if (param_reg(expr_node, fn_node, arg_reg))
    {
        uint inst_kind = mov_param_to_eax_inst(arg_reg);
        if (inst_kind == 0u)
            return false;
        write_inst(inst_i, inst_kind, 0u);
        return true;
    }

    return false;
}

bool value_to_eax_inst_count(uint node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    uint value = 0u;
    if (unary_literal_value(node, value))
    {
        inst_count = 1u;
        return true;
    }

    uint arg_reg = INVALID;
    if (param_reg(node, fn_node, arg_reg))
    {
        inst_count = 1u;
        return true;
    }

    if (expr_form(node) == HIR_EXPR_NEG &&
        param_reg(expr_left(node), fn_node, arg_reg))
    {
        inst_count = 2u;
        return true;
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

bool call_arg_inst_count(uint call_node, uint ordinal, out uint inst_count)
{
    inst_count = 0u;
    uint4 lookup = x86_call_arg_lookup_record[call_arg_lookup_slot(call_node, ordinal)];
    if (lookup.x != call_node || lookup.y != ordinal || lookup.z == INVALID)
        return false;

    uint value_kind = lookup.w;
    uint4 eval = x86_call_arg_eval_record[lookup.z];
    if (value_kind == X86_CALL_ARG_VALUE_SCALAR && eval.x == X86_CALL_ARG_EVAL_SCALAR_IMM)
    {
        if (mov_arg_imm_inst_kind(ordinal) == 0u)
            return false;
        inst_count = 1u;
        return true;
    }
    if (value_kind == X86_CALL_ARG_VALUE_BINARY_IMM && eval.x == X86_CALL_ARG_EVAL_BINARY_IMM)
    {
        if (mov_arg_from_eax_inst_kind(ordinal) == 0u || eval.w == X86_OP_MOD_I32)
            return false;
        inst_count = 3u;
        return true;
    }
    if (value_kind == X86_CALL_ARG_VALUE_PARAM && eval.x == X86_CALL_ARG_EVAL_PARAM_REG)
    {
        uint target_reg = sysv_integer_arg_reg(ordinal);
        if (target_reg == INVALID)
            return false;
        if (eval.y != target_reg &&
            !serial_param_move_safe(
                call_node,
                ordinal,
                x86_call_abi_record[call_abi_base_row(call_node)].z,
                eval.y,
                target_reg))
            return false;
        inst_count = eval.y == target_reg ? 0u : 1u;
        return true;
    }
    return false;
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
    if (!valid_node(call_node))
        return false;

    uint4 call_abi = x86_call_abi_record[call_abi_base_row(call_node)];
    target_fn = call_abi.y;
    uint arg_count = call_abi.z;
    if (call_abi.x != fn_node ||
        !valid_node(target_fn) ||
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

uint write_call_arg_rows(uint start_inst, uint call_node, uint ordinal)
{
    uint4 lookup = x86_call_arg_lookup_record[call_arg_lookup_slot(call_node, ordinal)];
    if (lookup.x != call_node || lookup.y != ordinal || lookup.z == INVALID)
        return INVALID;

    uint value_kind = lookup.w;
    uint4 eval = x86_call_arg_eval_record[lookup.z];
    if (value_kind == X86_CALL_ARG_VALUE_SCALAR && eval.x == X86_CALL_ARG_EVAL_SCALAR_IMM)
    {
        uint inst_kind = mov_arg_imm_inst_kind(ordinal);
        if (inst_kind == 0u)
            return INVALID;
        write_inst(start_inst, inst_kind, eval.y);
        return 1u;
    }

    if (value_kind == X86_CALL_ARG_VALUE_BINARY_IMM && eval.x == X86_CALL_ARG_EVAL_BINARY_IMM)
    {
        uint mov_result = mov_arg_from_eax_inst_kind(ordinal);
        uint inst_kind = binary_imm_inst_kind(eval.w);
        if (mov_result == 0u || inst_kind == 0u || eval.w == X86_OP_MOD_I32)
            return INVALID;
        write_inst(start_inst, X86_INST_MOV_EAX_IMM32, eval.y);
        write_inst(start_inst + 1u, inst_kind, eval.z);
        write_inst(start_inst + 2u, mov_result, 0u);
        return 3u;
    }

    if (value_kind == X86_CALL_ARG_VALUE_PARAM && eval.x == X86_CALL_ARG_EVAL_PARAM_REG)
    {
        uint target_reg = sysv_integer_arg_reg(ordinal);
        if (target_reg == INVALID)
            return INVALID;
        if (eval.y == target_reg)
            return 0u;
        if (!serial_param_move_safe(
                call_node,
                ordinal,
                x86_call_abi_record[call_abi_base_row(call_node)].z,
                eval.y,
                target_reg))
            return INVALID;
        uint inst_kind = mov_param_to_arg_inst_kind(eval.y, target_reg);
        if (inst_kind == 0u)
            return INVALID;
        write_inst(start_inst, inst_kind, 0u);
        return 1u;
    }

    return INVALID;
}

bool write_call_value_to_eax(
    uint inst_i,
    uint call_node,
    uint fn_node,
    out uint inst_count)
{
    inst_count = 0u;
    call_node = resolve_expr(call_node);
    if (!valid_node(call_node))
        return false;

    uint4 call_abi = x86_call_abi_record[call_abi_base_row(call_node)];
    uint target_fn = call_abi.y;
    uint arg_count = call_abi.z;
    if (call_abi.x != fn_node ||
        !valid_node(target_fn) ||
        arg_count > X86_SYSV_MAX_INTEGER_ARGS)
        return false;

    uint cursor = inst_i;
    [loop]
    for (uint ordinal = 0u; ordinal < X86_SYSV_MAX_INTEGER_ARGS; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;
        uint wrote = write_call_arg_rows(cursor, call_node, ordinal);
        if (wrote == INVALID)
            return false;
        cursor += wrote;
    }

    write_inst(cursor, X86_INST_CALL_REL32, target_fn);
    inst_count = cursor + 1u - inst_i;
    return true;
}

bool write_owned_call_value_to_eax(
    uint inst_i,
    uint fn_node,
    out uint inst_count,
    out uint call_node)
{
    inst_count = 0u;
    call_node = INVALID;

    [loop]
    for (uint node = 0u; node < gParams.n_hir_nodes; node += 1u)
    {
        uint4 call_abi = x86_call_abi_record[call_abi_base_row(node)];
        if (call_abi.x != fn_node || !valid_node(call_abi.y))
            continue;

        uint call_count = 0u;
        if (write_call_value_to_eax(inst_i, node, fn_node, call_count))
        {
            inst_count = call_count;
            call_node = node;
            return true;
        }
    }

    return false;
}

bool write_value_to_eax(uint inst_i, uint expr_node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    expr_node = resolve_expr(expr_node);
    if (!valid_node(expr_node))
        return false;

    if (write_scalar_to_eax(inst_i, expr_node, fn_node))
    {
        inst_count = 1u;
        return true;
    }

    uint arg_reg = INVALID;
    if (expr_form(expr_node) == HIR_EXPR_NEG &&
        param_reg(expr_left(expr_node), fn_node, arg_reg))
    {
        uint mov_kind = mov_param_to_eax_inst(arg_reg);
        if (mov_kind == 0u)
            return false;
        write_inst(inst_i, mov_kind, 0u);
        write_inst(inst_i + 1u, X86_INST_NEG_EAX, 0u);
        inst_count = 2u;
        return true;
    }

    if (write_call_value_to_eax(inst_i, expr_node, fn_node, inst_count))
        return true;

    return false;
}

bool expression_is_structural_operator(uint node)
{
    node = resolve_expr(node);
    if (!valid_node(node))
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
           form == HIR_EXPR_OR;
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

bool unsigned_compare_operands(uint expr_node, uint fn_node)
{
    uint left_ty = 0u;
    uint right_ty = 0u;
    bool left_unsigned = param_type(expr_left(expr_node), fn_node, left_ty) &&
                         (left_ty == TY_UINT || left_ty == TY_CHAR);
    bool right_unsigned = param_type(expr_right(expr_node), fn_node, right_ty) &&
                          (right_ty == TY_UINT || right_ty == TY_CHAR);
    return left_unsigned || right_unsigned;
}

uint compare_op_for_expr_node(uint expr_node, uint fn_node)
{
    uint op = compare_op_for_expr_form(expr_form(expr_node));
    if (op == 0u)
        return 0u;
    return unsigned_compare_operands(expr_node, fn_node) ?
           (op | X86_CMP_UNSIGNED_FLAG) :
           op;
}

uint binary_imm_inst_kind(uint op)
{
    if (op == X86_OP_SUB_I32)
        return X86_INST_SUB_EAX_IMM32;
    if (op == X86_OP_MUL_I32)
        return X86_INST_IMUL_EAX_EAX_IMM32;
    if (op == X86_OP_AND_BOOL)
        return X86_INST_AND_EAX_IMM32;
    if (op == X86_OP_OR_BOOL)
        return X86_INST_OR_EAX_IMM32;
    if (op == X86_OP_ADD_I32)
        return X86_INST_ADD_EAX_IMM32;
    return 0u;
}

uint binary_param_inst_kind(uint op, uint arg_reg)
{
    if (arg_reg != X86_REG_ESI)
        return 0u;
    if (op == X86_OP_SUB_I32)
        return X86_INST_SUB_EAX_ESI;
    if (op == X86_OP_MUL_I32)
        return X86_INST_IMUL_EAX_ESI;
    if (op == X86_OP_AND_BOOL)
        return X86_INST_AND_EAX_ESI;
    if (op == X86_OP_OR_BOOL)
        return X86_INST_OR_EAX_ESI;
    if (op == X86_OP_ADD_I32)
        return X86_INST_ADD_EAX_ESI;
    return 0u;
}

bool write_binary_op(uint inst_i, uint expr_node, uint fn_node)
{
    expr_node = resolve_expr(expr_node);
    if (!valid_node(expr_node))
        return false;

    uint op = binary_op_for_expr_form(expr_form(expr_node));
    if (op == 0u)
        return false;
    if (!write_scalar_to_eax(inst_i, expr_left(expr_node), fn_node))
        return false;

    uint right_value = 0u;
    if (unary_literal_value(expr_right(expr_node), right_value))
    {
        uint inst_kind = binary_imm_inst_kind(op);
        if (inst_kind == 0u)
            return false;
        write_inst(inst_i + 1u, inst_kind, right_value);
        return true;
    }

    uint right_reg = INVALID;
    if (param_reg(expr_right(expr_node), fn_node, right_reg))
    {
        uint inst_kind = binary_param_inst_kind(op, right_reg);
        if (inst_kind == 0u)
            return false;
        write_inst(inst_i + 1u, inst_kind, 0u);
        return true;
    }

    return false;
}

bool write_compare_right(uint inst_i, uint right_node, uint fn_node)
{
    uint value = 0u;
    if (unary_literal_value(right_node, value))
    {
        write_inst(inst_i, X86_INST_CMP_EAX_IMM32, value);
        return true;
    }

    uint arg_reg = INVALID;
    if (param_reg(right_node, fn_node, arg_reg))
    {
        if (arg_reg == X86_REG_ESI)
        {
            write_inst(inst_i, X86_INST_CMP_EAX_ESI, 0u);
            return true;
        }
        if (arg_reg == X86_REG_EDX)
        {
            write_inst(inst_i, X86_INST_CMP_EAX_EDX, 0u);
            return true;
        }
    }

    return false;
}

bool condition_compare_inst_count(uint node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    uint op = compare_op_for_expr_form(expr_form(node));
    if (op != 0u)
    {
        uint left_count = 0u;
        if (!value_to_eax_inst_count(expr_left(node), fn_node, left_count))
            return false;

        uint right_value = 0u;
        uint right_reg = INVALID;
        if (!unary_literal_value(expr_right(node), right_value) &&
            !param_reg(expr_right(node), fn_node, right_reg))
            return false;
        inst_count = left_count + 1u;
        return true;
    }

    uint value_count = 0u;
    if (value_to_eax_inst_count(node, fn_node, value_count))
    {
        inst_count = value_count + 1u;
        return true;
    }

    return false;
}

bool write_compare_return_rows(uint inst_i, uint expr_node, uint fn_node, uint inst_count)
{
    expr_node = resolve_expr(expr_node);
    if (!valid_node(expr_node))
        return false;

    uint compare_op = 0u;
    uint compare_count = 0u;
    bool compare_ok = false;
    if (compare_op_for_expr_form(expr_form(expr_node)) != 0u)
    {
        compare_ok = write_condition_compare(inst_i, expr_node, fn_node, compare_op, compare_count);
    }
    else if (expr_form(expr_node) == HIR_EXPR_NOT)
    {
        uint value_count = 0u;
        if (write_value_to_eax(inst_i, expr_left(expr_node), fn_node, value_count))
        {
            write_inst(inst_i + value_count, X86_INST_CMP_EAX_IMM32, 0u);
            compare_op = X86_CMP_EQ;
            compare_count = value_count + 1u;
            compare_ok = true;
        }
    }

    if (!compare_ok || compare_count + 3u != inst_count)
        return false;

    write_inst(inst_i + compare_count, X86_INST_SETCC_AL, compare_op);
    write_inst(inst_i + compare_count + 1u, X86_INST_MOVZX_EAX_AL, 0u);
    write_inst(inst_i + compare_count + 2u, X86_INST_RET, 0u);
    return true;
}

bool write_compare_value_to_eax(uint inst_i, uint expr_node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    expr_node = resolve_expr(expr_node);
    if (!valid_node(expr_node))
        return false;

    uint compare_op = 0u;
    uint compare_count = 0u;
    if (!write_condition_compare(inst_i, expr_node, fn_node, compare_op, compare_count))
        return false;

    write_inst(inst_i + compare_count, X86_INST_SETCC_AL, compare_op);
    write_inst(inst_i + compare_count + 1u, X86_INST_MOVZX_EAX_AL, 0u);
    inst_count = compare_count + 2u;
    return true;
}

bool write_compare_bool_binary_return_rows(
    uint inst_i,
    uint expr_node,
    uint fn_node,
    uint inst_count)
{
    expr_node = resolve_expr(expr_node);
    if (!valid_node(expr_node))
        return false;

    uint op = binary_op_for_expr_form(expr_form(expr_node));
    if (op != X86_OP_AND_BOOL && op != X86_OP_OR_BOOL)
        return false;

    uint left_count = 0u;
    if (!write_compare_value_to_eax(inst_i, expr_left(expr_node), fn_node, left_count))
        return false;

    uint scratch_inst = inst_i + left_count;
    write_inst(scratch_inst, X86_INST_MOV_ECX_EAX, 0u);

    uint right_count = 0u;
    if (!write_compare_value_to_eax(scratch_inst + 1u, expr_right(expr_node), fn_node, right_count))
        return false;

    uint combine_inst = scratch_inst + 1u + right_count;
    write_inst(
        combine_inst,
        op == X86_OP_AND_BOOL ? X86_INST_AND_EAX_ECX : X86_INST_OR_EAX_ECX,
        0u);
    write_inst(combine_inst + 1u, X86_INST_RET, 0u);
    return combine_inst + 2u == inst_i + inst_count;
}

bool write_condition_compare(
    uint inst_i,
    uint cond_node,
    uint fn_node,
    out uint compare_op,
    out uint inst_count)
{
    compare_op = 0u;
    inst_count = 0u;
    cond_node = resolve_expr(cond_node);
    if (!valid_node(cond_node))
        return false;

    uint op = compare_op_for_expr_node(cond_node, fn_node);
    if (op != 0u)
    {
        uint left_count = 0u;
        if (!write_value_to_eax(inst_i, expr_left(cond_node), fn_node, left_count) ||
            !write_compare_right(inst_i + left_count, expr_right(cond_node), fn_node))
            return false;
        compare_op = op;
        inst_count = left_count + 1u;
        return true;
    }

    uint value_count = 0u;
    if (!write_value_to_eax(inst_i, cond_node, fn_node, value_count))
        return false;
    write_inst(inst_i + value_count, X86_INST_CMP_EAX_IMM32, 0u);
    compare_op = X86_CMP_NE;
    inst_count = value_count + 1u;
    return true;
}

bool return_record(uint fn_node, out uint ret_expr)
{
    ret_expr = INVALID;
    uint4 record = x86_func_return_stmt_record[fn_node];
    if (record.x != fn_node || record.w != X86_FUNC_RETURN_STMT_TOP_LEVEL ||
        !valid_node(record.z))
        return false;
    ret_expr = record.z;
    return true;
}

bool terminal_if_record(uint fn_node, out uint cond_node, out uint then_expr, out uint else_expr)
{
    cond_node = INVALID;
    then_expr = INVALID;
    else_expr = INVALID;
    if (!valid_node(fn_node))
        return false;

    uint4 record = x86_terminal_if_record[fn_node];
    if (!valid_node(record.x) || !valid_node(record.y) ||
        !valid_node(record.z) || !valid_node(record.w))
        return false;

    cond_node = record.y;
    then_expr = record.z;
    else_expr = record.w;
    return true;
}

bool write_flat_terminal_if_value_rows(
    uint key_node,
    uint fn_node,
    uint start_inst,
    uint common_ret_inst,
    out uint inst_count,
    out uint detail)
{
    inst_count = 0u;
    detail = key_node;
    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (!terminal_if_record(key_node, cond_node, then_expr, else_expr))
        return false;

    uint compare_op = 0u;
    uint cond_count = 0u;
    if (!write_condition_compare(start_inst, cond_node, fn_node, compare_op, cond_count))
    {
        detail = cond_node;
        return false;
    }

    uint then_start = start_inst + cond_count + 1u;
    uint then_count = 0u;
    if (!write_value_to_eax(then_start, then_expr, fn_node, then_count))
    {
        detail = then_expr;
        return false;
    }

    uint else_start = then_start + then_count + 1u;
    uint else_count = 0u;
    if (!write_value_to_eax(else_start, else_expr, fn_node, else_count))
    {
        detail = else_expr;
        return false;
    }

    write_inst(start_inst + cond_count, X86_INST_JCC_FALSE_REL32, compare_op);
    write_inst(then_start + then_count, X86_INST_JMP_REL32, 0u);
    inst_count = else_start + else_count - start_inst;
    if (common_ret_inst != start_inst + inst_count)
    {
        detail = common_ret_inst;
        return false;
    }
    return true;
}

bool write_terminal_if_value_rows(
    uint key_node,
    uint fn_node,
    uint start_inst,
    uint common_ret_inst,
    out uint inst_count,
    out uint detail)
{
    inst_count = 0u;
    detail = key_node;
    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (!terminal_if_record(key_node, cond_node, then_expr, else_expr))
        return false;

    uint compare_op = 0u;
    uint cond_count = 0u;
    if (!write_condition_compare(start_inst, cond_node, fn_node, compare_op, cond_count))
    {
        detail = cond_node;
        return false;
    }

    uint then_start = start_inst + cond_count + 1u;
    uint then_count = 0u;
    if (!write_value_to_eax(then_start, then_expr, fn_node, then_count))
    {
        detail = then_expr;
        return false;
    }

    uint else_start = then_start + then_count + 1u;
    uint else_count = 0u;
    if (!write_value_to_eax(else_start, else_expr, fn_node, else_count) &&
        !write_flat_terminal_if_value_rows(
            else_expr,
            fn_node,
            else_start,
            common_ret_inst,
            else_count,
            detail))
    {
        detail = else_expr;
        return false;
    }

    write_inst(start_inst + cond_count, X86_INST_JCC_FALSE_REL32, compare_op);
    write_inst(then_start + then_count, X86_INST_JMP_REL32, 0u);
    inst_count = else_start + else_count - start_inst;
    return true;
}

bool write_terminal_if_rows(uint fn_node, uint start_inst, uint inst_count, out uint detail)
{
    uint body_count = 0u;
    if (!write_terminal_if_value_rows(
            fn_node,
            fn_node,
            start_inst,
            start_inst + inst_count - 1u,
            body_count,
            detail) ||
        body_count + 1u != inst_count)
        return false;

    write_inst(start_inst + body_count, X86_INST_RET, 0u);
    return true;
}

bool write_function_return_rows(uint fn_node, uint start_inst, uint inst_count, out uint detail)
{
    detail = fn_node;
    if (write_terminal_if_rows(fn_node, start_inst, inst_count, detail))
        return true;

    uint ret_expr = INVALID;
    if (!return_record(fn_node, ret_expr))
        return false;

    uint value_count = 0u;
    if (write_value_to_eax(start_inst, ret_expr, fn_node, value_count) &&
        value_count + 1u == inst_count)
    {
        x86_planned_inst_kind[start_inst + value_count] = X86_INST_RET;
        x86_planned_inst_arg0[start_inst + value_count] = 0u;
        return true;
    }

    uint owned_call_count = 0u;
    uint owned_call_node = INVALID;
    if (!expression_is_structural_operator(ret_expr) &&
        write_owned_call_value_to_eax(
            start_inst,
            fn_node,
            owned_call_count,
            owned_call_node) &&
        owned_call_count + 1u == inst_count)
    {
        x86_planned_inst_kind[start_inst + owned_call_count] = X86_INST_RET;
        x86_planned_inst_arg0[start_inst + owned_call_count] = 0u;
        return true;
    }

    if (inst_count == 3u)
    {
        detail = ret_expr;
        if (!write_binary_op(start_inst, ret_expr, fn_node))
            return false;
        x86_planned_inst_kind[start_inst + 2u] = X86_INST_RET;
        x86_planned_inst_arg0[start_inst + 2u] = 0u;
        return true;
    }

    detail = ret_expr;
    if (write_compare_return_rows(start_inst, ret_expr, fn_node, inst_count))
        return true;
    if (write_compare_bool_binary_return_rows(start_inst, ret_expr, fn_node, inst_count))
        return true;

    detail = inst_count;
    return false;
}

void publish_status(bool ok, uint error, uint detail, uint count)
{
    x86_func_return_inst_status[0u] = ok ? X86_FUNC_RETURN_INST_OK : 0u;
    x86_func_return_inst_status[1u] = ok ? 0u : error;
    x86_func_return_inst_status[2u] = ok ? INVALID : detail;
    x86_func_return_inst_status[3u] = ok ? count : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    bool upstream_ok = layout_ok();
    if (node_i == 0u)
    {
        publish_status(
            upstream_ok,
            x86_func_layout_status[1u] == 0u ? X86_ERR_UNSUPPORTED_RETURN :
                                               x86_func_layout_status[1u],
            x86_func_layout_status[2u],
            0u);
    }

    if (!upstream_ok || !valid_node(node_i))
        return;

    uint4 layout = x86_func_layout_record[node_i];
    if (layout.x == INVALID || layout.y == 0u || layout.z != X86_FUNC_LAYOUT_CALLEE)
        return;

    uint detail = node_i;
    if (write_function_return_rows(node_i, layout.x, layout.y, detail))
    {
        uint old_count = 0u;
        InterlockedAdd(x86_func_return_inst_status[3u], 1u, old_count);
    }
    else
    {
        x86_func_return_inst_status[0u] = 0u;
        x86_func_return_inst_status[1u] = X86_ERR_UNSUPPORTED_RETURN;
        uint old_detail = 0u;
        InterlockedMin(x86_func_return_inst_status[2u], detail, old_detail);
    }
}
