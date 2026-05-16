// Record-driven multi-function WASM module lowering for scalar HIR functions.
//
// This bounded pass consumes HIR, parameter, expression, call, intrinsic, and
// resolver records. It does not read token records, source bytes, token
// spelling, helper names, or function-body text shapes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> fn_entrypoint_tag;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_MODULE_OUTPUT_TARGET_LIMIT = 512u;

static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_CALL_EXPR = 19u;
static const uint ENTRYPOINT_MAIN = 1u;
static const uint INTRINSIC_PRINT = 1u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND = 0u;
static const uint STMT_RECORD_A = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

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

static const uint MAX_EXPR_STACK = 96u;
static const uint MAX_CALL_ARGS = 8u;
static const uint MAX_PRINTS = 16u;
static const uint ERR_MULTI_FUNCTION_MODULE_BASE = 700u;

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

uint stmt_record(uint node, uint slot)
{
    return valid_node(node) ? hir_stmt_record[node * STMT_RECORD_STRIDE + slot] : INVALID;
}

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return expr_slot(node, EXPR_RECORD_LEFT);
}

uint expr_right(uint node)
{
    return expr_slot(node, EXPR_RECORD_RIGHT);
}

uint expr_value_token(uint node)
{
    return expr_slot(node, EXPR_RECORD_VALUE_TOKEN);
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

uint function_count()
{
    uint count = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] == HIR_FN && valid_token(hir_token_pos[node]))
            count += 1u;
    }
    return count;
}

uint nth_function_node(uint ordinal)
{
    uint seen = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] != HIR_FN || !valid_token(hir_token_pos[node]))
            continue;
        if (seen == ordinal)
            return node;
        seen += 1u;
    }
    return INVALID;
}

uint function_ordinal(uint fn_node)
{
    uint ordinal = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (node == fn_node)
            return ordinal;
        if (hir_kind[node] == HIR_FN && valid_token(hir_token_pos[node]))
            ordinal += 1u;
    }
    return INVALID;
}

uint next_function_pos(uint fn_node)
{
    uint start = hir_token_pos[fn_node];
    uint best = INVALID;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        uint pos = hir_token_pos[node];
        if (hir_kind[node] == HIR_FN && pos != INVALID && pos > start &&
            (best == INVALID || pos < best))
            best = pos;
    }
    return best;
}

bool node_in_function(uint node, uint fn_node)
{
    if (!valid_node(node) || !valid_node(fn_node))
        return false;
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (cur == fn_node)
            return true;
        if (!valid_node(cur))
            return false;
        cur = parent[cur];
    }
    return false;
}

uint function_node_for_decl_token(uint decl_token)
{
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] == HIR_FN && hir_token_pos[node] == decl_token)
            return node;
    }
    return INVALID;
}

uint wasm_function_index_for_decl_token(uint decl_token)
{
    uint fn_node = function_node_for_decl_token(decl_token);
    uint ordinal = valid_node(fn_node) ? function_ordinal(fn_node) : INVALID;
    return ordinal == INVALID ? INVALID : ordinal + 1u;
}

uint function_param_count(uint fn_node)
{
    uint count = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        uint4 record = hir_param_record[node];
        if (record.x == fn_node)
            count = max(count, record.y + 1u);
    }
    return count;
}

uint param_index_for_name(uint fn_node, uint decl_token, uint use_token)
{
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        uint4 record = hir_param_record[node];
        if (record.x != fn_node)
            continue;
        if (record.z == decl_token)
            return record.y;
    }
    return INVALID;
}

uint find_main_fn_node()
{
    uint found = INVALID;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] != HIR_FN)
            continue;
        uint decl_token = hir_token_pos[node];
        bool tagged = fn_entrypoint_tag[node] == ENTRYPOINT_MAIN ||
                      (valid_token(decl_token) && fn_entrypoint_tag[decl_token] == ENTRYPOINT_MAIN);
        if (!tagged)
            continue;
        if (found != INVALID)
            return INVALID;
        found = node;
    }
    return found;
}

uint find_return_node(uint fn_node)
{
    uint found = INVALID;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] != HIR_RETURN_STMT || !node_in_function(node, fn_node))
            continue;
        if (stmt_record(node, STMT_RECORD_KIND) != STMT_RECORD_KIND_RETURN)
            continue;
        if (found != INVALID)
            return INVALID;
        found = node;
    }
    return found;
}

