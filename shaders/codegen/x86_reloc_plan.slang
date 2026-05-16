// x86_64 relocation-row planning over layout and entry-instruction records.
//
// Instruction rows are materialized before this pass. This pass owns the
// planned branch/call relocation rows so selection only copies complete
// instruction and relocation records into the backend buffers.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_return_vreg;
StructuredBuffer<uint> x86_vreg_value;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint4> x86_call_abi_record;
StructuredBuffer<uint4> x86_call_arg_lookup_record;
StructuredBuffer<uint4> x86_call_arg_eval_record;
StructuredBuffer<uint4> x86_terminal_if_record;
StructuredBuffer<uint4> x86_param_reg_record;
StructuredBuffer<uint4> x86_intrinsic_call_record;
StructuredBuffer<uint> x86_intrinsic_call_status;
StructuredBuffer<uint4> x86_func_layout_record;
StructuredBuffer<uint> x86_func_layout_status;
StructuredBuffer<uint> x86_entry_inst_status;
StructuredBuffer<uint> x86_select_plan;
StructuredBuffer<uint> plan_status;

RWStructuredBuffer<uint> x86_planned_reloc_kind;
RWStructuredBuffer<uint> x86_planned_reloc_site_inst;
RWStructuredBuffer<uint> x86_planned_reloc_target_inst;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_PLAN_OK = 1u;
static const uint X86_SELECT_SHAPE_BRANCH = 4u;
static const uint X86_SELECT_SHAPE_CALL = 5u;
static const uint X86_RELOC_REL32 = 1u;
static const uint X86_RELOC_CALL_REL32 = 2u;
static const uint X86_ENTRY_STATUS_CALL_SITE_INST = 4u;
static const uint X86_ENTRY_STATUS_RELOC_COUNT = 5u;
static const uint X86_LAYOUT_STATUS_OWNER_FN = 4u;
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
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDX = 2u;
static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
static const uint X86_OP_MOD_I32 = 6u;
static const uint X86_CALL_ARG_VALUE_SCALAR = 1u;
static const uint X86_CALL_ARG_VALUE_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_VALUE_PARAM = 3u;
static const uint X86_CALL_ARG_EVAL_SCALAR_IMM = 1u;
static const uint X86_CALL_ARG_EVAL_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_EVAL_PARAM_REG = 3u;
static const uint X86_SELECT_PLAN_NESTED_CALL_NODE = 4u;
static const uint X86_INTRINSIC_CALLS_OK = 1u;
static const uint X86_INTRINSIC_TEXT_WRITE = 1u;
static const uint X86_INTRINSIC_TEXT_WRITE_CODE_ROWS = 5u;
static const uint X86_INTRINSIC_IF_TEXT_WRITE_CODE_ROWS = 14u;
static const uint X86_INTRINSIC_IF_THEN_TEXT_WRITE_CODE_ROWS = 8u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

void write_reloc(uint reloc_i, uint kind, uint site_inst, uint target_inst)
{
    x86_planned_reloc_kind[reloc_i] = kind;
    x86_planned_reloc_site_inst[reloc_i] = site_inst;
    x86_planned_reloc_target_inst[reloc_i] = target_inst;
}

bool plan_ok()
{
    return plan_status[0u] == X86_PLAN_OK && plan_status[1u] == 0u;
}

uint call_abi_base_row(uint call_node)
{
    return call_node * 2u;
}

uint call_arg_lookup_slot(uint call_node, uint ordinal)
{
    return call_node * X86_SYSV_MAX_INTEGER_ARGS + ordinal;
}

bool valid_node(uint node)
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

bool literal_or_unary_literal_expr(uint node)
{
    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_INT || form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return true;
    if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
    {
        uint operand = resolve_expr(expr_left(node));
        if (!valid_node(operand))
            return false;
        uint operand_form = expr_form(operand);
        return operand_form == HIR_EXPR_INT ||
               operand_form == HIR_EXPR_TRUE ||
               operand_form == HIR_EXPR_FALSE;
    }
    return false;
}

bool param_reg_expr(uint node, uint fn_node, out uint arg_reg)
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

bool param_expr(uint node, uint fn_node)
{
    uint arg_reg = INVALID;
    return param_reg_expr(node, fn_node, arg_reg);
}

