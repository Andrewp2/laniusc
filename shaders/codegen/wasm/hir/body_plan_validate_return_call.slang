// Parallel validation and planning for scalar WASM return direct-call
// expressions. Argument bytes are sized by the scanned call-argument record
// pipeline, not by this validator.

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
static const uint HIR_RETURN_STMT = 9u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_STMT_INVALID_COUNT = 11u;
static const uint BODY_PLAN_RETURN_VALUE_OK_COUNT = 20u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_BINARY_DIRECT = 1u << 5u;
static const uint BODY_FEATURE_RETURN_DIRECT = 1u << 8u;
static const uint BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 = 24u;
static const uint BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 = 29u;

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

bool return_stmt_node(uint node)
{
    return valid_node(node) &&
           hir_kind[node] == HIR_RETURN_STMT &&
           stmt_record_slot(node, 0u) == STMT_RECORD_KIND_RETURN;
}

uint binary_direct_call_op_byte(uint expr_node)
{
    return expr_binary_op_byte_for_node(expr_node);
}

bool return_binary_direct_call_record(
    uint return_node,
    out uint call_node,
    out uint atom_node,
    out uint op,
    out uint call_side,
    out uint len_without_args,
    out uint4 aux)
{
    call_node = INVALID;
    atom_node = INVALID;
    op = 0u;
    call_side = 0u;
    len_without_args = 0u;
    aux = uint4(INVALID, 0u, INVALID, 0u);

    uint expr = resolve_expr_node(stmt_record_slot(return_node, 1u));
    if (!valid_node(expr) || !expr_binary_op_supported(expr_form(expr)))
        return false;

    op = binary_direct_call_op_byte(expr);
    if (op == 0u)
        return false;

    uint left = expr_record_slot(expr, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(expr, EXPR_RECORD_RIGHT);
    uint left_expr_len = 0u;
    uint right_expr_len = 0u;
    uint left_call = resolve_expr_node(left);
    uint right_call = resolve_expr_node(right);
    bool left_is_call = valid_node(left_call) && hir_kind[left_call] == HIR_CALL_EXPR;
    bool right_is_call = valid_node(right_call) && hir_kind[right_call] == HIR_CALL_EXPR;
    bool left_expr = direct_call_arg_expr_and_len(left, left_expr_len);
    bool right_expr = direct_call_arg_expr_and_len(right, right_expr_len);

    if (left_is_call && right_expr)
    {
        call_node = left_call;
        atom_node = right;
        call_side = 0u;
    }
    else if (right_is_call && left_expr)
    {
        call_node = right_call;
        atom_node = left;
        call_side = 1u;
    }
    else
    {
        return false;
    }

    if (!direct_call_header_aux(call_node, aux))
        return false;

    uint atom_len = call_side == 0u ? right_expr_len : left_expr_len;
    len_without_args = (1u + u32_leb_len(aux.x)) + atom_len + 2u;
    return true;
}

void publish_fragment(uint token_i, uint len, uint4 meta, uint4 aux)
{
    uint slot = token_i * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
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

void validate_main_return_call(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (!return_stmt_node(node))
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }
    if (body_fragment_len[token * 2u] != 0u)
        return;

    uint return_expr_node = resolve_expr_node(stmt_record_slot(node, 1u));
    uint4 aux = uint4(INVALID, 0u, INVALID, 0u);
    if (direct_call_header_aux(return_expr_node, aux))
    {
        uint provisional_len = 1u + u32_leb_len(aux.x) + 1u;
        atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
        add_func_body_len(owner_fn, provisional_len);
        publish_fragment(
            token,
            provisional_len,
            uint4(
                BODY_FRAGMENT_RETURN_DIRECT_CALL_I32,
                return_expr_node,
                provisional_len,
                token),
            aux);
        atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_RETURN_DIRECT);
        return;
    }

    uint call_node = INVALID;
    uint atom_node = INVALID;
    uint op = 0u;
    uint call_side = 0u;
    uint len_without_args = 0u;
    if (return_binary_direct_call_record(
            node,
            call_node,
            atom_node,
            op,
            call_side,
            len_without_args,
            aux))
    {
        atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
        add_func_body_len(owner_fn, len_without_args);
        publish_fragment(
            token,
            len_without_args,
            uint4(
                BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32,
                call_node,
                atom_node,
                op | (call_side << 8u)),
            aux);
        atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_BINARY_DIRECT);
    }
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
    if (!valid_node(node) || hir_kind[node] != HIR_RETURN_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_return_call(node, hir_token_pos[node]);
}
