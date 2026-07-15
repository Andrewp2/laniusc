// Parallel validation and planning for statement-position direct calls.
// Argument bytes are sized and validated by the scanned direct-call record
// pipeline, not by this validator.

import atomics;
import body_arg_byte_common;
import call_relocation;

StructuredBuffer<uint> status;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> hir_call_context_stmt_node;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint WASM_IMPORT_FUNCTION_COUNT = 42u;
static const uint HIR_STMT = 7u;
static const uint INTRINSIC_TEXT_WRITE = 1u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_STMT_INVALID_COUNT = 11u;
static const uint BODY_PLAN_PRINT_COUNT_AGG = 17u;
static const uint BODY_PLAN_PRINT_MAX_TOKEN = 19u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_DIRECT = 1u << 1u;
static const uint BODY_FEATURE_STMT_PRINT_DIRECT = 1u << 22u;
static const uint BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 = 23u;
static const uint BODY_FRAGMENT_DIRECT_CALL_VOID = 59u;
static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;

bool type_is_i32_value(uint ty)
{
    return ty == TY_BOOL || ty == TY_INT || ty == TY_UINT;
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

uint print_call_arg0_node(uint call_node)
{
    if (!print_call_node(call_node))
        return INVALID;
    return direct_call_arg_node(call_node, 0u);
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
    if (!supported_call_target_token(fn_token))
        return false;

    uint explicit_arg_count = hir_call_arg_count[call_node];
    bool has_receiver_arg = direct_call_has_receiver_arg(call_node, fn_token);
    uint arg_count = explicit_arg_count + (has_receiver_arg ? 1u : 0u);
    if (call_param_count[fn_token] != arg_count)
        return false;

    uint return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    if (!type_is_i32_value(return_ty))
        return false;

    uint wasm_func_index = wasm_call_target_for_call(call_node, fn_token);
    aux = uint4(wasm_func_index, arg_count, fn_token, 0u);
    return true;
}

bool direct_void_call_header_aux(uint call_node, out uint4 aux)
{
    aux = uint4(INVALID, 0u, INVALID, 0u);
    call_node = resolve_expr_node(call_node);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    uint return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    if (!supported_call_target_token(fn_token) ||
        (return_ty != TY_UNKNOWN && return_ty != TY_VOID))
        return false;

    uint explicit_arg_count = hir_call_arg_count[call_node];
    bool has_receiver_arg = direct_call_has_receiver_arg(call_node, fn_token);
    uint arg_count = explicit_arg_count + (has_receiver_arg ? 1u : 0u);
    if (call_param_count[fn_token] != arg_count)
        return false;

    aux = uint4(wasm_call_target_for_call(call_node, fn_token), arg_count, fn_token, 0u);
    return true;
}

uint print_direct_call_tail_len(uint4 aux)
{
    return 1u + wasm_call_index_len(aux.x) + 3u;
}

void publish_fragment(uint token_i, uint len, uint4 meta, uint4 aux)
{
    uint slot = token_i * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_STMT_PRINT_DIRECT);
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

    if (!print_call_node(node))
    {
        uint4 direct_aux = uint4(INVALID, 0u, INVALID, 0u);
        if (!direct_void_call_header_aux(node, direct_aux))
            return;

        // Publish only the fixed call tail here. One dense record per ABI
        // argument validates and sizes argument bytes in parallel; the direct
        // call finalizer adds their scanned byte total to this provisional
        // length and to the owning function body.
        uint len = 1u + wasm_call_index_len(direct_aux.x);
        add_func_body_len(owner_fn, len);
        uint slot = token * 2u;
        body_fragment_len[slot] = len;
        body_fragment_meta[slot] = uint4(BODY_FRAGMENT_DIRECT_CALL_VOID, node, len, token);
        body_fragment_aux[slot] = direct_aux;
        atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_DIRECT);
        return;
    }

    uint arg0 = resolve_expr_node(print_call_arg0_node(node));
    if (!valid_node(arg0) || hir_kind[arg0] != HIR_CALL_EXPR)
        return;

    uint4 aux = uint4(INVALID, 0u, INVALID, 0u);
    if (!direct_call_header_aux(arg0, aux))
    {
        publish_func_invalid(owner_fn, hir_token_pos[arg0]);
        return;
    }

    uint len = print_direct_call_tail_len(aux);
    atomic_u32_add(body_plan, BODY_PLAN_PRINT_COUNT_AGG, 1u);
    add_func_body_len(owner_fn, len);
    atomic_u32_max(body_plan, BODY_PLAN_PRINT_MAX_TOKEN, token);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_PRINT_DIRECT_CALL_I64, arg0, len, token),
        aux);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_call(node, hir_token_pos[node]);
}
