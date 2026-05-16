// Record-driven WASM function-body emitter for the scalar main slice.
//
// This pass consumes GPU-owned HIR, statement, expression, resolver, and
// intrinsic records. It does not read token records, source bytes, token
// spelling, helper names, or function-body text shapes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_start;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> call_intrinsic_tag;

RWStructuredBuffer<uint> body_words;
RWStructuredBuffer<uint> body_status;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint HIR_FN = 3u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint ENTRYPOINT_MAIN = 1u;
static const uint INTRINSIC_PRINT = 1u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND = 0u;
static const uint STMT_RECORD_A = 1u;
static const uint STMT_RECORD_B = 2u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;

static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint ASSIGN_OP_XOR = 7u;
static const uint ASSIGN_OP_SHL = 8u;
static const uint ASSIGN_OP_SHR = 9u;
static const uint ASSIGN_OP_BAND = 10u;
static const uint ASSIGN_OP_BOR = 11u;

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

static const uint MAX_LOCAL_COUNT = 16u;
static const uint MAX_BODY_STATEMENTS = 64u;
static const uint MAX_EXPR_STACK = 96u;

static const uint NEXT_STATEMENT_LET = 1u;
static const uint NEXT_STATEMENT_ASSIGN = 2u;
static const uint NEXT_STATEMENT_PRINT = 3u;
static const uint NEXT_STATEMENT_IF = 4u;

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

uint parent_node(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

uint nearest_control_ancestor(uint node)
{
    uint cur = parent_node(node);
    [loop]
    for (uint guard = 0u; guard < 96u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        uint kind = hir_kind[cur];
        if (kind == HIR_IF_STMT || kind == HIR_WHILE_STMT || kind == HIR_MATCH_EXPR)
            return cur;
        uint p = parent_node(cur);
        if (!valid_node(p) || p == cur)
            return INVALID;
        cur = p;
    }
    return INVALID;
}

bool has_ancestor(uint node, uint ancestor)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return false;
        if (cur == ancestor)
            return true;
        uint p = parent_node(cur);
        if (!valid_node(p) || p == cur)
            return false;
        cur = p;
    }
    return false;
}

uint nearest_hir_statement(uint node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 96u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        uint kind = hir_kind[cur];
        if (kind == HIR_STMT || kind == HIR_LET_STMT || kind == HIR_RETURN_STMT ||
            kind == HIR_IF_STMT || kind == HIR_WHILE_STMT || kind == HIR_BREAK_STMT ||
            kind == HIR_CONTINUE_STMT)
            return cur;
        cur = parent_node(cur);
    }
    return INVALID;
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint stmt_record(uint node, uint slot)
{
    return valid_node(node) ? hir_stmt_record[stmt_slot(node, slot)] : INVALID;
}

uint expr_form(uint node)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + EXPR_RECORD_FORM] : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + EXPR_RECORD_LEFT] : INVALID;
}

uint expr_right(uint node)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + EXPR_RECORD_RIGHT] : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + EXPR_RECORD_VALUE_TOKEN]
                            : INVALID;
}

void put_body(uint pos, uint value, bool write, uint target)
{
    if (write && pos < gParams.out_capacity && pos == target)
        body_words[pos] = value & 0xffu;
}

void put_byte(inout uint cursor, uint value, bool write, uint target)
{
    put_body(cursor, value, write, target);
    cursor += 1u;
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

void emit_i32_const(inout uint cursor, uint value, bool write, uint target)
{
    put_byte(cursor, 0x41u, write, target);
    put_u32_leb5(cursor, value, write, target);
}

void emit_local_get(inout uint cursor, uint local_i, bool write, uint target)
{
    put_byte(cursor, 0x20u, write, target);
    put_u32_leb(cursor, local_i, write, target);
}

void emit_local_set(inout uint cursor, uint local_i, bool write, uint target)
{
    put_byte(cursor, 0x21u, write, target);
    put_u32_leb(cursor, local_i, write, target);
}

bool emit_local_decls(inout uint cursor, uint local_count, bool write, uint target)
{
    if (local_count == 0u)
    {
        put_u32_leb(cursor, 0u, write, target);
        return true;
    }
    put_u32_leb(cursor, 1u, write, target);
    put_u32_leb(cursor, local_count, write, target);
    put_byte(cursor, 0x7fu, write, target);
    return true;
}

uint find_main_fn_node()
{
    uint found = INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] != HIR_FN)
            continue;
        uint fn_token = hir_token_pos[i];
        bool tagged = fn_entrypoint_tag[i] == ENTRYPOINT_MAIN ||
                      (valid_token(fn_token) && fn_entrypoint_tag[fn_token] == ENTRYPOINT_MAIN);
        if (!tagged)
            continue;
        if (found != INVALID)
            return INVALID;
        found = i;
    }
    return found;
}