void put_module(uint pos, uint value, bool write, uint target)
{
    if (write && pos < gParams.out_capacity && pos == target)
        out_words[pos] = value & 0xffu;
}

void put_byte(inout uint cursor, uint value, bool write, uint target)
{
    put_module(cursor, value, write, target);
    cursor += 1u;
}

void put_body_byte(inout uint cursor, uint base, uint value, bool write, uint target)
{
    put_module(base + cursor, value, write, target);
    cursor += 1u;
}

uint u32_leb_size(uint value)
{
    uint size = 1u;
    [loop]
    for (uint guard = 0u; guard < 5u && value >= 128u; guard += 1u)
    {
        value = value >> 7u;
        size += 1u;
    }
    return size;
}

void put_u32_leb(inout uint cursor, uint value, bool write, uint target)
{
    [loop]
    for (uint guard = 0u; guard < 5u; guard += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write, target);
        if (value == 0u)
            break;
    }
}

void put_u32_leb5(inout uint cursor, uint value, bool write, uint target)
{
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = (value >> (i * 7u)) & 0x7fu;
        if (i < 4u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write, target);
    }
}

void put_body_u32_leb(inout uint cursor, uint base, uint value, bool write, uint target)
{
    [loop]
    for (uint guard = 0u; guard < 5u; guard += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        put_body_byte(cursor, base, byte_value, write, target);
        if (value == 0u)
            break;
    }
}

void put_body_u32_leb5(inout uint cursor, uint base, uint value, bool write, uint target)
{
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = (value >> (i * 7u)) & 0x7fu;
        if (i < 4u)
            byte_value |= 0x80u;
        put_body_byte(cursor, base, byte_value, write, target);
    }
}

void emit_i32_const(inout uint cursor, uint base, uint value, bool write, uint target)
{
    put_body_byte(cursor, base, 0x41u, write, target);
    put_body_u32_leb5(cursor, base, value, write, target);
}

void emit_local_get(inout uint cursor, uint base, uint local_i, bool write, uint target)
{
    put_body_byte(cursor, base, 0x20u, write, target);
    put_body_u32_leb(cursor, base, local_i, write, target);
}

void emit_expr_op(inout uint cursor, uint base, uint form, bool write, uint target)
{
    if (form == HIR_EXPR_NOT)
        put_body_byte(cursor, base, 0x45u, write, target);
    else if (form == HIR_EXPR_NEG || form == HIR_EXPR_SUB)
        put_body_byte(cursor, base, 0x6bu, write, target);
    else if (form == HIR_EXPR_MUL)
        put_body_byte(cursor, base, 0x6cu, write, target);
    else if (form == HIR_EXPR_DIV)
        put_body_byte(cursor, base, 0x6du, write, target);
    else if (form == HIR_EXPR_MOD)
        put_body_byte(cursor, base, 0x6fu, write, target);
    else if (form == HIR_EXPR_LT)
        put_body_byte(cursor, base, 0x48u, write, target);
    else if (form == HIR_EXPR_GT)
        put_body_byte(cursor, base, 0x4au, write, target);
    else if (form == HIR_EXPR_LE)
        put_body_byte(cursor, base, 0x4cu, write, target);
    else if (form == HIR_EXPR_GE)
        put_body_byte(cursor, base, 0x4eu, write, target);
    else if (form == HIR_EXPR_EQ)
        put_body_byte(cursor, base, 0x46u, write, target);
    else if (form == HIR_EXPR_NE)
        put_body_byte(cursor, base, 0x47u, write, target);
    else if (form == HIR_EXPR_AND || form == HIR_EXPR_BIT_AND)
        put_body_byte(cursor, base, 0x71u, write, target);
    else if (form == HIR_EXPR_OR || form == HIR_EXPR_BIT_OR)
        put_body_byte(cursor, base, 0x72u, write, target);
    else if (form == HIR_EXPR_BIT_XOR)
        put_body_byte(cursor, base, 0x73u, write, target);
    else if (form == HIR_EXPR_SHL)
        put_body_byte(cursor, base, 0x74u, write, target);
    else if (form == HIR_EXPR_SHR)
        put_body_byte(cursor, base, 0x75u, write, target);
    else
        put_body_byte(cursor, base, 0x6au, write, target);
}