bool resolved_non_param_name_expr(uint node, uint fn_node)
{
    node = resolve_expr(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint arg_reg = INVALID;
    return !param_reg_expr(node, fn_node, arg_reg);
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
    if (!valid_node(call_node))
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

uint compare_op_for_expr_form(uint form)
{
    if (form == HIR_EXPR_LT || form == HIR_EXPR_GT ||
        form == HIR_EXPR_LE || form == HIR_EXPR_GE ||
        form == HIR_EXPR_EQ || form == HIR_EXPR_NE)
        return 1u;
    return 0u;
}

bool value_to_eax_inst_count(uint node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    if (literal_or_unary_literal_expr(node) ||
        param_expr(node, fn_node) ||
        resolved_non_param_name_expr(node, fn_node))
    {
        inst_count = 1u;
        return true;
    }

    uint arg_reg = INVALID;
    if (expr_form(node) == HIR_EXPR_NEG &&
        param_reg_expr(expr_left(node), fn_node, arg_reg))
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
        if (ordinal > 2u)
            return false;
        inst_count = 1u;
        return true;
    }
    if (value_kind == X86_CALL_ARG_VALUE_BINARY_IMM && eval.x == X86_CALL_ARG_EVAL_BINARY_IMM)
    {
        if (ordinal > 1u || eval.w == X86_OP_MOD_I32)
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
                call_arg_count_for_call(call_node),
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

bool condition_compare_inst_count(uint node, uint fn_node, out uint inst_count)
{
    inst_count = 0u;
    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    if (compare_op_for_expr_form(expr_form(node)) != 0u)
    {
        uint left_count = 0u;
        if (!value_to_eax_inst_count(expr_left(node), fn_node, left_count))
            return false;

        uint right_reg = INVALID;
        if (!literal_or_unary_literal_expr(expr_right(node)) &&
            !resolved_non_param_name_expr(expr_right(node), fn_node) &&
            !param_reg_expr(expr_right(node), fn_node, right_reg))
            return false;
        if (right_reg == X86_REG_EDI)
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

bool terminal_if_record_at(
    uint key_node,
    out uint cond_node,
    out uint then_expr,
    out uint else_expr)
{
    cond_node = INVALID;
    then_expr = INVALID;
    else_expr = INVALID;
    if (!valid_node(key_node))
        return false;

    uint4 branch = x86_terminal_if_record[key_node];
    if (!valid_node(branch.x) || !valid_node(branch.y) ||
        !valid_node(branch.z) || !valid_node(branch.w))
        return false;

    cond_node = branch.y;
    then_expr = branch.z;
    else_expr = branch.w;
    return true;
}

bool flat_terminal_if_value_count(uint key_node, uint fn_node, out uint inst_count)
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

uint value_call_reloc_count(uint node, uint fn_node)
{
    uint inst_count = 0u;
    uint target_fn = INVALID;
    if (!call_value_to_eax_inst_count(node, fn_node, inst_count, target_fn))
        return 0u;

    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    return terminal_if_record_at(target_fn, cond_node, then_expr, else_expr) ? 3u : 1u;
}

bool write_flat_terminal_if_branch_relocs_only(
    uint first_reloc,
    uint key_node,
    uint fn_node,
    uint start_inst,
    uint common_ret_inst)
{
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

    uint else_start = start_inst + cond_count + 1u + then_count + 1u;
    if (else_start + else_count != common_ret_inst)
        return false;

    write_reloc(first_reloc, X86_RELOC_REL32, start_inst + cond_count, else_start);
    write_reloc(first_reloc + 1u, X86_RELOC_REL32, else_start - 1u, common_ret_inst);
    return true;
}

bool write_value_call_relocs(
    uint first_reloc,
    uint value_node,
    uint fn_node,
    uint start_inst)
{
    uint call_inst_count = 0u;
    uint target_fn = INVALID;
    if (!call_value_to_eax_inst_count(value_node, fn_node, call_inst_count, target_fn))
        return false;

    uint target_inst = x86_func_layout_record[target_fn].x;
    if (target_inst == INVALID)
        return false;

    write_reloc(
        first_reloc,
        X86_RELOC_CALL_REL32,
        start_inst + call_inst_count - 1u,
        target_inst);

    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (terminal_if_record_at(target_fn, cond_node, then_expr, else_expr))
    {
        uint4 layout = x86_func_layout_record[target_fn];
        if (layout.x == INVALID || layout.y == 0u)
            return false;
        return write_flat_terminal_if_branch_relocs_only(
            first_reloc + 1u,
            target_fn,
            target_fn,
            layout.x,
            layout.x + layout.y - 1u);
    }

    return true;
}

bool write_flat_terminal_if_relocs(
    uint first_reloc,
    uint key_node,
    uint fn_node,
    uint start_inst,
    uint common_ret_inst)
{
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

    uint then_start = start_inst + cond_count + 1u;
    uint else_start = then_start + then_count + 1u;
    if (else_start + else_count != common_ret_inst)
        return false;

    if (!write_flat_terminal_if_branch_relocs_only(
            first_reloc,
            key_node,
            fn_node,
            start_inst,
            common_ret_inst))
        return false;

    uint then_reloc_count = value_call_reloc_count(then_expr, fn_node);
    if (then_reloc_count != 0u &&
        !write_value_call_relocs(first_reloc + 2u, then_expr, fn_node, then_start))
        return false;

    uint else_reloc_count = value_call_reloc_count(else_expr, fn_node);
    if (else_reloc_count != 0u &&
        !write_value_call_relocs(
            first_reloc + 2u + then_reloc_count,
            else_expr,
            fn_node,
            else_start))
        return false;

    return true;
}

bool write_terminal_if_relocs(uint first_reloc, uint target_fn)
{
    if (!valid_node(target_fn))
        return false;

    uint4 layout = x86_func_layout_record[target_fn];
    if (layout.x == INVALID || layout.y == 0u)
        return false;

    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (!terminal_if_record_at(target_fn, cond_node, then_expr, else_expr))
        return false;

    uint cond_count = 0u;
    uint then_count = 0u;
    uint else_count = 0u;
    if (!condition_compare_inst_count(cond_node, target_fn, cond_count) ||
        !value_to_eax_inst_count(then_expr, target_fn, then_count))
        return false;
    bool else_is_value = value_to_eax_inst_count(else_expr, target_fn, else_count);
    bool else_is_nested = !else_is_value &&
                          flat_terminal_if_value_count(else_expr, target_fn, else_count);
    if (!else_is_value && !else_is_nested)
        return false;

    uint common_ret_inst = layout.x + layout.y - 1u;
    uint else_start = layout.x + cond_count + 1u + then_count + 1u;
    if (else_start + else_count != common_ret_inst)
        return false;

    write_reloc(first_reloc, X86_RELOC_REL32, layout.x + cond_count, else_start);
    write_reloc(first_reloc + 1u, X86_RELOC_REL32, else_start - 1u, common_ret_inst);
    uint then_reloc_count = value_call_reloc_count(then_expr, target_fn);
    if (then_reloc_count != 0u &&
        !write_value_call_relocs(
            first_reloc + 2u,
            then_expr,
            target_fn,
            layout.x + cond_count + 1u))
        return false;
    if (else_is_nested)
        return write_flat_terminal_if_relocs(
            first_reloc + 2u + then_reloc_count,
            else_expr,
            target_fn,
            else_start,
            common_ret_inst);
    uint else_reloc_count = value_call_reloc_count(else_expr, target_fn);
    if (else_reloc_count != 0u)
        return write_value_call_relocs(
            first_reloc + 2u + then_reloc_count,
            else_expr,
            target_fn,
            else_start);
    return true;
}

bool top_level_text_write_call(uint call_node, uint fn_node)
{
    if (!valid_active_node(call_node))
        return false;

    uint4 record = x86_intrinsic_call_record[call_node];
    return record.x == fn_node &&
           record.y == call_node &&
           record.w == X86_INTRINSIC_TEXT_WRITE &&
           !has_if_ancestor_before_function(call_node);
}

bool branch_text_write_call(uint block_node, uint fn_node, out uint call_node)
{
    call_node = INVALID;
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
        count += 1u;
        call_node = node;
    }

    return count == 1u;
}

uint write_entry_output_relocs(uint first_reloc, uint fn_node)
{
    if (!valid_active_node(fn_node) || !intrinsic_calls_ok())
        return INVALID;

    uint4 layout = x86_func_layout_record[fn_node];
    if (layout.x == INVALID || layout.y == 0u)
        return INVALID;

    uint code_cursor = layout.x;
    uint reloc_cursor = first_reloc;
    [loop]
    for (uint node = 0u; node < gParams.n_hir_nodes; node += 1u)
    {
        if (top_level_text_write_call(node, fn_node))
        {
            code_cursor += X86_INTRINSIC_TEXT_WRITE_CODE_ROWS;
            continue;
        }

        if (hir_kind[node] != HIR_IF_STMT ||
            stmt_record_slot(node, 0u) != STMT_RECORD_KIND_IF ||
            owning_function_node(node) != fn_node ||
            has_if_ancestor_before_function(node))
            continue;

        uint then_block = stmt_record_slot(node, 2u);
        uint else_block = stmt_record_slot(node, 3u);
        uint then_call = INVALID;
        uint else_call = INVALID;
        if (!branch_text_write_call(then_block, fn_node, then_call))
            return INVALID;

        uint jcc_site = code_cursor + 2u;
        uint then_start = code_cursor + 3u;
        bool has_else = branch_text_write_call(else_block, fn_node, else_call);
        if (has_else)
        {
            uint jmp_site = then_start + X86_INTRINSIC_TEXT_WRITE_CODE_ROWS;
            uint else_start = jmp_site + 1u;
            uint after_else = else_start + X86_INTRINSIC_TEXT_WRITE_CODE_ROWS;
            write_reloc(reloc_cursor, X86_RELOC_REL32, jcc_site, else_start);
            write_reloc(reloc_cursor + 1u, X86_RELOC_REL32, jmp_site, after_else);
            reloc_cursor += 2u;
            code_cursor += X86_INTRINSIC_IF_TEXT_WRITE_CODE_ROWS;
        }
        else
        {
            uint after_then = then_start + X86_INTRINSIC_TEXT_WRITE_CODE_ROWS;
            write_reloc(reloc_cursor, X86_RELOC_REL32, jcc_site, after_then);
            reloc_cursor += 1u;
            code_cursor += X86_INTRINSIC_IF_THEN_TEXT_WRITE_CODE_ROWS;
        }
    }

    return reloc_cursor - first_reloc;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (linear_dispatch_id(tid) != 0u || !plan_ok())
        return;

    uint owner_fn = x86_func_layout_status[X86_LAYOUT_STATUS_OWNER_FN];
    uint entry_reloc_count = x86_entry_inst_status[X86_ENTRY_STATUS_RELOC_COUNT];
    uint reloc_base = 0u;
    if (entry_reloc_count != 0u)
    {
        uint wrote = write_entry_output_relocs(0u, owner_fn);
        if (wrote == INVALID)
            return;
        reloc_base = wrote;
    }

    uint shape = x86_select_plan[0u];
    if (shape == X86_SELECT_SHAPE_BRANCH)
    {
        write_reloc(reloc_base, X86_RELOC_REL32, 2u, 5u);
        write_reloc(reloc_base + 1u, X86_RELOC_REL32, 4u, 6u);
    }
    else if (shape == X86_SELECT_SHAPE_CALL)
    {
        uint return_vreg = x86_select_plan[3u] != INVALID ?
                           x86_select_plan[3u] :
                           x86_return_vreg[0u];
        uint call_node = x86_vreg_value[return_vreg];
        uint4 call_abi = call_node != INVALID && call_node < gParams.n_hir_nodes ?
                         x86_call_abi_record[call_abi_base_row(call_node)] :
                         uint4(INVALID, INVALID, 0u, INVALID);
        uint target_fn = call_abi.y;
        uint site_inst = x86_entry_inst_status[X86_ENTRY_STATUS_CALL_SITE_INST];
        uint target_inst = target_fn != INVALID && target_fn < gParams.n_hir_nodes ?
                           x86_func_layout_record[target_fn].x :
                           INVALID;
        if (site_inst != INVALID && target_inst != INVALID)
            write_reloc(reloc_base, X86_RELOC_CALL_REL32, site_inst, target_inst);
        if (!write_terminal_if_relocs(reloc_base + 1u, target_fn))
        {
            uint nested_call_node = x86_select_plan[X86_SELECT_PLAN_NESTED_CALL_NODE];
            uint4 target_layout = valid_node(target_fn) ?
                                  x86_func_layout_record[target_fn] :
                                  uint4(INVALID, 0u, 0u, INVALID);
            if (valid_node(nested_call_node) && target_layout.x != INVALID)
                write_value_call_relocs(
                    reloc_base + 1u,
                    nested_call_node,
                    target_fn,
                    target_layout.x);
        }
    }
}
