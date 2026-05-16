// x86_64 entry instruction planning over backend value/use/layout records.
//
// This pass materializes only the entry function rows currently represented as
// a vreg graph. Direct function-call rows were removed with the old callee body
// path; calls should return through generic node-level function
// instruction generation when that backend stage exists.

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
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint4> x86_const_value_record;
StructuredBuffer<uint> x86_const_value_status;
StructuredBuffer<uint4> x86_local_literal_record;
StructuredBuffer<uint> x86_local_literal_status;
StructuredBuffer<uint4> x86_intrinsic_call_record;
StructuredBuffer<uint> x86_intrinsic_call_status;
StructuredBuffer<uint> x86_vreg_kind;
StructuredBuffer<uint> x86_vreg_value;
StructuredBuffer<uint4> x86_vreg_args;
StructuredBuffer<uint> x86_vreg_op;
StructuredBuffer<uint> x86_use_key;
StructuredBuffer<uint> x86_use_value;
StructuredBuffer<uint> x86_return_vreg;
StructuredBuffer<uint4> x86_call_abi_record;
StructuredBuffer<uint4> x86_call_arg_lookup_record;
StructuredBuffer<uint4> x86_call_arg_eval_record;
StructuredBuffer<uint4> x86_func_layout_record;
StructuredBuffer<uint> x86_func_layout_status;
StructuredBuffer<uint> x86_func_return_inst_status;

RWStructuredBuffer<uint> x86_planned_inst_kind;
RWStructuredBuffer<uint> x86_planned_inst_arg0;
RWStructuredBuffer<uint> x86_entry_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_VREGS = 8u;
static const uint MAX_X86_OPERANDS = 4u;
static const uint MAX_X86_USE_EDGES = MAX_X86_VREGS * MAX_X86_OPERANDS + 1u;
static const uint MAX_X86_INSTS = 256u;
static const uint X86_FUNC_LAYOUT_OK = 1u;
static const uint X86_FUNC_RETURN_INST_OK = 1u;
static const uint X86_ENTRY_INST_OK = 1u;
static const uint X86_VREG_IMM_I32 = 1u;
static const uint X86_VREG_BINARY_I32 = 2u;
static const uint X86_VREG_BRANCH_I32 = 3u;
static const uint X86_VREG_COMPARE_I32 = 4u;
static const uint X86_VREG_CALL_I32 = 5u;
static const uint X86_ERR_UNSUPPORTED_RETURN = 3u;
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
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint X86_CALL_ARG_VALUE_SCALAR = 1u;
static const uint X86_CALL_ARG_VALUE_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_EVAL_SCALAR_IMM = 1u;
static const uint X86_CALL_ARG_EVAL_BINARY_IMM = 2u;
static const uint X86_INTRINSIC_CALLS_OK = 1u;
static const uint X86_INTRINSIC_TEXT_WRITE = 1u;
static const uint X86_INTRINSIC_TEXT_WRITE_CODE_ROWS = 5u;
static const uint X86_INTRINSIC_TEXT_WRITE_DATA_ROWS = 1u;
static const uint X86_INTRINSIC_IF_TEXT_WRITE_CODE_ROWS = 14u;
static const uint X86_INTRINSIC_IF_TEXT_WRITE_DATA_ROWS = 2u;
static const uint X86_INTRINSIC_IF_THEN_TEXT_WRITE_CODE_ROWS = 8u;
static const uint X86_INTRINSIC_IF_THEN_TEXT_WRITE_DATA_ROWS = 1u;
static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
static const uint X86_CONST_VALUES_OK = 1u;
static const uint X86_CONST_VALUE_LITERAL = 1u;
static const uint X86_LOCAL_LITERALS_OK = 1u;
static const uint X86_LOCAL_LITERAL_TOP_LEVEL = 1u;