uint callee_token_for_call(uint call_node)
{
    uint callee_node = resolve_expr(hir_call_callee_node[call_node]);
    return valid_node(callee_node) ? expr_value_token(callee_node) : INVALID;
}

uint call_arg_node(uint call_node, uint ordinal)
{
    uint seen = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_call_arg_parent_call[node] != call_node)
            continue;
        if (seen == ordinal)
            return node;
        seen += 1u;
    }
    return INVALID;
}

uint call_arg_count_for_call(uint call_node)
{
    uint count = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_call_arg_parent_call[node] == call_node)
            count += 1u;
    }
    return count;
}

uint call_node_for_callee_expr(uint callee_expr, uint fn_node)
{
    uint resolved_callee = resolve_expr(callee_expr);
    if (!valid_node(resolved_callee))
        return INVALID;
    uint target_token = expr_value_token(resolved_callee);
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] != HIR_CALL_EXPR)
            continue;
        uint call_callee_raw = hir_call_callee_node[node];
        uint call_callee = resolve_expr(call_callee_raw);
        if (call_callee == resolved_callee)
            return node;
        uint call_token = valid_node(call_callee) ? expr_value_token(call_callee) : INVALID;
        if (valid_token(target_token) && call_token == target_token &&
            node_in_function(call_callee, fn_node))
            return node;
    }
    return INVALID;
}

bool push_expr(inout uint stack_top, inout uint node_stack[MAX_EXPR_STACK],
               inout uint state_stack[MAX_EXPR_STACK], uint node, uint state)
{
    if (stack_top >= MAX_EXPR_STACK || !valid_node(node))
        return false;
    node_stack[stack_top] = node;
    state_stack[stack_top] = state;
    stack_top += 1u;
    return true;
}

bool emit_expr_node(inout uint cursor, uint base, uint root, uint fn_node, out uint expr_fail,
                    bool write, uint target)
{
    expr_fail = 0u;
    uint node_stack[MAX_EXPR_STACK];
    uint state_stack[MAX_EXPR_STACK];
    uint stack_top = 0u;
    if (!push_expr(stack_top, node_stack, state_stack, root, 0u))
    {
        expr_fail = 1u;
        return false;
    }

    [loop]
    for (uint guard = 0u; guard < 384u; guard += 1u)
    {
        if (stack_top == 0u)
            return true;
        stack_top -= 1u;
        uint node = resolve_expr(node_stack[stack_top]);
        uint state = state_stack[stack_top];
        if (!valid_node(node))
        {
            expr_fail = 2u;
            return false;
        }
        if (state == 0u)
        {
            uint call_node = call_node_for_callee_expr(node, fn_node);
            if (valid_node(call_node))
                node = call_node;
        }

        if (state == 1u)
        {
            emit_expr_op(cursor, base, expr_form(node), write, target);
            continue;
        }
        if (state == 2u)
        {
            uint callee_token = callee_token_for_call(node);
            uint decl_token = valid_token(callee_token) ? call_fn_index[callee_token] : INVALID;
            uint wasm_index = wasm_function_index_for_decl_token(decl_token);
            if (wasm_index == INVALID)
            {
                expr_fail = 3u;
                return false;
            }
            put_body_byte(cursor, base, 0x10u, write, target);
            put_body_u32_leb(cursor, base, wasm_index, write, target);
            continue;
        }

        uint form = expr_form(node);
        if (form == HIR_EXPR_INT)
        {
            emit_i32_const(cursor, base, hir_expr_int_value[node], write, target);
            continue;
        }
        if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        {
            emit_i32_const(cursor, base, form == HIR_EXPR_TRUE ? 1u : 0u, write, target);
            continue;
        }
        if (form == HIR_EXPR_NAME)
        {
            uint value_token = expr_value_token(node);
            uint decl_token = valid_token(value_token) ? visible_decl[value_token] : INVALID;
            uint local_i = param_index_for_name(fn_node, decl_token, value_token);
            if (local_i == INVALID)
            {
                expr_fail = 1000u + (valid_token(value_token) ? value_token : 999u);
                return false;
            }
            emit_local_get(cursor, base, local_i, write, target);
            continue;
        }
        if (hir_kind[node] == HIR_CALL_EXPR)
        {
            uint arg_count = call_arg_count_for_call(node);
            if (arg_count > MAX_CALL_ARGS)
            {
                expr_fail = 5u;
                return false;
            }
            if (!push_expr(stack_top, node_stack, state_stack, node, 2u))
            {
                expr_fail = 6u;
                return false;
            }
            [loop]
            for (uint reverse_i = 0u; reverse_i < MAX_CALL_ARGS; reverse_i += 1u)
            {
                if (reverse_i >= arg_count)
                    break;
                uint ordinal = arg_count - 1u - reverse_i;
                uint arg_node = call_arg_node(node, ordinal);
                if (!push_expr(stack_top, node_stack, state_stack, arg_node, 0u))
                {
                    expr_fail = 7u;
                    return false;
                }
            }
            continue;
        }
        if (form == HIR_EXPR_NOT)
        {
            if (!push_expr(stack_top, node_stack, state_stack, node, 1u) ||
                !push_expr(stack_top, node_stack, state_stack, expr_left(node), 0u))
            {
                expr_fail = 8u;
                return false;
            }
            continue;
        }
        if (form == HIR_EXPR_NEG)
        {
            emit_i32_const(cursor, base, 0u, write, target);
            if (!push_expr(stack_top, node_stack, state_stack, node, 1u) ||
                !push_expr(stack_top, node_stack, state_stack, expr_left(node), 0u))
            {
                expr_fail = 9u;
                return false;
            }
            continue;
        }
        if (form >= HIR_EXPR_EQ && form <= HIR_EXPR_SHR)
        {
            if (!push_expr(stack_top, node_stack, state_stack, node, 1u) ||
                !push_expr(stack_top, node_stack, state_stack, expr_right(node), 0u) ||
                !push_expr(stack_top, node_stack, state_stack, expr_left(node), 0u))
            {
                expr_fail = 10u;
                return false;
            }
            continue;
        }
        expr_fail = 11u;
        return false;
    }
    return false;
}

