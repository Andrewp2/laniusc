// Shared helpers for the small HIR-driven WASM body pipeline.
//
// This handles the scalar entrypoint slice the module wrapper already supports:
// one exported main function returning a constant i32 expression. Other shapes
// continue to fail closed with the stable WASM backend boundary. Body emission
// uses per-node fragment records followed by prefix-scan/scatter passes.

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
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint2> wasm_const_value_record;
StructuredBuffer<uint> body_let_init_expr_by_decl_token;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_context_stmt_node;
StructuredBuffer<uint> hir_call_arg_start;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_arg_ordinal;
StructuredBuffer<uint> hir_nearest_enclosing_control_node;
StructuredBuffer<uint> call_intrinsic_tag;

static const uint INVALID = 0xffffffffu;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;

static const uint ENTRYPOINT_MAIN = 1u;
static const uint HIR_FN = 3u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_NONE = 0u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NONE = 0u;
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

static const uint WASM_CONST_VALUE_LITERAL = 1u;
static const uint INTRINSIC_TEXT_WRITE = 1u;
static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I64_CONST = 0x42u;
static const uint WASM_CALL = 0x10u;
static const uint WASM_END = 0x0bu;
static const uint BODY_FRAGMENT_NONE = 0u;
static const uint BODY_FRAGMENT_LOCAL_DECL_COUNT = 1u;
static const uint BODY_FRAGMENT_PRINT_I64 = 2u;
static const uint BODY_FRAGMENT_RETURN_I32 = 3u;
static const uint MAX_CONST_EVAL_STACK = 16u;
static const uint MAX_CONST_EVAL_STEPS = 48u;
static const uint MAX_CONST_CONTROL_DEPTH = 8u;
static const uint MAX_PATH_SEGMENTS = 9u;
static const uint DISPATCH_X_STRIDE = 16776960u;

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