static const uint X86_INST_MOV_EAX_IMM32 = 1u;
static const uint X86_INST_MOV_EDI_IMM32 = 2u;
static const uint X86_INST_SYSCALL = 3u;
static const uint X86_INST_ADD_EAX_IMM32 = 4u;
static const uint X86_INST_SUB_EAX_IMM32 = 5u;
static const uint X86_INST_IMUL_EAX_EAX_IMM32 = 6u;
static const uint X86_INST_MOV_EDI_EAX = 7u;
static const uint X86_INST_CMP_EAX_IMM32 = 8u;
static const uint X86_INST_JCC_FALSE_REL32 = 9u;
static const uint X86_INST_JMP_REL32 = 10u;
static const uint X86_INST_SETCC_AL = 11u;
static const uint X86_INST_MOVZX_EDI_AL = 12u;
static const uint X86_INST_AND_EAX_IMM32 = 13u;
static const uint X86_INST_OR_EAX_IMM32 = 14u;
static const uint X86_INST_CALL_REL32 = 15u;
static const uint X86_INST_MOV_ESI_IMM32 = 18u;
static const uint X86_INST_MOV_ESI_EAX = 24u;
static const uint X86_INST_MOV_EDX_IMM32 = 27u;
static const uint X86_INST_CDQ = 32u;
static const uint X86_INST_MOV_ECX_IMM32 = 33u;
static const uint X86_INST_IDIV_ECX = 34u;
static const uint X86_INST_MOV_EDI_EDX = 35u;
static const uint X86_INST_XOR_EAX_IMM32 = 39u;
static const uint X86_INST_SHL_EAX_IMM8 = 40u;
static const uint X86_INST_SAR_EAX_IMM8 = 41u;
static const uint X86_INST_DATA_I32_NL = 48u;
static const uint X86_INST_MOV_ESI_TEXT_ROW_ADDR = 49u;

static const uint X86_LAYOUT_STATUS_TOTAL_INSTS = 3u;
static const uint X86_LAYOUT_STATUS_OWNER_FN = 4u;
static const uint X86_LAYOUT_STATUS_SHAPE = 6u;
static const uint X86_LAYOUT_STATUS_VREG_COUNT = 8u;
static const uint X86_ENTRY_STATUS_INST_COUNT = 3u;
static const uint X86_ENTRY_STATUS_CALL_SITE_INST = 4u;
static const uint X86_ENTRY_STATUS_RELOC_COUNT = 5u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

bool is_compare_op(uint op)
{
    uint base = op & ~X86_CMP_UNSIGNED_FLAG;
    return base == X86_CMP_LT || base == X86_CMP_GT || base == X86_CMP_LE ||
           base == X86_CMP_GE || base == X86_CMP_EQ || base == X86_CMP_NE;
}