bool is_print_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;
    uint callee_token = callee_token_for_call(call_node);
    return valid_token(callee_token) && call_intrinsic_tag[callee_token] == INTRINSIC_PRINT;
}

uint next_print_call(uint fn_node, uint boundary_pos, uint after_pos)
{
    uint best = INVALID;
    uint best_pos = INVALID;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        uint pos = hir_token_pos[node];
        if (pos == INVALID || pos >= boundary_pos || pos <= after_pos ||
            !node_in_function(node, fn_node) || !is_print_call(node))
            continue;
        if (best_pos == INVALID || pos < best_pos)
        {
            best_pos = pos;
            best = node;
        }
    }
    return best;
}

bool emit_print_call(inout uint cursor, uint base, uint call_node, uint fn_node, bool write,
                     uint target)
{
    if (call_arg_count_for_call(call_node) != 1u)
        return false;
    uint arg_node = call_arg_node(call_node, 0u);
    uint expr_fail = 0u;
    if (!emit_expr_node(cursor, base, arg_node, fn_node, expr_fail, write, target))
        return false;
    put_body_byte(cursor, base, 0xacu, write, target);
    put_body_byte(cursor, base, 0x10u, write, target);
    put_body_u32_leb(cursor, base, 0u, write, target);
    return true;
}

bool emit_function_body(uint fn_node, out uint body_len, out uint fail_detail, bool write,
                        uint target, uint base)
{
    body_len = 0u;
    fail_detail = 0u;
    if (function_param_count(fn_node) > 2u)
    {
        fail_detail = 1u;
        return false;
    }
    uint return_node = find_return_node(fn_node);
    uint return_pos = valid_node(return_node) ? hir_token_pos[return_node] : INVALID;
    if (!valid_node(return_node) || return_pos == INVALID)
    {
        fail_detail = 2u;
        return false;
    }

    uint cursor = 0u;
    put_body_u32_leb(cursor, base, 0u, write, target);

    uint after_pos = 0u;
    [loop]
    for (uint i = 0u; i < MAX_PRINTS; i += 1u)
    {
        uint print_node = next_print_call(fn_node, return_pos, after_pos);
        if (!valid_node(print_node))
            break;
        if (!emit_print_call(cursor, base, print_node, fn_node, write, target))
        {
            fail_detail = 3u;
            return false;
        }
        after_pos = hir_token_pos[print_node];
    }

    uint ret_expr = stmt_record(return_node, STMT_RECORD_A);
    uint expr_fail = 0u;
    if (!emit_expr_node(cursor, base, ret_expr, fn_node, expr_fail, write, target))
    {
        fail_detail = expr_fail;
        return false;
    }
    put_body_byte(cursor, base, 0x0bu, write, target);
    body_len = cursor;
    return true;
}