bool valid_token_end(uint token)
{
    return token != INVALID && token <= gParams.n_tokens;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_path(uint path_i)
{
    return path_i != INVALID && path_i < active_path_count();
}

bool valid_span_node(uint node)
{
    return valid_node(node) &&
           valid_token(hir_token_pos[node]) &&
           valid_token_end(hir_token_end[node]) &&
           hir_token_pos[node] < hir_token_end[node];
}

bool node_span_contains(uint owner, uint node)
{
    return valid_span_node(owner) &&
           valid_span_node(node) &&
           hir_token_pos[owner] <= hir_token_pos[node] &&
           hir_token_end[node] <= hir_token_end[owner];
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
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint resolve_expr_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    if (valid_node(root))
        return root;
    return expr_form(node) == HIR_EXPR_FORWARD ? INVALID : node;
}

uint path_node_for_callee(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;
    if (hir_kind[callee_node] == HIR_PATH_EXPR)
        return callee_node;
    if (hir_kind[callee_node] == HIR_NAME_EXPR)
    {
        uint child = first_child[callee_node];
        if (valid_node(child) && hir_kind[child] == HIR_PATH_EXPR)
            return child;
    }
    return INVALID;
}

uint path_leaf_token_for_callee(uint callee_node)
{
    uint path_node = path_node_for_callee(callee_node);
    if (!valid_node(path_node))
        return INVALID;

    uint path_i = path_id_by_owner_hir[path_node];
    if (!valid_path(path_i))
        return INVALID;

    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (count == 0u)
        return INVALID;

    uint slot = path_segment_base[path_i] + count - 1u;
    if (slot >= gParams.n_tokens * MAX_PATH_SEGMENTS)
        return INVALID;

    uint token = path_segment_token[slot];
    return valid_token(token) ? token : INVALID;
}

uint node_enclosing_fn_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return INVALID;
    uint encoded_fn = enclosing_fn[token];
    return encoded_fn == 0u ? INVALID : encoded_fn - 1u;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint raw_callee_node = hir_call_callee_node[call_node];
    uint path_leaf = path_leaf_token_for_callee(raw_callee_node);
    if (valid_token(path_leaf))
        return path_leaf;

    uint callee_node = resolve_expr_node(raw_callee_node);
    if (!valid_node(callee_node))
        return INVALID;
    uint callee_token = expr_record_slot(callee_node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

bool statement_position_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;
    uint context = hir_call_context_stmt_node[call_node];
    return valid_node(context) && hir_kind[context] == HIR_STMT;
}

bool print_call_node(uint call_node)
{
    uint callee_token = call_callee_token(call_node);
    return valid_token(callee_token) &&
           statement_position_call(call_node) &&
           call_intrinsic_tag[callee_token] == INTRINSIC_TEXT_WRITE &&
           hir_call_arg_count[call_node] == 1u;
}

uint call_arg0_node(uint call_node)
{
    if (!print_call_node(call_node))
        return INVALID;

    uint arg = hir_call_arg_start[call_node];
    if (valid_node(arg) &&
        hir_call_arg_parent_call[arg] == call_node &&
        hir_call_arg_ordinal[arg] == 0u)
    {
        return arg;
    }
    return INVALID;
}

bool let_initializer_for_decl_token(uint decl_token, out uint init_expr)
{
    init_expr = INVALID;
    if (!valid_token(decl_token))
        return false;

    init_expr = body_let_init_expr_by_decl_token[decl_token];
    return valid_node(init_expr) && hir_kind[init_expr] == HIR_EXPR;
}

bool name_const_record_value(uint name_node, out uint value)
{
    value = 0u;
    uint name_token = expr_record_slot(name_node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    uint2 record = wasm_const_value_record[decl_token];
    if (record.x != WASM_CONST_VALUE_LITERAL)
        return false;
    value = record.y;
    return true;
}

bool name_let_initializer_expr(uint name_node, out uint init_expr)
{
    init_expr = INVALID;
    uint name_token = expr_record_slot(name_node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    return let_initializer_for_decl_token(decl_token, init_expr);
}

bool const_atom_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr_node(node);
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
        return name_const_record_value(node, value);
    }
    return false;
}

bool unary_const_value(uint form, uint inner, out uint value)
{
    if (form == HIR_EXPR_NEG)
    {
        value = 0u - inner;
        return true;
    }
    if (form == HIR_EXPR_NOT)
    {
        value = inner == 0u ? 1u : 0u;
        return true;
    }
    value = 0u;
    return false;
}

bool binary_const_value(uint form, uint left, uint right, out uint value)
{
    value = 0u;
    if (form == HIR_EXPR_EQ) { value = left == right ? 1u : 0u; return true; }
    if (form == HIR_EXPR_NE) { value = left != right ? 1u : 0u; return true; }
    if (form == HIR_EXPR_LT) { value = int(left) < int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_GT) { value = int(left) > int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_LE) { value = int(left) <= int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_GE) { value = int(left) >= int(right) ? 1u : 0u; return true; }
    if (form == HIR_EXPR_ADD) { value = left + right; return true; }
    if (form == HIR_EXPR_SUB) { value = left - right; return true; }
    if (form == HIR_EXPR_MUL) { value = left * right; return true; }
    if (form == HIR_EXPR_AND) { value = left != 0u && right != 0u ? 1u : 0u; return true; }
    if (form == HIR_EXPR_OR) { value = left != 0u || right != 0u ? 1u : 0u; return true; }
    if (form == HIR_EXPR_BIT_OR) { value = left | right; return true; }
    if (form == HIR_EXPR_BIT_XOR) { value = left ^ right; return true; }
    if (form == HIR_EXPR_BIT_AND) { value = left & right; return true; }
    if (form == HIR_EXPR_SHL) { value = left << min(right, 31u); return true; }
    if (form == HIR_EXPR_SHR) { value = uint(int(left) >> min(right, 31u)); return true; }
    if (right == 0u)
        return false;
    if (form == HIR_EXPR_DIV) { value = uint(int(left) / int(right)); return true; }
    if (form == HIR_EXPR_MOD) { value = uint(int(left) % int(right)); return true; }
    return false;
}

bool push_eval_node(
    inout uint nodes[MAX_CONST_EVAL_STACK],
    inout uint states[MAX_CONST_EVAL_STACK],
    inout uint sp,
    uint node)
{
    if (sp >= MAX_CONST_EVAL_STACK)
        return false;
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    nodes[sp] = node;
    states[sp] = 0u;
    sp += 1u;
    return true;
}

bool const_expr_value(uint root_node, out uint value)
{
    value = 0u;

    uint nodes[MAX_CONST_EVAL_STACK];
    uint states[MAX_CONST_EVAL_STACK];
    uint values[MAX_CONST_EVAL_STACK];
    uint sp = 0u;
    uint vsp = 0u;
    if (!push_eval_node(nodes, states, sp, root_node))
        return false;

    for (uint step = 0u; step < MAX_CONST_EVAL_STEPS; step += 1u)
    {
        if (sp == 0u)
            break;

        uint node = nodes[sp - 1u];
        uint state = states[sp - 1u];
        uint form = expr_form(node);
        uint atom = 0u;
        if (state == 0u && const_atom_value(node, atom))
        {
            if (vsp >= MAX_CONST_EVAL_STACK)
                return false;
            values[vsp] = atom;
            vsp += 1u;
            sp -= 1u;
            continue;
        }
        if (state == 0u && form == HIR_EXPR_NAME)
        {
            uint init_expr = INVALID;
            if (!name_let_initializer_expr(node, init_expr))
                return false;
            nodes[sp - 1u] = resolve_expr_node(init_expr);
            states[sp - 1u] = 0u;
            continue;
        }

        if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
        {
            if (state == 0u)
            {
                states[sp - 1u] = 1u;
                if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                    return false;
                continue;
            }
            if (vsp < 1u)
                return false;
            uint inner = values[vsp - 1u];
            vsp -= 1u;
            uint result = 0u;
            if (!unary_const_value(form, inner, result))
                return false;
            values[vsp] = result;
            vsp += 1u;
            sp -= 1u;
            continue;
        }

        bool binary =
            form == HIR_EXPR_EQ || form == HIR_EXPR_NE ||
            form == HIR_EXPR_LT || form == HIR_EXPR_GT ||
            form == HIR_EXPR_LE || form == HIR_EXPR_GE ||
            form == HIR_EXPR_ADD || form == HIR_EXPR_SUB ||
            form == HIR_EXPR_MUL || form == HIR_EXPR_AND ||
            form == HIR_EXPR_OR || form == HIR_EXPR_MOD ||
            form == HIR_EXPR_DIV || form == HIR_EXPR_BIT_OR ||
            form == HIR_EXPR_BIT_XOR || form == HIR_EXPR_BIT_AND ||
            form == HIR_EXPR_SHL || form == HIR_EXPR_SHR;
        if (!binary)
            return false;

        if (state == 0u)
        {
            states[sp - 1u] = 1u;
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_LEFT)))
                return false;
            continue;
        }
        if (state == 1u)
        {
            states[sp - 1u] = 2u;
            if (!push_eval_node(nodes, states, sp, expr_record_slot(node, EXPR_RECORD_RIGHT)))
                return false;
            continue;
        }
        if (vsp < 2u)
            return false;
        uint right = values[vsp - 1u];
        uint left = values[vsp - 2u];
        vsp -= 2u;
        uint result = 0u;
        if (!binary_const_value(form, left, right, result))
            return false;
        values[vsp] = result;
        vsp += 1u;
        sp -= 1u;
    }

    if (sp != 0u || vsp != 1u)
        return false;
    value = values[0u];
    return true;
}