bool valid_vreg(uint vreg, uint vreg_count)
{
    return vreg != INVALID && vreg < vreg_count;
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
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
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

bool intrinsic_calls_ok()
{
    return x86_intrinsic_call_status[0u] == X86_INTRINSIC_CALLS_OK &&
           x86_intrinsic_call_status[1u] == 0u;
}

bool const_values_ok()
{
    return x86_const_value_status[0u] == X86_CONST_VALUES_OK &&
           x86_const_value_status[1u] == 0u;
}

bool local_literals_ok()
{
    return x86_local_literal_status[0u] == X86_LOCAL_LITERALS_OK &&
           x86_local_literal_status[1u] == 0u;
}

uint parent_node(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

uint owning_function_node(uint node)
{
    if (!valid_node(node))
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
    if (!valid_node(node))
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
    if (!valid_node(node) || !valid_node(ancestor))
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

bool is_imm_vreg(uint vreg, uint vreg_count)
{
    return valid_vreg(vreg, vreg_count) && x86_vreg_kind[vreg] == X86_VREG_IMM_I32;
}

bool valid_binary_op(uint op)
{
    return op >= X86_OP_ADD_I32 && op <= X86_OP_SHR_I32;
}

uint use_key_user(uint key)
{
    return key & 0xffffu;
}

uint use_key_slot(uint key)
{
    return (key >> 16u) & 0xffffu;
}

uint use_value_for_slot(uint user_vreg, uint wanted_slot)
{
    [loop]
    for (uint edge_i = 0u; edge_i < MAX_X86_USE_EDGES; edge_i += 1u)
    {
        uint key = x86_use_key[edge_i];
        if (key != INVALID && use_key_user(key) == user_vreg &&
            use_key_slot(key) == wanted_slot)
            return x86_use_value[edge_i];
    }
    return INVALID;
}

uint binary_inst_kind(uint op)
{
    if (op == X86_OP_SUB_I32) return X86_INST_SUB_EAX_IMM32;
    if (op == X86_OP_MUL_I32) return X86_INST_IMUL_EAX_EAX_IMM32;
    if (op == X86_OP_AND_BOOL || op == X86_OP_BIT_AND_I32) return X86_INST_AND_EAX_IMM32;
    if (op == X86_OP_OR_BOOL || op == X86_OP_BIT_OR_I32) return X86_INST_OR_EAX_IMM32;
    if (op == X86_OP_BIT_XOR_I32) return X86_INST_XOR_EAX_IMM32;
    if (op == X86_OP_SHL_I32) return X86_INST_SHL_EAX_IMM8;
    if (op == X86_OP_SHR_I32) return X86_INST_SAR_EAX_IMM8;
    if (op == X86_OP_ADD_I32) return X86_INST_ADD_EAX_IMM32;
    return 0u;
}

uint call_arg_lookup_slot(uint call_node, uint ordinal)
{
    return call_node * X86_SYSV_MAX_INTEGER_ARGS + ordinal;
}

uint call_abi_base_row(uint call_node)
{
    return call_node * 2u;
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

void write_inst(uint inst_i, uint kind, uint arg0)
{
    if (inst_i < MAX_X86_INSTS)
    {
        x86_planned_inst_kind[inst_i] = kind;
        x86_planned_inst_arg0[inst_i] = arg0;
    }
}

uint function_start_inst(uint fn_node)
{
    if (fn_node == INVALID || fn_node >= gParams.n_hir_nodes)
        return INVALID;
    return x86_func_layout_record[fn_node].x;
}

bool owner_layout_ok(uint owner_fn)
{
    if (owner_fn == INVALID || owner_fn >= gParams.n_hir_nodes)
        return false;
    uint4 layout = x86_func_layout_record[owner_fn];
    return layout.x != INVALID && layout.y != 0u && layout.x + layout.y <= MAX_X86_INSTS;
}

uint abs_i32_magnitude(uint value)
{
    return (value & 0x80000000u) != 0u ? (0u - value) : value;
}

uint decimal_digit_count_u32(uint value)
{
    if (value < 10u) return 1u;
    if (value < 100u) return 2u;
    if (value < 1000u) return 3u;
    if (value < 10000u) return 4u;
    if (value < 100000u) return 5u;
    if (value < 1000000u) return 6u;
    if (value < 10000000u) return 7u;
    if (value < 100000000u) return 8u;
    if (value < 1000000000u) return 9u;
    return 10u;
}

uint i32_text_len(uint value)
{
    uint digits = decimal_digit_count_u32(abs_i32_magnitude(value));
    uint sign = (value & 0x80000000u) != 0u ? 1u : 0u;
    return sign + digits + 1u;
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

bool expr_leaf_value(uint value_node, uint fn_node, out uint value)
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

uint hir_binary_value(uint form, uint left, uint right, out bool ok)
{
    ok = true;
    if (form == HIR_EXPR_ADD) return left + right;
    if (form == HIR_EXPR_SUB) return left - right;
    if (form == HIR_EXPR_MUL) return left * right;
    if (form == HIR_EXPR_EQ) return left == right ? 1u : 0u;
    if (form == HIR_EXPR_NE) return left != right ? 1u : 0u;
    if (form == HIR_EXPR_LT) return int(left) < int(right) ? 1u : 0u;
    if (form == HIR_EXPR_GT) return int(left) > int(right) ? 1u : 0u;
    if (form == HIR_EXPR_LE) return int(left) <= int(right) ? 1u : 0u;
    if (form == HIR_EXPR_GE) return int(left) >= int(right) ? 1u : 0u;
    if (form == HIR_EXPR_AND) return (left != 0u && right != 0u) ? 1u : 0u;
    if (form == HIR_EXPR_OR) return (left != 0u || right != 0u) ? 1u : 0u;
    if (form == HIR_EXPR_BIT_AND) return left & right;
    if (form == HIR_EXPR_BIT_OR) return left | right;
    if (form == HIR_EXPR_BIT_XOR) return left ^ right;
    if (form == HIR_EXPR_SHL) return left << (right & 31u);
    if (form == HIR_EXPR_SHR) return uint(int(left) >> int(right & 31u));
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
    ok = false;
    return 0u;
}

bool expr_scalar_value(uint value_node, uint fn_node, out uint value)
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
            if (expr_leaf_value(node, fn_node, last_value))
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
            hir_binary_value(form, 1u, 1u, op_ok);
            if (!op_ok || sp >= 32u)
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
            uint result = hir_binary_value(form, left_stack[frame], last_value, ok);
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
    if (arg_node == INVALID || arg_node >= gParams.n_hir_nodes)
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
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_intrinsic_call_record[call_node];
    if (record.y != call_node || record.w != X86_INTRINSIC_TEXT_WRITE)
        return false;
    return intrinsic_output_arg_value(record.z, value);
}

bool top_level_text_write_call(uint call_node, uint fn_node, out uint value)
{
    value = 0u;
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_intrinsic_call_record[call_node];
    if (record.x != fn_node ||
        record.y != call_node ||
        record.w != X86_INTRINSIC_TEXT_WRITE ||
        has_if_ancestor_before_function(call_node))
        return false;

    return intrinsic_text_write_call_value(call_node, value);
}

bool branch_text_write_call(
    uint block_node,
    uint fn_node,
    out uint call_node,
    out uint arg_node)
{
    call_node = INVALID;
    arg_node = INVALID;
    if (!valid_node(block_node) || !valid_node(fn_node))
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
    if (!valid_node(fn_node) || !intrinsic_calls_ok())
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
        uint cond_value = 0u;
        if (!expr_scalar_value(cond_node, fn_node, cond_value) ||
            !branch_text_write_call(then_block, fn_node, then_call, then_arg))
        {
            failure_node = node;
            return false;
        }
        if (branch_text_write_call(else_block, fn_node, else_call, else_arg))
        {
            code_count += X86_INTRINSIC_IF_TEXT_WRITE_CODE_ROWS;
            data_count += X86_INTRINSIC_IF_TEXT_WRITE_DATA_ROWS;
            reloc_count += 2u;
            accounted_calls += 2u;
        }
        else
        {
            code_count += X86_INTRINSIC_IF_THEN_TEXT_WRITE_CODE_ROWS;
            data_count += X86_INTRINSIC_IF_THEN_TEXT_WRITE_DATA_ROWS;
            reloc_count += 1u;
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

uint write_text_output_rows(uint code_cursor, uint data_cursor, uint value)
{
    write_inst(code_cursor + 0u, X86_INST_MOV_EAX_IMM32, 1u);
    write_inst(code_cursor + 1u, X86_INST_MOV_EDI_IMM32, 1u);
    write_inst(code_cursor + 2u, X86_INST_MOV_ESI_TEXT_ROW_ADDR, data_cursor);
    write_inst(code_cursor + 3u, X86_INST_MOV_EDX_IMM32, i32_text_len(value));
    write_inst(code_cursor + 4u, X86_INST_SYSCALL, 0u);
    write_inst(data_cursor, X86_INST_DATA_I32_NL, value);
    return X86_INTRINSIC_TEXT_WRITE_CODE_ROWS;
}

uint write_intrinsic_output_rows(uint start_inst, uint fn_node, uint data_start_inst)
{
    uint code_cursor = start_inst;
    uint data_cursor = data_start_inst;
    uint accounted_calls = 0u;
    [loop]
    for (uint node = 0u; node < gParams.n_hir_nodes; node += 1u)
    {
        uint top_value = 0u;
        if (top_level_text_write_call(node, fn_node, top_value))
        {
            code_cursor += write_text_output_rows(code_cursor, data_cursor, top_value);
            data_cursor += X86_INTRINSIC_TEXT_WRITE_DATA_ROWS;
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
        if (!branch_text_write_call(then_block, fn_node, then_call, then_arg) ||
            (!branch_text_write_call(else_block, fn_node, else_call, else_arg) &&
             valid_node(else_block)))
            return INVALID;

        uint cond_value = 0u;
        uint then_value = 0u;
        uint else_value = 0u;
        if (!expr_scalar_value(cond_node, fn_node, cond_value) ||
            !intrinsic_output_arg_value(then_arg, then_value))
            return INVALID;

        write_inst(code_cursor + 0u, X86_INST_MOV_EAX_IMM32, cond_value);
        write_inst(code_cursor + 1u, X86_INST_CMP_EAX_IMM32, 0u);
        write_inst(code_cursor + 2u, X86_INST_JCC_FALSE_REL32, X86_CMP_NE);
        code_cursor += 3u;
        code_cursor += write_text_output_rows(code_cursor, data_cursor, then_value);
        data_cursor += 1u;
        if (else_call != INVALID)
        {
            if (!intrinsic_output_arg_value(else_arg, else_value))
                return INVALID;
            write_inst(code_cursor, X86_INST_JMP_REL32, 0u);
            code_cursor += 1u;
            code_cursor += write_text_output_rows(code_cursor, data_cursor, else_value);
            data_cursor += 1u;
            accounted_calls += 2u;
        }
        else
        {
            accounted_calls += 1u;
        }
    }

    if (accounted_calls != owned_intrinsic_call_count(fn_node))
        return INVALID;
    return code_cursor - start_inst;
}

void write_literal_rows(uint start_inst, uint return_vreg)
{
    write_inst(start_inst, X86_INST_MOV_EAX_IMM32, 60u);
    write_inst(start_inst + 1u, X86_INST_MOV_EDI_IMM32, x86_vreg_value[return_vreg]);
    write_inst(start_inst + 2u, X86_INST_SYSCALL, 0u);
}

void write_binary_rows(uint start_inst, uint return_vreg, uint arg0, uint arg1)
{
    if (x86_vreg_op[return_vreg] == X86_OP_MOD_I32 ||
        x86_vreg_op[return_vreg] == X86_OP_DIV_I32)
    {
        write_inst(start_inst, X86_INST_MOV_EAX_IMM32, x86_vreg_value[arg0]);
        write_inst(start_inst + 1u, X86_INST_CDQ, 0u);
        write_inst(start_inst + 2u, X86_INST_MOV_ECX_IMM32, x86_vreg_value[arg1]);
        write_inst(start_inst + 3u, X86_INST_IDIV_ECX, 0u);
        write_inst(
            start_inst + 4u,
            x86_vreg_op[return_vreg] == X86_OP_MOD_I32 ? X86_INST_MOV_EDI_EDX : X86_INST_MOV_EDI_EAX,
            0u);
        write_inst(start_inst + 5u, X86_INST_MOV_EAX_IMM32, 60u);
        write_inst(start_inst + 6u, X86_INST_SYSCALL, 0u);
        return;
    }

    write_inst(start_inst, X86_INST_MOV_EAX_IMM32, x86_vreg_value[arg0]);
    write_inst(start_inst + 1u, binary_inst_kind(x86_vreg_op[return_vreg]), x86_vreg_value[arg1]);
    write_inst(start_inst + 2u, X86_INST_MOV_EDI_EAX, 0u);
    write_inst(start_inst + 3u, X86_INST_MOV_EAX_IMM32, 60u);
    write_inst(start_inst + 4u, X86_INST_SYSCALL, 0u);
}

void write_compare_rows(uint start_inst, uint return_vreg, uint arg0, uint arg1)
{
    write_inst(start_inst, X86_INST_MOV_EAX_IMM32, x86_vreg_value[arg0]);
    write_inst(start_inst + 1u, X86_INST_CMP_EAX_IMM32, x86_vreg_value[arg1]);
    write_inst(start_inst + 2u, X86_INST_SETCC_AL, x86_vreg_op[return_vreg]);
    write_inst(start_inst + 3u, X86_INST_MOVZX_EDI_AL, 0u);
    write_inst(start_inst + 4u, X86_INST_MOV_EAX_IMM32, 60u);
    write_inst(start_inst + 5u, X86_INST_SYSCALL, 0u);
}

void write_branch_rows(uint start_inst, uint return_vreg, uint arg0, uint arg1, uint arg2, uint arg3)
{
    write_inst(start_inst, X86_INST_MOV_EAX_IMM32, x86_vreg_value[arg0]);
    write_inst(start_inst + 1u, X86_INST_CMP_EAX_IMM32, x86_vreg_value[arg1]);
    write_inst(start_inst + 2u, X86_INST_JCC_FALSE_REL32, x86_vreg_op[return_vreg]);
    write_inst(start_inst + 3u, X86_INST_MOV_EDI_IMM32, x86_vreg_value[arg2]);
    write_inst(start_inst + 4u, X86_INST_JMP_REL32, 0u);
    write_inst(start_inst + 5u, X86_INST_MOV_EDI_IMM32, x86_vreg_value[arg3]);
    write_inst(start_inst + 6u, X86_INST_MOV_EAX_IMM32, 60u);
    write_inst(start_inst + 7u, X86_INST_SYSCALL, 0u);
}

uint write_call_arg_rows(uint start_inst, uint call_node, uint ordinal)
{
    uint4 lookup = x86_call_arg_lookup_record[call_arg_lookup_slot(call_node, ordinal)];
    if (lookup.x != call_node || lookup.y != ordinal || lookup.z == INVALID)
        return 0u;

    uint value_kind = lookup.w;
    uint4 eval = x86_call_arg_eval_record[lookup.z];
    if (value_kind == X86_CALL_ARG_VALUE_SCALAR && eval.x == X86_CALL_ARG_EVAL_SCALAR_IMM)
    {
        uint inst_kind = mov_arg_imm_inst_kind(ordinal);
        if (inst_kind == 0u)
            return 0u;
        write_inst(start_inst, inst_kind, eval.y);
        return 1u;
    }

    if (value_kind == X86_CALL_ARG_VALUE_BINARY_IMM && eval.x == X86_CALL_ARG_EVAL_BINARY_IMM)
    {
        uint mov_result = mov_arg_from_eax_inst_kind(ordinal);
        if (mov_result == 0u ||
            !valid_binary_op(eval.w) ||
            eval.w == X86_OP_MOD_I32 ||
            eval.w == X86_OP_DIV_I32)
            return 0u;
        write_inst(start_inst, X86_INST_MOV_EAX_IMM32, eval.y);
        write_inst(start_inst + 1u, binary_inst_kind(eval.w), eval.z);
        write_inst(start_inst + 2u, mov_result, 0u);
        return 3u;
    }

    return 0u;
}

uint write_call_arg_range_rows(uint start_inst, uint call_node, uint arg_count)
{
    uint cursor = start_inst;
    [loop]
    for (uint ordinal = 0u; ordinal < X86_SYSV_MAX_INTEGER_ARGS; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;
        uint wrote = write_call_arg_rows(cursor, call_node, ordinal);
        if (wrote == 0u)
            return INVALID;
        cursor += wrote;
    }
    return cursor - start_inst;
}

uint write_call_rows(uint start_inst, uint return_vreg)
{
    uint call_node = x86_vreg_value[return_vreg];
    if (call_node == INVALID || call_node >= gParams.n_hir_nodes)
        return INVALID;

    uint4 call_abi = x86_call_abi_record[call_abi_base_row(call_node)];
    uint target_fn = call_abi.y;
    uint arg_count = call_abi.z;
    if (call_abi.x != x86_func_layout_status[X86_LAYOUT_STATUS_OWNER_FN] ||
        target_fn == INVALID || target_fn >= gParams.n_hir_nodes)
        return INVALID;

    uint arg_inst_count = write_call_arg_range_rows(start_inst, call_node, arg_count);
    if (arg_inst_count == INVALID)
        return INVALID;

    uint call_site_inst = start_inst + arg_inst_count;
    write_inst(call_site_inst, X86_INST_CALL_REL32, target_fn);
    write_inst(call_site_inst + 1u, X86_INST_MOV_EDI_EAX, 0u);
    write_inst(call_site_inst + 2u, X86_INST_MOV_EAX_IMM32, 60u);
    write_inst(call_site_inst + 3u, X86_INST_SYSCALL, 0u);
    return call_site_inst;
}

void publish_status(
    bool ok,
    uint error,
    uint detail,
    uint inst_count,
    uint call_site_inst,
    uint reloc_count)
{
    x86_entry_inst_status[0u] = ok ? X86_ENTRY_INST_OK : 0u;
    x86_entry_inst_status[1u] = ok ? 0u : error;
    x86_entry_inst_status[2u] = ok ? INVALID : detail;
    x86_entry_inst_status[X86_ENTRY_STATUS_INST_COUNT] = ok ? inst_count : 0u;
    x86_entry_inst_status[X86_ENTRY_STATUS_CALL_SITE_INST] = ok ? call_site_inst : INVALID;
    x86_entry_inst_status[X86_ENTRY_STATUS_RELOC_COUNT] = ok ? reloc_count : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (linear_dispatch_id(tid) != 0u)
        return;

    bool layout_ok = x86_func_layout_status[0u] == X86_FUNC_LAYOUT_OK &&
                     x86_func_layout_status[1u] == 0u &&
                     x86_func_return_inst_status[0u] == X86_FUNC_RETURN_INST_OK &&
                     x86_func_return_inst_status[1u] == 0u;
    uint vreg_count = layout_ok ? x86_func_layout_status[X86_LAYOUT_STATUS_VREG_COUNT] : 0u;
    uint return_vreg = x86_return_vreg[0u];
    bool valid_return = valid_vreg(return_vreg, vreg_count);
    uint return_kind = valid_return ? x86_vreg_kind[return_vreg] : 0u;
    uint return_op = valid_return ? x86_vreg_op[return_vreg] : 0u;
    uint arg0 = valid_return ? use_value_for_slot(return_vreg, 0u) : INVALID;
    uint arg1 = valid_return ? use_value_for_slot(return_vreg, 1u) : INVALID;
    uint arg2 = valid_return ? use_value_for_slot(return_vreg, 2u) : INVALID;
    uint arg3 = valid_return ? use_value_for_slot(return_vreg, 3u) : INVALID;
    uint layout_shape = layout_ok ? x86_func_layout_status[X86_LAYOUT_STATUS_SHAPE] : 0u;
    uint owner_fn = layout_ok ? x86_func_layout_status[X86_LAYOUT_STATUS_OWNER_FN] : INVALID;
    uint entry_start_inst = layout_ok ? function_start_inst(owner_fn) : INVALID;
    bool entry_layout_ok = layout_ok && owner_layout_ok(owner_fn);
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

    bool literal_ok = return_kind == X86_VREG_IMM_I32 &&
                      layout_shape == X86_SELECT_SHAPE_LITERAL &&
                      entry_layout_ok;
    bool binary_ok = return_kind == X86_VREG_BINARY_I32 &&
                     is_imm_vreg(arg0, vreg_count) && is_imm_vreg(arg1, vreg_count) &&
                     valid_binary_op(return_op) &&
                     layout_shape == X86_SELECT_SHAPE_BINARY &&
                     entry_layout_ok;
    bool compare_ok = return_kind == X86_VREG_COMPARE_I32 &&
                      is_imm_vreg(arg0, vreg_count) && is_imm_vreg(arg1, vreg_count) &&
                      is_compare_op(return_op) &&
                      layout_shape == X86_SELECT_SHAPE_COMPARE &&
                      entry_layout_ok;
    bool branch_ok = return_kind == X86_VREG_BRANCH_I32 &&
                     is_imm_vreg(arg0, vreg_count) && is_imm_vreg(arg1, vreg_count) &&
                     is_imm_vreg(arg2, vreg_count) && is_imm_vreg(arg3, vreg_count) &&
                     is_compare_op(return_op) &&
                     layout_shape == X86_SELECT_SHAPE_BRANCH &&
                     entry_layout_ok;
    bool call_ok = return_kind == X86_VREG_CALL_I32 &&
                   layout_shape == X86_SELECT_SHAPE_CALL &&
                   entry_layout_ok;
    bool ok = layout_ok && output_ok &&
              (literal_ok || binary_ok || compare_ok || branch_ok || call_ok);
    uint inst_count = ok ? x86_func_layout_status[X86_LAYOUT_STATUS_TOTAL_INSTS] : 0u;
    uint call_site_inst = INVALID;
    uint return_start_inst = entry_start_inst + output_code_count;
    uint data_start_inst = inst_count >= output_data_count ?
                           entry_start_inst + inst_count - output_data_count :
                           INVALID;

    if (ok && output_code_count != 0u)
    {
        uint output_rows = write_intrinsic_output_rows(
            entry_start_inst,
            owner_fn,
            data_start_inst);
        ok = output_rows == output_code_count;
    }
    if (ok && literal_ok)
        write_literal_rows(return_start_inst, return_vreg);
    if (ok && binary_ok)
        write_binary_rows(return_start_inst, return_vreg, arg0, arg1);
    if (ok && compare_ok)
        write_compare_rows(return_start_inst, return_vreg, arg0, arg1);
    if (ok && branch_ok)
        write_branch_rows(return_start_inst, return_vreg, arg0, arg1, arg2, arg3);
    if (ok && call_ok)
    {
        call_site_inst = write_call_rows(return_start_inst, return_vreg);
        ok = call_site_inst != INVALID;
    }

    uint error = x86_func_layout_status[1u] != 0u ? x86_func_layout_status[1u] :
                 (x86_func_return_inst_status[1u] != 0u ? x86_func_return_inst_status[1u] :
                  X86_ERR_UNSUPPORTED_RETURN);
    uint detail = x86_func_layout_status[1u] != 0u ? x86_func_layout_status[2u] :
                  (x86_func_return_inst_status[1u] != 0u ? x86_func_return_inst_status[2u] :
                   (!output_ok ? output_failure_detail : x86_func_layout_status[2u]));
    publish_status(ok, error, detail, inst_count, call_site_inst, output_reloc_count);
}
