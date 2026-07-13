// Parallel validation and planning for scalar WASM binary let initializers
// where the left operand is a direct call. Argument bytes are sized by the
// scanned call-argument record pipeline, not by this validator.

import atomics;
import body_arg_byte_common;

StructuredBuffer<uint> status;
StructuredBuffer<uint> call_intrinsic_tag;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint TY_BOOL = 2u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 42u;
static const uint HIR_LET_STMT = 8u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_STMT_INVALID_COUNT = 11u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_BINARY_DIRECT = 1u << 5u;
static const uint BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 = 46u;

bool type_is_i32_value(uint ty)
{
    return ty == TY_BOOL || ty == TY_INT || ty == TY_UINT;
}

uint method_member_node_for_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return callee_node;

    callee_node = resolve_expr_node(callee_node);
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR
               ? callee_node
               : INVALID;
}

uint method_receiver_node_for_call(uint call_node)
{
    uint member_node = method_member_node_for_call(call_node);
    if (!valid_node(member_node))
        return INVALID;
    uint receiver_node = hir_member_receiver_node[member_node];
    return valid_node(receiver_node) ? receiver_node : INVALID;
}

bool direct_call_has_receiver_arg(uint call_node, uint fn_token)
{
    if (!valid_token(fn_token))
        return false;
    uint receiver_node = method_receiver_node_for_call(call_node);
    if (!valid_node(receiver_node))
        return false;
    uint explicit_arg_count = hir_call_arg_count[call_node];
    return call_param_count[fn_token] == explicit_arg_count + 1u;
}

bool direct_call_header_aux(uint call_node, out uint4 aux)
{
    aux = uint4(INVALID, 0u, INVALID, 0u);
    call_node = resolve_expr_node(call_node);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!supported_function_token(fn_token))
        return false;

    uint explicit_arg_count = hir_call_arg_count[call_node];
    bool has_receiver_arg = direct_call_has_receiver_arg(call_node, fn_token);
    uint arg_count = explicit_arg_count + (has_receiver_arg ? 1u : 0u);
    if (call_param_count[fn_token] != arg_count)
        return false;

    uint return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    if (!type_is_i32_value(return_ty) && return_ty != TY_FLOAT)
        return false;

    uint wasm_func_index = wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT;
    aux = uint4(wasm_func_index, arg_count, fn_token, 0u);
    return true;
}

uint local_set_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint let_binary_direct_call_op_byte(uint node, uint decl_token)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;

    uint form = expr_form(node);
    if (visible_type_for_token(decl_token) == TY_FLOAT)
    {
        if (form == HIR_EXPR_EQ) return WASM_F32_EQ;
        if (form == HIR_EXPR_NE) return WASM_F32_NE;
        if (form == HIR_EXPR_LT) return WASM_F32_LT;
        if (form == HIR_EXPR_GT) return WASM_F32_GT;
        if (form == HIR_EXPR_LE) return WASM_F32_LE;
        if (form == HIR_EXPR_GE) return WASM_F32_GE;
        if (form == HIR_EXPR_ADD) return WASM_F32_ADD;
        if (form == HIR_EXPR_SUB) return WASM_F32_SUB;
        if (form == HIR_EXPR_MUL) return WASM_F32_MUL;
        if (form == HIR_EXPR_DIV) return WASM_F32_DIV;
        return 0u;
    }
    return expr_binary_op_byte_for_node(node);
}

bool let_binary_direct_call_record(
    uint node,
    uint decl_token,
    out uint call_node,
    out uint expr_node,
    out uint op,
    out uint len_without_args,
    out uint4 aux)
{
    call_node = INVALID;
    expr_node = INVALID;
    op = 0u;
    len_without_args = 0u;
    aux = uint4(INVALID, 0u, INVALID, 0u);
    node = resolve_expr_node(node);
    if (!valid_node(node) || !expr_binary_op_supported(expr_form(node)))
        return false;

    op = let_binary_direct_call_op_byte(node, decl_token);
    if (op == 0u)
        return false;

    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint right_expr_len = 0u;
    bool right_expr = direct_call_arg_expr_and_len(right, right_expr_len);
    call_node = resolve_expr_node(left);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR || !right_expr)
        return false;

    if (!direct_call_header_aux(call_node, aux))
        return false;

    expr_node = right;
    len_without_args = (1u + u32_leb_len(aux.x)) + right_expr_len + 1u;
    return true;
}

void publish_fragment(uint token_i, uint len, uint4 meta, uint4 aux)
{
    uint slot = token_i * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_BINARY_DIRECT);
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

void validate_main_let_binary_direct_call(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }

    uint init_expr = resolve_expr_node(stmt_record_slot(node, 2u));
    if (!valid_node(init_expr) || !expr_binary_op_supported(expr_form(init_expr)))
        return;

    uint left = resolve_expr_node(expr_record_slot(init_expr, EXPR_RECORD_LEFT));
    if (!valid_node(left) || hir_kind[left] != HIR_CALL_EXPR)
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }
    if (body_fragment_len[token * 2u] != 0u)
        return;

    uint decl_token = stmt_record_slot(node, 1u);
    uint call_node = INVALID;
    uint expr_node = INVALID;
    uint op = 0u;
    uint len_without_args = 0u;
    uint4 aux = uint4(INVALID, 0u, INVALID, 0u);
    if (!valid_token(decl_token) ||
        !let_binary_direct_call_record(
            init_expr,
            decl_token,
            call_node,
            expr_node,
            op,
            len_without_args,
            aux))
    {
        return;
    }

    uint local_ty = visible_type_for_token(decl_token);
    if (local_ty == TY_UNKNOWN)
        local_ty = local_decl_initializer_expr_type(init_expr);
    if (local_ty == TY_UNKNOWN)
        local_ty = TY_INT;

    uint local_index = INVALID;
    if (!function_non_param_local_index_for_type(decl_token, owner_fn, local_ty, local_index))
        return;

    uint len = len_without_args + local_set_len(local_index);
    add_func_local_token(owner_fn, decl_token);
    add_func_body_len(owner_fn, len);
    aux.w = op;
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32, local_index, call_node, expr_node),
        aux);
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
    if (!valid_node(node) || hir_kind[node] != HIR_LET_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_let_binary_direct_call(node, hir_token_pos[node]);
}