bool if_condition_value(uint if_node, out uint condition)
{
    condition = 0u;
    if (!valid_node(if_node) ||
        hir_kind[if_node] != HIR_IF_STMT ||
        stmt_record_slot(if_node, 0u) != STMT_RECORD_KIND_IF)
        return false;

    uint condition_node = stmt_record_slot(if_node, 1u);
    return valid_node(condition_node) && const_expr_value(condition_node, condition);
}

bool constant_if_selects_node(uint if_node, uint node, out bool selected)
{
    selected = false;
    uint condition = 0u;
    if (!if_condition_value(if_node, condition))
        return false;

    uint then_block = stmt_record_slot(if_node, 2u);
    uint else_block = stmt_record_slot(if_node, 3u);
    if (condition != 0u)
    {
        selected = node_span_contains(then_block, node);
        return true;
    }

    selected = valid_node(else_block) && node_span_contains(else_block, node);
    return true;
}

bool node_enabled_by_constant_if_chain(uint node)
{
    uint control = valid_node(node) ? hir_nearest_enclosing_control_node[node] : INVALID;
    for (uint depth = 0u; depth < MAX_CONST_CONTROL_DEPTH; depth += 1u)
    {
        if (!valid_node(control))
            return true;
        if (hir_kind[control] != HIR_IF_STMT)
            return false;

        bool selected = false;
        if (!constant_if_selects_node(control, node, selected) || !selected)
            return false;

        control = hir_nearest_enclosing_control_node[control];
    }
    return false;
}