uint find_return_node(uint fn_node)
{
    uint found = INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] != HIR_RETURN_STMT || !has_ancestor(i, fn_node))
            continue;
        if (stmt_record(i, STMT_RECORD_KIND) != STMT_RECORD_KIND_RETURN)
            continue;
        if (found != INVALID)
            return INVALID;
        found = i;
    }
    return found;
}

bool unsupported_control_flow_before(uint fn_node, uint boundary_pos)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        uint pos = hir_token_pos[i];
        if (pos == INVALID || pos >= boundary_pos || !has_ancestor(i, fn_node))
            continue;
        uint kind = hir_kind[i];
        if (kind == HIR_WHILE_STMT || kind == HIR_BREAK_STMT ||
            kind == HIR_CONTINUE_STMT || kind == HIR_MATCH_EXPR)
            return true;
    }
    return false;
}

bool is_print_call_statement(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;
    uint stmt = nearest_hir_statement(call_node);
    if (!valid_node(stmt) || hir_kind[stmt] != HIR_STMT)
        return false;
    uint callee = hir_call_callee_node[call_node];
    uint callee_token = valid_node(callee) ? hir_token_pos[callee] : INVALID;
    return valid_token(callee_token) && call_intrinsic_tag[callee_token] == INTRINSIC_PRINT;
}

uint local_index_for_decl_token(uint decl_token, inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                                uint local_count)
{
    [loop]
    for (uint i = 0u; i < MAX_LOCAL_COUNT; i += 1u)
    {
        if (i >= local_count)
            break;
        if (local_decl_tokens[i] == decl_token)
            return i;
    }
    return INVALID;
}

uint local_index_for_name_expr(uint node, inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                               uint local_count)
{
    uint cur = node;
    uint form = expr_form(cur);
    [loop]
    for (uint guard = 0u; guard < 64u && form == HIR_EXPR_FORWARD; guard += 1u)
    {
        cur = expr_left(cur);
        if (!valid_node(cur))
            return INVALID;
        form = expr_form(cur);
    }

    if (form != HIR_EXPR_NAME)
        return INVALID;
    uint value_token = expr_value_token(cur);
    uint decl_token = valid_token(value_token) ? visible_decl[value_token] : INVALID;
    return local_index_for_decl_token(decl_token, local_decl_tokens, local_count);
}

bool collect_locals(uint fn_node, uint boundary_pos,
                    inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                    inout uint local_nodes[MAX_LOCAL_COUNT],
                    out uint local_count)
{
    local_count = 0u;
    [unroll]
    for (uint slot = 0u; slot < MAX_LOCAL_COUNT; slot += 1u)
    {
        local_decl_tokens[slot] = INVALID;
        local_nodes[slot] = INVALID;
    }

    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        uint pos = hir_token_pos[i];
        if (hir_kind[i] != HIR_LET_STMT || pos == INVALID || pos >= boundary_pos ||
            !has_ancestor(i, fn_node))
            continue;
        if (stmt_record(i, STMT_RECORD_KIND) != STMT_RECORD_KIND_LET)
            return false;
        uint decl_token = stmt_record(i, STMT_RECORD_A);
        uint init_expr = stmt_record(i, STMT_RECORD_B);
        if (!valid_token(decl_token) || !valid_node(init_expr))
            return false;
        if (local_index_for_decl_token(decl_token, local_decl_tokens, local_count) != INVALID)
            return false;
        if (local_count >= MAX_LOCAL_COUNT)
            return false;

        uint insert_at = local_count;
        [loop]
        for (uint guard = 0u; guard < MAX_LOCAL_COUNT && insert_at > 0u; guard += 1u)
        {
            uint prev = local_nodes[insert_at - 1u];
            if (!valid_node(prev) || hir_token_pos[prev] <= pos)
                break;
            local_decl_tokens[insert_at] = local_decl_tokens[insert_at - 1u];
            local_nodes[insert_at] = local_nodes[insert_at - 1u];
            insert_at -= 1u;
        }
        local_decl_tokens[insert_at] = decl_token;
        local_nodes[insert_at] = i;
        local_count += 1u;
    }
    return true;
}

