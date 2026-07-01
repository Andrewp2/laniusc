// Parallel validation and aggregate planning for the scalar WASM body.

import atomics;
import body_common;

StructuredBuffer<uint> status;
RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;

static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_MAIN_TOKEN_MIN = 9u;
static const uint BODY_PLAN_STMT_INVALID_COUNT = 11u;
static const uint BODY_PLAN_RETURN_COUNT = 12u;
static const uint BODY_PLAN_RETURN_TOKEN_MIN = 13u;
static const uint BODY_PLAN_LET_COUNT = 14u;
static const uint BODY_PLAN_LET_MAX_TOKEN = 15u;
static const uint BODY_PLAN_CALL_INVALID_COUNT = 16u;
static const uint BODY_PLAN_PRINT_COUNT_AGG = 17u;
static const uint BODY_PLAN_PRINT_LEN_AGG = 18u;
static const uint BODY_PLAN_PRINT_MAX_TOKEN = 19u;
static const uint BODY_PLAN_RETURN_VALUE_OK_COUNT = 20u;
static const uint BODY_PLAN_RETURN_VALUE_AGG = 21u;
static const uint BODY_PLAN_RETURN_VALUE_INVALID_COUNT = 22u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_ASSIGN_COUNT = 24u;
static const uint BODY_PLAN_ASSIGN_MAX_TOKEN = 25u;
static const uint BODY_PLAN_ASSIGN_LEN_AGG = 26u;
static const uint BODY_PLAN_LET_LEN_AGG = 27u;
static const uint BODY_PLAN_RETURN_LEN_AGG = 28u;
static const uint BODY_PLAN_LOCAL_CONST_EXPR_COUNT = 29u;
static const uint BODY_PLAN_CONTROL_LEN_AGG = 30u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_EXPR_INDEX = 26u;

void publish_fragment(uint token_i, uint len, uint4 meta, uint4 aux)
{
    uint slot = token_i * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
}

void publish_fragment_slot(uint slot, uint len, uint4 meta, uint4 aux)
{
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
}

uint4 direct_call_aux(uint call_node)
{
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    call_node = resolve_expr_node(call_node);
    if (!direct_user_call_node(call_node, fn_token, wasm_func_index, arg_count))
        return uint4(INVALID, 0u, 0u, 0u);
    return uint4(wasm_func_index, arg_count, fn_token, 0u);
}

void publish_detail(uint detail)
{
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
}

void publish_stmt_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_STMT_INVALID_COUNT, 1u);
    publish_detail(detail);
}

void publish_call_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_CALL_INVALID_COUNT, 1u);
    publish_detail(detail);
}

void publish_return_value(uint value)
{
    uint old_value = 0u;
    InterlockedExchange(body_plan[BODY_PLAN_RETURN_VALUE_AGG], value, old_value);
    atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
}

void publish_func_invalid(uint fn_token, uint detail)
{
    if (!valid_token(fn_token))
    {
        publish_stmt_invalid(detail);
        return;
    }
    atomic_u32_add(wasm_func_invalid_count_by_token, fn_token, 1u);
    atomic_u32_min(wasm_func_detail_by_token, fn_token, detail);
}

void add_func_body_len(uint fn_token, uint len)
{
    if (valid_token(fn_token))
        atomic_u32_add(wasm_func_body_len_by_token, fn_token, len);
}

void add_func_local_token(uint fn_token, uint decl_token)
{
    if (valid_token(fn_token) && valid_token(decl_token))
    {
        uint prior = atomic_u32_compare_exchange(
            wasm_func_local_max_by_token,
            fn_token,
            INVALID,
            decl_token);
        if (prior != INVALID)
            atomic_u32_max(wasm_func_local_max_by_token, fn_token, decl_token);
    }
}