uint i32_sleb_len(uint value)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (done)
            return i + 1u;
    }
    return 5u;
}

uint i32_sleb_byte(uint value, uint byte_i)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (!done)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (done)
            return 0u;
    }
    return 0u;
}

bool print_call_value_and_len(uint call_node, out uint value, out uint len)
{
    value = 0u;
    len = 0u;
    uint arg_node = call_arg0_node(call_node);
    if (!valid_node(arg_node) || !const_expr_value(arg_node, value))
        return false;

    len = 1u + i32_sleb_len(value) + 2u;
    return true;
}

bool body_fragment_for_node(
    uint node,
    uint main_token,
    uint return_token,
    uint return_value,
    out uint token_i,
    out uint4 fragment_meta,
    out uint fragment_len)
{
    token_i = INVALID;
    fragment_meta = uint4(BODY_FRAGMENT_NONE, 0u, 0u, INVALID);
    fragment_len = 0u;
    if (!valid_node(node))
        return false;
    if (!node_enabled_by_constant_if_chain(node))
        return false;

    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return false;

    if (hir_kind[node] == HIR_FN &&
        fn_entrypoint_tag[node] == ENTRYPOINT_MAIN &&
        token == main_token)
    {
        token_i = token;
        fragment_len = 1u;
        fragment_meta = uint4(
            BODY_FRAGMENT_LOCAL_DECL_COUNT,
            0u,
            fragment_len,
            main_token);
        return true;
    }

    if (node_enclosing_fn_token(node) != main_token)
        return false;

    if (hir_kind[node] == HIR_RETURN_STMT && token == return_token)
    {
        token_i = token;
        fragment_len = 1u + i32_sleb_len(return_value) + 1u;
        fragment_meta = uint4(
            BODY_FRAGMENT_RETURN_I32,
            return_value,
            fragment_len,
            return_token);
        return true;
    }

    if (hir_kind[node] == HIR_CALL_EXPR &&
        token < return_token &&
        print_call_node(node))
    {
        uint value = 0u;
        uint len = 0u;
        if (!print_call_value_and_len(node, value, len))
            return false;
        token_i = token;
        fragment_len = len;
        fragment_meta = uint4(
            BODY_FRAGMENT_PRINT_I64,
            value,
            fragment_len,
            token_i);
        return true;
    }

    return false;
}