void emit_assignment_op(inout uint cursor, uint op, bool write, uint target)
{
    if (op == ASSIGN_OP_SUB)
        put_byte(cursor, 0x6bu, write, target);
    else if (op == ASSIGN_OP_MUL)
        put_byte(cursor, 0x6cu, write, target);
    else if (op == ASSIGN_OP_DIV)
        put_byte(cursor, 0x6du, write, target);
    else if (op == ASSIGN_OP_MOD)
        put_byte(cursor, 0x6fu, write, target);
    else if (op == ASSIGN_OP_XOR)
        put_byte(cursor, 0x73u, write, target);
    else if (op == ASSIGN_OP_SHL)
        put_byte(cursor, 0x74u, write, target);
    else if (op == ASSIGN_OP_SHR)
        put_byte(cursor, 0x75u, write, target);
    else if (op == ASSIGN_OP_BAND)
        put_byte(cursor, 0x71u, write, target);
    else if (op == ASSIGN_OP_BOR)
        put_byte(cursor, 0x72u, write, target);
    else
        put_byte(cursor, 0x6au, write, target);
}

void emit_expr_op(inout uint cursor, uint form, bool write, uint target)
{
    if (form == HIR_EXPR_NOT)
        put_byte(cursor, 0x45u, write, target);
    else if (form == HIR_EXPR_NEG || form == HIR_EXPR_SUB)
        put_byte(cursor, 0x6bu, write, target);
    else if (form == HIR_EXPR_MUL)
        put_byte(cursor, 0x6cu, write, target);
    else if (form == HIR_EXPR_DIV)
        put_byte(cursor, 0x6du, write, target);
    else if (form == HIR_EXPR_MOD)
        put_byte(cursor, 0x6fu, write, target);
    else if (form == HIR_EXPR_LT)
        put_byte(cursor, 0x48u, write, target);
    else if (form == HIR_EXPR_GT)
        put_byte(cursor, 0x4au, write, target);
    else if (form == HIR_EXPR_LE)
        put_byte(cursor, 0x4cu, write, target);
    else if (form == HIR_EXPR_GE)
        put_byte(cursor, 0x4eu, write, target);
    else if (form == HIR_EXPR_EQ)
        put_byte(cursor, 0x46u, write, target);
    else if (form == HIR_EXPR_NE)
        put_byte(cursor, 0x47u, write, target);
    else if (form == HIR_EXPR_AND)
        put_byte(cursor, 0x71u, write, target);
    else if (form == HIR_EXPR_OR)
        put_byte(cursor, 0x72u, write, target);
    else if (form == HIR_EXPR_BIT_OR)
        put_byte(cursor, 0x72u, write, target);
    else if (form == HIR_EXPR_BIT_XOR)
        put_byte(cursor, 0x73u, write, target);
    else if (form == HIR_EXPR_BIT_AND)
        put_byte(cursor, 0x71u, write, target);
    else if (form == HIR_EXPR_SHL)
        put_byte(cursor, 0x74u, write, target);
    else if (form == HIR_EXPR_SHR)
        put_byte(cursor, 0x75u, write, target);
    else
        put_byte(cursor, 0x6au, write, target);
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

bool emit_expr_node(inout uint cursor, uint root,
                    inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                    uint local_count, bool write, uint target)
{
    uint node_stack[MAX_EXPR_STACK];
    uint state_stack[MAX_EXPR_STACK];
    uint stack_top = 0u;
    if (!push_expr(stack_top, node_stack, state_stack, root, 0u))
        return false;

    [loop]
    for (uint guard = 0u; guard < 384u; guard += 1u)
    {
        if (stack_top == 0u)
            return true;
        stack_top -= 1u;
        uint node = node_stack[stack_top];
        uint state = state_stack[stack_top];

        uint form = expr_form(node);
        [loop]
        for (uint forward_guard = 0u; forward_guard < 64u && form == HIR_EXPR_FORWARD;
             forward_guard += 1u)
        {
            node = expr_left(node);
            if (!valid_node(node))
                return false;
            form = expr_form(node);
        }

        if (state == 1u)
        {
            emit_expr_op(cursor, form, write, target);
            continue;
        }

        if (form == HIR_EXPR_INT)
        {
            emit_i32_const(cursor, hir_expr_int_value[node], write, target);
            continue;
        }
        if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        {
            emit_i32_const(cursor, form == HIR_EXPR_TRUE ? 1u : 0u, write, target);
            continue;
        }
        if (form == HIR_EXPR_NAME)
        {
            uint value_token = expr_value_token(node);
            uint decl_token = valid_token(value_token) ? visible_decl[value_token] : INVALID;
            uint local_i = local_index_for_decl_token(decl_token, local_decl_tokens, local_count);
            if (local_i == INVALID)
                return false;
            emit_local_get(cursor, local_i, write, target);
            continue;
        }
        if (form == HIR_EXPR_NOT)
        {
            if (!push_expr(stack_top, node_stack, state_stack, node, 1u) ||
                !push_expr(stack_top, node_stack, state_stack, expr_left(node), 0u))
                return false;
            continue;
        }
        if (form == HIR_EXPR_NEG)
        {
            emit_i32_const(cursor, 0u, write, target);
            if (!push_expr(stack_top, node_stack, state_stack, node, 1u) ||
                !push_expr(stack_top, node_stack, state_stack, expr_left(node), 0u))
                return false;
            continue;
        }
        if (form >= HIR_EXPR_EQ && form <= HIR_EXPR_SHR)
        {
            if (!push_expr(stack_top, node_stack, state_stack, node, 1u) ||
                !push_expr(stack_top, node_stack, state_stack, expr_right(node), 0u) ||
                !push_expr(stack_top, node_stack, state_stack, expr_left(node), 0u))
                return false;
            continue;
        }
        return false;
    }
    return false;
}

bool emit_let_stmt(inout uint cursor, uint let_node, uint local_i,
                   inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                   uint local_count, bool write, uint target)
{
    uint init_expr = stmt_record(let_node, STMT_RECORD_B);
    if (!emit_expr_node(cursor, init_expr, local_decl_tokens, local_count, write, target))
        return false;
    emit_local_set(cursor, local_i, write, target);
    return true;
}

bool emit_print_call(inout uint cursor, uint call_node,
                     inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                     uint local_count, bool write, uint target)
{
    if (hir_call_arg_count[call_node] != 1u)
        return false;
    uint arg_node = hir_call_arg_start[call_node];
    if (!emit_expr_node(cursor, arg_node, local_decl_tokens, local_count, write, target))
        return false;
    put_byte(cursor, 0xacu, write, target);
    put_byte(cursor, 0x10u, write, target);
    put_u32_leb(cursor, 0u, write, target);
    return true;
}

bool emit_assignment_stmt(inout uint cursor, uint stmt_node,
                          inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                          uint local_count, bool write, uint target)
{
    uint target_expr = stmt_record(stmt_node, STMT_RECORD_A);
    uint rhs_expr = stmt_record(stmt_node, STMT_RECORD_B);
    uint op = stmt_record(stmt_node, 3u);
    uint local_i = local_index_for_name_expr(target_expr, local_decl_tokens, local_count);
    if (local_i == INVALID || !valid_node(rhs_expr))
        return false;

    if (op == ASSIGN_OP_SET)
    {
        if (!emit_expr_node(cursor, rhs_expr, local_decl_tokens, local_count, write, target))
            return false;
        emit_local_set(cursor, local_i, write, target);
        return true;
    }

    if (op < ASSIGN_OP_ADD || op > ASSIGN_OP_BOR)
        return false;
    emit_local_get(cursor, local_i, write, target);
    if (!emit_expr_node(cursor, rhs_expr, local_decl_tokens, local_count, write, target))
        return false;
    emit_assignment_op(cursor, op, write, target);
    emit_local_set(cursor, local_i, write, target);
    return true;
}

bool classify_statement_candidate(uint candidate, bool allow_if, out uint node, out uint kind)
{
    node = candidate;
    kind = 0u;
    bool is_let = hir_kind[candidate] == HIR_LET_STMT &&
                  stmt_record(candidate, STMT_RECORD_KIND) == STMT_RECORD_KIND_LET;
    bool is_assign = hir_kind[candidate] == HIR_STMT &&
                     stmt_record(candidate, STMT_RECORD_KIND) == STMT_RECORD_KIND_ASSIGN;
    bool is_if = allow_if && hir_kind[candidate] == HIR_IF_STMT &&
                 stmt_record(candidate, STMT_RECORD_KIND) == STMT_RECORD_KIND_IF;
    bool is_print = is_print_call_statement(candidate);
    if (!is_let && !is_assign && !is_if && !is_print)
        return false;
    kind = is_let ? NEXT_STATEMENT_LET
                  : (is_assign ? NEXT_STATEMENT_ASSIGN
                               : (is_if ? NEXT_STATEMENT_IF : NEXT_STATEMENT_PRINT));
    return true;
}

bool candidate_in_top_sequence(uint candidate, uint fn_node)
{
    if (!has_ancestor(candidate, fn_node))
        return false;
    uint stmt = nearest_hir_statement(candidate);
    if (!valid_node(stmt))
        return false;
    return nearest_control_ancestor(stmt) == INVALID;
}

bool candidate_in_if_branch(uint candidate, uint if_node, uint branch_block)
{
    if (!valid_node(branch_block) || !has_ancestor(candidate, branch_block))
        return false;
    uint stmt = nearest_hir_statement(candidate);
    if (!valid_node(stmt))
        return false;
    return nearest_control_ancestor(stmt) == if_node;
}

bool next_top_statement(uint fn_node, uint boundary_pos, uint after_pos,
                        out uint node, out uint kind)
{
    node = INVALID;
    kind = 0u;
    uint best_pos = INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        uint pos = hir_token_pos[i];
        if (pos == INVALID || pos >= boundary_pos || pos <= after_pos ||
            !candidate_in_top_sequence(i, fn_node))
            continue;
        uint candidate_node = INVALID;
        uint candidate_kind = 0u;
        if (!classify_statement_candidate(i, true, candidate_node, candidate_kind))
            continue;
        if (best_pos == INVALID || pos < best_pos)
        {
            best_pos = pos;
            node = candidate_node;
            kind = candidate_kind;
        }
    }
    return node != INVALID;
}