void validate_main_statement(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    uint stmt_kind = stmt_record_slot(node, 0u);
    if (stmt_kind == STMT_RECORD_KIND_NONE || hir_kind[node] == HIR_ARRAY_EXPR)
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_LET && hir_kind[node] == HIR_LET_STMT)
    {
        uint raw_init_expr = resolve_expr_node(stmt_record_slot(node, 2u));
        if (valid_node(raw_init_expr) && hir_kind[raw_init_expr] == HIR_ARRAY_EXPR)
            return;

        uint decl_token = INVALID;
        uint expr_node = INVALID;
        uint value = 0u;
        uint len = 0u;
        bool runtime_expr =
            supported_let_i32_array_data_ptr_fragment(node, decl_token, expr_node, len) ||
            supported_let_host_stdout_write_fragment(node, decl_token, expr_node, len) ||
            supported_let_host_process_argc_fragment(node, decl_token, expr_node, len) ||
            supported_let_host_process_arg_len_fragment(node, decl_token, expr_node, len) ||
            supported_let_host_process_arg_read_fragment(node, decl_token, expr_node, len) ||
            supported_let_host_secure_u32_fragment(node, decl_token, expr_node, len) ||
            supported_let_host_unix_seconds_fragment(node, decl_token, expr_node, len) ||
            supported_let_direct_call_fragment(node, decl_token, expr_node, len) ||
            supported_let_expr_fragment(node, decl_token, expr_node, len);
        if (!runtime_expr &&
            !supported_let_const_fragment(node, decl_token, value, len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }
        uint init_expr = stmt_record_slot(node, 2u);
        if (!runtime_expr && expr_mentions_local_let(init_expr))
            atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);

        add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
        add_func_body_len(owner_fn, len);
        uint4 aux = uint4(INVALID, 0u, 0u, 0u);
        uint kind = BODY_FRAGMENT_LET_CONST_I32;
        uint meta_w = token;
        if (supported_let_i32_array_data_ptr_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_I32_ARRAY_DATA_PTR;
        }
        else if (supported_let_host_stdout_write_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_HOST_STDOUT_WRITE_I32;
        }
        else if (supported_let_host_process_argc_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_HOST_NO_ARG_I32;
            meta_w = WASM_PROCESS_ARGC_FUNC_INDEX;
        }
        else if (supported_let_host_process_arg_len_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_PROCESS_ARG_LEN_I32;
        }
        else if (supported_let_host_process_arg_read_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_PROCESS_ARG_READ_I32;
        }
        else if (supported_let_host_secure_u32_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_HOST_NO_ARG_I32;
            meta_w = WASM_RANDOM_SECURE_U32_FUNC_INDEX;
        }
        else if (supported_let_host_unix_seconds_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_HOST_NO_ARG_I32;
            meta_w = WASM_TIME_UNIX_SECONDS_FUNC_INDEX;
        }
        else if (supported_let_direct_call_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_DIRECT_CALL_I32;
            aux = direct_call_aux(expr_node);
        }
        else if (supported_let_expr_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_EXPR_I32;
        }
        else
        {
            kind = BODY_FRAGMENT_LET_CONST_I32;
            expr_node = value;
        }
        publish_fragment(token, len, uint4(kind, decl_token, expr_node, meta_w), aux);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_RETURN && hir_kind[node] == HIR_RETURN_STMT)
    {
        atomic_u32_add(wasm_func_return_count_by_token, owner_fn, 1u);
        atomic_u32_min(wasm_func_return_token_by_token, owner_fn, token);

        uint return_expr_node = INVALID;
        uint return_value = 0u;
        uint return_len = 0u;
        uint return_decl = INVALID;
        uint return_call_node = INVALID;
        uint return_atom_node = INVALID;
        uint return_op = 0u;
        uint return_call_side = 0u;
        if (return_binary_direct_call_fragment_and_len(
                node,
                return_call_node,
                return_atom_node,
                return_op,
                return_call_side,
                return_len))
        {
            atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
            add_func_body_len(owner_fn, return_len);
            publish_fragment(
                token,
                return_len,
                uint4(
                    BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32,
                    return_call_node,
                    return_atom_node,
                    return_op | (return_call_side << 8u)),
                direct_call_aux(return_call_node));
        }
        else if (return_direct_call_fragment_and_len(node, return_expr_node, return_len))
        {
            atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
            add_func_body_len(owner_fn, return_len);
            publish_fragment(
                token,
                return_len,
                uint4(
                    BODY_FRAGMENT_RETURN_DIRECT_CALL_I32,
                    return_expr_node,
                    return_len,
                    token),
                direct_call_aux(return_expr_node));
        }
        else if (return_expr_fragment_and_len(node, return_expr_node, return_len))
        {
            atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
            add_func_body_len(owner_fn, return_len);
            publish_fragment(
                token,
                return_len,
                uint4(BODY_FRAGMENT_RETURN_EXPR_I32, return_expr_node, return_len, token),
                uint4(INVALID, 0u, 0u, 0u));
        }
        else if (return_expr_value_and_len(node, return_value, return_len))
        {
            publish_return_value(return_value);
            add_func_body_len(owner_fn, return_len);
            if (expr_mentions_local_let(stmt_record_slot(node, 1u)))
                atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);
            publish_fragment(
                token,
                return_len,
                uint4(BODY_FRAGMENT_RETURN_I32, return_value, return_len, token),
                uint4(INVALID, 0u, 0u, 0u));
        }
        else
        {
            atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_INVALID_COUNT, 1u);
            publish_func_invalid(owner_fn, token);
        }
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_IF && hir_kind[node] == HIR_IF_STMT)
    {
        uint condition_node = INVALID;
        uint open_len = 0u;
        uint else_token = INVALID;
        uint else_len = 0u;
        uint end_token = INVALID;
        uint end_len = 0u;
        if (!if_open_fragment_and_len(node, condition_node, open_len) ||
            !if_end_token_and_len(node, end_token, end_len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }

        if (valid_node(stmt_record_slot(node, 3u)) &&
            !if_else_token_and_len(node, else_token, else_len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }

        add_func_body_len(owner_fn, open_len + else_len + end_len);
        publish_fragment(
            token,
            open_len,
            uint4(BODY_FRAGMENT_IF_OPEN_I32, condition_node, open_len, token),
            uint4(INVALID, 0u, 0u, 0u));
        if (else_len != 0u)
        {
            publish_fragment(
                else_token,
                else_len,
                uint4(BODY_FRAGMENT_IF_ELSE, 0u, 0u, else_token),
                uint4(INVALID, 0u, 0u, 0u));
        }
        publish_fragment(
            end_token,
            end_len,
            uint4(BODY_FRAGMENT_IF_END, 0u, 0u, end_token),
            uint4(INVALID, 0u, 0u, 0u));
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, end_token);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_ASSIGN && hir_kind[node] == HIR_STMT)
    {
        uint raw_rhs_node = resolve_expr_node(stmt_record_slot(node, 2u));
        if (valid_node(raw_rhs_node) && expr_form(raw_rhs_node) == HIR_EXPR_INDEX)
            return;

        uint target_decl = INVALID;
        uint rhs_node = INVALID;
        uint rhs_value = 0u;
        uint op = 0u;
        uint len = 0u;
        bool runtime_expr =
            supported_assign_direct_call_fragment(node, target_decl, rhs_node, op, len) ||
            supported_assign_expr_fragment(node, target_decl, rhs_node, op, len);
        if (!runtime_expr &&
            !supported_assign_const_fragment(node, target_decl, rhs_value, op, len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }

        uint rhs = stmt_record_slot(node, 2u);
        if (!runtime_expr && expr_mentions_local_let(rhs))
            atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);
        add_func_body_len(owner_fn, len);
        uint kind = op == ASSIGN_OP_SET
                        ? BODY_FRAGMENT_ASSIGN_CONST_I32
                        : BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32;
        uint value = rhs_value;
        uint4 aux = uint4(INVALID, 0u, 0u, 0u);
        if (supported_assign_direct_call_fragment(node, target_decl, rhs_node, op, len))
        {
            kind = op == ASSIGN_OP_SET
                       ? BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32
                       : BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32;
            value = rhs_node;
            aux = direct_call_aux(rhs_node);
        }
        else if (supported_assign_expr_fragment(node, target_decl, rhs_node, op, len))
        {
            kind = op == ASSIGN_OP_SET
                       ? BODY_FRAGMENT_ASSIGN_EXPR_I32
                       : BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32;
            value = rhs_node;
        }
        publish_fragment(token, len, uint4(kind, target_decl, value, op), aux);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_WHILE && hir_kind[node] == HIR_WHILE_STMT)
    {
        uint condition_node = INVALID;
        uint open_len = 0u;
        uint close_token = INVALID;
        uint close_len = 0u;
        if (!while_open_fragment_and_len(node, condition_node, open_len) ||
            !while_close_token_and_len(node, close_token, close_len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }
        add_func_body_len(owner_fn, open_len + close_len);
        publish_fragment(
            token,
            open_len,
            uint4(BODY_FRAGMENT_WHILE_OPEN_I32, condition_node, open_len, token),
            uint4(INVALID, 0u, 0u, 0u));
        publish_fragment(
            close_token,
            close_len,
            uint4(BODY_FRAGMENT_WHILE_CLOSE, 0u, 0u, close_token),
            uint4(INVALID, 0u, 0u, 0u));
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, close_token);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_FOR &&
        (hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT))
    {
        uint binding_token = INVALID;
        uint range_node = INVALID;
        uint end_local_token = INVALID;
        uint open_len = 0u;
        uint close_token = INVALID;
        uint close_len = 0u;
        if (!for_open_range_fragment_and_len(
                node,
                binding_token,
                range_node,
                end_local_token,
                open_len) ||
            !for_close_token_and_len(node, close_token, close_len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }
        add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
        add_func_local_token(owner_fn, hir_token_end[range_node]);
        add_func_body_len(owner_fn, open_len + close_len);
        publish_fragment(
            token,
            open_len,
            uint4(
                BODY_FRAGMENT_FOR_OPEN_RANGE_I32,
                binding_token,
                range_node,
                end_local_token),
            uint4(INVALID, 0u, 0u, 0u));
        publish_fragment(
            close_token,
            close_len,
            uint4(BODY_FRAGMENT_FOR_CLOSE_RANGE_I32, binding_token, close_len, close_token),
            uint4(INVALID, 0u, 0u, 0u));
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, close_token);
        return;
    }

    if ((stmt_kind == STMT_RECORD_KIND_BREAK && hir_kind[node] == HIR_BREAK_STMT) ||
        (stmt_kind == STMT_RECORD_KIND_CONTINUE && hir_kind[node] == HIR_CONTINUE_STMT))
    {
        uint depth = 0u;
        uint len = 0u;
        if (!loop_control_fragment_and_len(node, depth, len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }
        add_func_body_len(owner_fn, len);
        publish_fragment(
            token,
            len,
            uint4(BODY_FRAGMENT_BRANCH, depth, len, token),
            uint4(INVALID, 0u, 0u, 0u));
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, token);
        return;
    }

    publish_func_invalid(owner_fn, token);
}