uint wasm_type_index_for_function(uint fn_node)
{
    uint params = function_param_count(fn_node);
    if (params == 0u)
        return 1u;
    if (params == 1u)
        return 2u;
    if (params == 2u)
        return 3u;
    return INVALID;
}

void emit_type_entry(inout uint cursor, uint type_index, bool write, uint target)
{
    put_byte(cursor, 0x60u, write, target);
    if (type_index == 1u)
    {
        put_byte(cursor, 0u, write, target);
        put_byte(cursor, 1u, write, target);
        put_byte(cursor, 0x7fu, write, target);
    }
    else if (type_index == 2u)
    {
        put_byte(cursor, 1u, write, target);
        put_byte(cursor, 0x7fu, write, target);
        put_byte(cursor, 1u, write, target);
        put_byte(cursor, 0x7fu, write, target);
    }
    else
    {
        put_byte(cursor, 2u, write, target);
        put_byte(cursor, 0x7fu, write, target);
        put_byte(cursor, 0x7fu, write, target);
        put_byte(cursor, 1u, write, target);
        put_byte(cursor, 0x7fu, write, target);
    }
}

bool code_payload_len(uint fn_count, out uint payload_len)
{
    payload_len = u32_leb_size(fn_count);
    [loop]
    for (uint ord = 0u; ord < fn_count; ord += 1u)
    {
        uint body_len = 0u;
        uint fail_detail = 0u;
        if (!emit_function_body(nth_function_node(ord), body_len, fail_detail, false, 0u, 0u))
        {
            payload_len = ord * 10000u + fail_detail;
            return false;
        }
        payload_len += u32_leb_size(body_len) + body_len;
    }
    return true;
}