bool next_if_branch_statement(uint if_node, uint branch_block, uint after_pos,
                              out uint node, out uint kind)
{
    node = INVALID;
    kind = 0u;
    uint best_pos = INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        uint pos = hir_token_pos[i];
        if (pos == INVALID || pos <= after_pos || !candidate_in_if_branch(i, if_node, branch_block))
            continue;
        uint candidate_node = INVALID;
        uint candidate_kind = 0u;
        if (!classify_statement_candidate(i, false, candidate_node, candidate_kind))
            continue;
        if (best_pos == INVALID || pos < best_pos)
        {
            best_pos = pos;
            node = candidate_node;
            kind = candidate_kind;
        }
    }
    return node != INVALID;
}

bool emit_statement_by_kind(inout uint cursor, uint node, uint kind,
                            inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                            uint local_count, bool write, uint target)
{
    if (kind == NEXT_STATEMENT_LET)
    {
        uint decl_token = stmt_record(node, STMT_RECORD_A);
        uint local_i = local_index_for_decl_token(decl_token, local_decl_tokens, local_count);
        return local_i != INVALID &&
               emit_let_stmt(cursor, node, local_i, local_decl_tokens, local_count, write, target);
    }
    if (kind == NEXT_STATEMENT_ASSIGN)
        return emit_assignment_stmt(cursor, node, local_decl_tokens, local_count, write, target);
    if (kind == NEXT_STATEMENT_PRINT)
        return emit_print_call(cursor, node, local_decl_tokens, local_count, write, target);
    return false;
}