void validate_main_call(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (!statement_position_call(node))
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    uint len = 0u;
    uint decl_token = INVALID;
    uint expr_node = INVALID;
    uint value = 0u;
    if (!print_call_node(node))
    {
        return;
    }
    if (print_call_direct_call_and_len(node, expr_node, len) ||
        print_call_expr_and_len(node, expr_node, len))
    {
        atomic_u32_add(body_plan, BODY_PLAN_PRINT_COUNT_AGG, 1u);
        add_func_body_len(owner_fn, len);
        atomic_u32_max(body_plan, BODY_PLAN_PRINT_MAX_TOKEN, token);
        uint kind = BODY_FRAGMENT_PRINT_EXPR_I64;
        uint4 aux = uint4(INVALID, 0u, 0u, 0u);
        if (print_call_direct_call_and_len(node, expr_node, len))
        {
            kind = BODY_FRAGMENT_PRINT_DIRECT_CALL_I64;
            aux = direct_call_aux(expr_node);
        }
        publish_fragment(token, len, uint4(kind, expr_node, len, token), aux);
        return;
    }
    if (!print_call_value_and_len(node, value, len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }
    if (expr_mentions_local_let(call_arg0_node(node)))
        atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);

    atomic_u32_add(body_plan, BODY_PLAN_PRINT_COUNT_AGG, 1u);
    add_func_body_len(owner_fn, len);
    atomic_u32_max(body_plan, BODY_PLAN_PRINT_MAX_TOKEN, token);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_PRINT_I64, value, len, token),
        uint4(INVALID, 0u, 0u, 0u));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] != 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    uint token = hir_token_pos[node];
    validate_main_statement(node, token);

    if (hir_kind[node] == HIR_CALL_EXPR)
        validate_main_call(node, token);
}