bool emit_module(out uint module_len, out uint fail_stage, bool write, uint target)
{
    module_len = 0u;
    fail_stage = 0u;
    uint fn_count = function_count();
    if (fn_count <= 1u)
    {
        fail_stage = 1u;
        return false;
    }
    uint main_fn = find_main_fn_node();
    uint main_ord = valid_node(main_fn) ? function_ordinal(main_fn) : INVALID;
    if (main_ord == INVALID)
    {
        fail_stage = 2u;
        return false;
    }

    [loop]
    for (uint ord = 0u; ord < fn_count; ord += 1u)
    {
        if (wasm_type_index_for_function(nth_function_node(ord)) == INVALID)
        {
            fail_stage = 3u;
            return false;
        }
    }

    uint code_len = 0u;
    if (!code_payload_len(fn_count, code_len))
    {
        module_len = code_len;
        fail_stage = 4u;
        return false;
    }

    uint cursor = 0u;
    put_byte(cursor, 0x00u, write, target);
    put_byte(cursor, 0x61u, write, target);
    put_byte(cursor, 0x73u, write, target);
    put_byte(cursor, 0x6du, write, target);
    put_byte(cursor, 0x01u, write, target);
    put_byte(cursor, 0x00u, write, target);
    put_byte(cursor, 0x00u, write, target);
    put_byte(cursor, 0x00u, write, target);

    put_byte(cursor, 1u, write, target);
    put_u32_leb(cursor, 20u, write, target);
    put_u32_leb(cursor, 4u, write, target);
    put_byte(cursor, 0x60u, write, target);
    put_byte(cursor, 1u, write, target);
    put_byte(cursor, 0x7eu, write, target);
    put_byte(cursor, 0u, write, target);
    emit_type_entry(cursor, 1u, write, target);
    emit_type_entry(cursor, 2u, write, target);
    emit_type_entry(cursor, 3u, write, target);

    put_byte(cursor, 2u, write, target);
    put_u32_leb(cursor, 17u, write, target);
    put_byte(cursor, 1u, write, target);
    put_byte(cursor, 3u, write, target);
    put_byte(cursor, 101u, write, target);
    put_byte(cursor, 110u, write, target);
    put_byte(cursor, 118u, write, target);
    put_byte(cursor, 9u, write, target);
    put_byte(cursor, 112u, write, target);
    put_byte(cursor, 114u, write, target);
    put_byte(cursor, 105u, write, target);
    put_byte(cursor, 110u, write, target);
    put_byte(cursor, 116u, write, target);
    put_byte(cursor, 95u, write, target);
    put_byte(cursor, 105u, write, target);
    put_byte(cursor, 54u, write, target);
    put_byte(cursor, 52u, write, target);
    put_byte(cursor, 0u, write, target);
    put_byte(cursor, 0u, write, target);

    uint function_payload_len = u32_leb_size(fn_count) + fn_count;
    put_byte(cursor, 3u, write, target);
    put_u32_leb(cursor, function_payload_len, write, target);
    put_u32_leb(cursor, fn_count, write, target);
    [loop]
    for (uint ord = 0u; ord < fn_count; ord += 1u)
        put_u32_leb(cursor, wasm_type_index_for_function(nth_function_node(ord)), write, target);

    uint main_index = main_ord + 1u;
    uint export_payload_len = 1u + 1u + 4u + 1u + u32_leb_size(main_index);
    put_byte(cursor, 7u, write, target);
    put_u32_leb(cursor, export_payload_len, write, target);
    put_byte(cursor, 1u, write, target);
    put_byte(cursor, 4u, write, target);
    put_byte(cursor, 109u, write, target);
    put_byte(cursor, 97u, write, target);
    put_byte(cursor, 105u, write, target);
    put_byte(cursor, 110u, write, target);
    put_byte(cursor, 0u, write, target);
    put_u32_leb(cursor, main_index, write, target);

    put_byte(cursor, 10u, write, target);
    put_u32_leb(cursor, code_len, write, target);
    put_u32_leb(cursor, fn_count, write, target);
    [loop]
    for (uint ord = 0u; ord < fn_count; ord += 1u)
    {
        uint body_len = 0u;
        uint fail_detail = 0u;
        uint fn_node = nth_function_node(ord);
        if (!emit_function_body(fn_node, body_len, fail_detail, false, 0u, 0u))
        {
            module_len = ord * 10000u + fail_detail;
            fail_stage = 5u;
            return false;
        }
        put_u32_leb(cursor, body_len, write, target);
        uint body_base = cursor;
        if (!emit_function_body(fn_node, body_len, fail_detail, write, target, body_base))
        {
            module_len = ord * 10000u + fail_detail;
            fail_stage = 6u;
            return false;
        }
        cursor += body_len;
    }

    module_len = cursor;
    return true;
}

void record_reject(uint detail, uint value, uint target)
{
    if (target == 0u)
    {
        status[0u] = value;
        status[1u] = 2u;
        status[2u] = ERR_MULTI_FUNCTION_MODULE_BASE + detail;
        status[3u] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint target = linear_dispatch_id(tid);
    uint target_limit = min(gParams.out_capacity, HIR_MODULE_OUTPUT_TARGET_LIMIT);
    if (target >= target_limit && target != 0u)
        return;

    uint fn_count = function_count();
    if (fn_count <= 1u)
        return;

    uint module_len = 0u;
    uint fail_stage = 0u;
    if (!emit_module(module_len, fail_stage, false, target))
    {
        record_reject(fail_stage, module_len, target);
        return;
    }
    if (module_len == 0u || module_len > gParams.out_capacity ||
        module_len > HIR_MODULE_OUTPUT_TARGET_LIMIT)
    {
        record_reject(2u, module_len, target);
        return;
    }
    if (!emit_module(module_len, fail_stage, true, target))
    {
        record_reject(10u + fail_stage, module_len, target);
        return;
    }

    if (target == 0u)
    {
        status[0u] = module_len;
        status[1u] = 1u;
        status[2u] = 0u;
        status[3u] = INVALID;
    }
}