bool emit_if_branch_statements(inout uint cursor, uint if_node, uint branch_block,
                               inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                               uint local_count, bool write, uint target)
{
    uint after_pos = 0u;
    [loop]
    for (uint stmt_i = 0u; stmt_i < MAX_BODY_STATEMENTS; stmt_i += 1u)
    {
        uint node = INVALID;
        uint kind = 0u;
        if (!next_if_branch_statement(if_node, branch_block, after_pos, node, kind))
            return true;
        if (!emit_statement_by_kind(cursor, node, kind, local_decl_tokens, local_count, write, target))
            return false;
        after_pos = hir_token_pos[node];
    }
    return false;
}

bool emit_if_stmt(inout uint cursor, uint if_node,
                  inout uint local_decl_tokens[MAX_LOCAL_COUNT],
                  uint local_count, bool write, uint target)
{
    uint cond_expr = stmt_record(if_node, STMT_RECORD_A);
    uint then_block = stmt_record(if_node, STMT_RECORD_B);
    uint else_block = stmt_record(if_node, 3u);
    if (!valid_node(cond_expr) || !valid_node(then_block))
        return false;

    if (!emit_expr_node(cursor, cond_expr, local_decl_tokens, local_count, write, target))
        return false;
    put_byte(cursor, 0x04u, write, target);
    put_byte(cursor, 0x40u, write, target);
    if (!emit_if_branch_statements(cursor, if_node, then_block, local_decl_tokens, local_count, write, target))
        return false;
    if (valid_node(else_block))
    {
        put_byte(cursor, 0x05u, write, target);
        if (!emit_if_branch_statements(cursor, if_node, else_block, local_decl_tokens, local_count, write, target))
            return false;
    }
    put_byte(cursor, 0x0bu, write, target);
    return true;
}

bool emit_main_body(out uint body_len, bool write, uint target)
{
    body_len = 0u;
    uint fn_node = find_main_fn_node();
    uint ret_node = valid_node(fn_node) ? find_return_node(fn_node) : INVALID;
    uint ret_pos = valid_node(ret_node) ? hir_token_pos[ret_node] : INVALID;
    if (!valid_node(fn_node) || !valid_node(ret_node) || ret_pos == INVALID ||
        unsupported_control_flow_before(fn_node, ret_pos))
        return false;

    uint local_decl_tokens[MAX_LOCAL_COUNT];
    uint local_nodes[MAX_LOCAL_COUNT];
    uint local_count = 0u;
    if (!collect_locals(fn_node, ret_pos, local_decl_tokens, local_nodes, local_count))
        return false;

    uint cursor = 0u;
    if (!emit_local_decls(cursor, local_count, write, target))
        return false;

    uint after_pos = 0u;
    [loop]
    for (uint stmt_i = 0u; stmt_i < MAX_BODY_STATEMENTS; stmt_i += 1u)
    {
        uint node = INVALID;
        uint kind = 0u;
        if (!next_top_statement(fn_node, ret_pos, after_pos, node, kind))
            break;
        if (kind == NEXT_STATEMENT_IF)
        {
            if (!emit_if_stmt(cursor, node, local_decl_tokens, local_count, write, target))
                return false;
        }
        else if (!emit_statement_by_kind(cursor, node, kind, local_decl_tokens, local_count, write, target))
            return false;
        after_pos = hir_token_pos[node];
    }

    uint ret_expr = stmt_record(ret_node, STMT_RECORD_A);
    if (!emit_expr_node(cursor, ret_expr, local_decl_tokens, local_count, write, target))
        return false;
    put_byte(cursor, 0x0bu, write, target);
    body_len = cursor;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint target = linear_dispatch_id(tid);
    if (target >= gParams.out_capacity && target != 0u)
        return;

    uint body_len = 0u;
    if (!emit_main_body(body_len, false, target))
        return;
    if (body_len == 0u || body_len > gParams.out_capacity)
        return;
    if (!emit_main_body(body_len, true, target))
        return;

    if (target == 0u)
    {
        body_status[0u] = body_len;
        body_status[1u] = 1u;
        status[1u] = 0u;
        status[2u] = 0u;
        status[3u] = INVALID;
    }
}
