// Parallel pre-validation collection for facts fragment validation must read.
//
// Function discovery owns function counting and reachability. This pass runs
// after that discovery and before fragment validation so statement lanes can
// read completed per-function local bounds when computing typed WASM locals.

import atomics;
import body_common;

StructuredBuffer<uint> status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_prefix_before_node;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_subtree_end;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint> hir_semantic_first_child;
StructuredBuffer<uint> hir_semantic_next_sibling;
StructuredBuffer<uint> hir_semantic_depth;
StructuredBuffer<uint> hir_semantic_child_index;
RWStructuredBuffer<uint> body_plan;

static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_PLAN_SEMANTIC_MAX_DEPTH = 36u;
static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;
static const uint BODY_FEATURE_DIRECT = 1u << 1u;
static const uint BODY_FEATURE_HOST = 1u << 2u;
static const uint BODY_FEATURE_ARRAYS = 1u << 3u;
static const uint BODY_FEATURE_MEMBER_EXPR = 1u << 4u;
static const uint BODY_FEATURE_BINARY_DIRECT = 1u << 5u;
static const uint BODY_FEATURE_LET_DIRECT = 1u << 6u;
static const uint BODY_FEATURE_RETURN_DIRECT = 1u << 8u;
static const uint BODY_FEATURE_LET_AGG_DIRECT = 1u << 9u;
static const uint BODY_FEATURE_RETURN_AGG_DIRECT = 1u << 10u;
static const uint BODY_FEATURE_AGG_COPY = 1u << 11u;
static const uint BODY_FEATURE_ARRAY_ALLOC = 1u << 12u;

uint active_semantic_hir_count()
{
    return min(hir_semantic_count[0u], active_hir_node_count());
}

bool valid_semantic_hir_row(uint row)
{
    return row != INVALID && row < active_semantic_hir_count();
}

bool semantic_hir_row_for_node(uint node, out uint row)
{
    row = INVALID;
    if (!valid_node(node))
        return false;
    uint candidate = hir_semantic_prefix_before_node[node];
    if (!valid_semantic_hir_row(candidate))
        return false;
    if (hir_semantic_dense_node[candidate] != node)
        return false;
    row = candidate;
    return true;
}

bool call_is_let_initializer(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint context = hir_call_context_stmt_node[call_node];
    return valid_node(context) &&
           hir_kind[context] == HIR_LET_STMT &&
           stmt_record_slot(context, 0u) == STMT_RECORD_KIND_LET &&
           resolve_expr_node(stmt_record_slot(context, 2u)) == resolve_expr_node(call_node);
}

bool call_is_return_value(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint context = hir_call_context_stmt_node[call_node];
    return valid_node(context) &&
           hir_kind[context] == HIR_RETURN_STMT &&
           stmt_record_slot(context, 0u) == STMT_RECORD_KIND_RETURN &&
           resolve_expr_node(stmt_record_slot(context, 1u)) == resolve_expr_node(call_node);
}

bool token_has_host_language_name(uint token)
{
    if (!valid_token(token))
        return false;

    uint name_id = name_id_by_token[token];
    for (uint symbol = LANGUAGE_SYMBOL_OPEN_READ_PATH; symbol <= LANGUAGE_SYMBOL_READ_STDIN; symbol += 1u)
    {
        if (symbol == 28u || symbol == 29u)
            continue;
        if (language_name_id[symbol] == name_id)
            return true;
    }
    return false;
}

bool known_host_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token))
        fn_token = callee_token;

    return token_has_host_language_name(callee_token) ||
           token_has_host_language_name(fn_token);
}

bool potential_user_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    return supported_function_token(fn_token);
}

bool user_call_return_type(uint call_node, out uint return_ty)
{
    return_ty = TY_UNKNOWN;
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!supported_function_token(fn_token))
        return false;

    return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    return true;
}

uint collect_feature_mask(uint node)
{
    if (!valid_node(node))
        return 0u;

    uint kind = hir_kind[node];
    if (kind == HIR_ARRAY_EXPR)
        return BODY_FEATURE_ARRAYS | BODY_FEATURE_ARRAY_ALLOC | BODY_FEATURE_MEMBER_EXPR;
    if (kind == HIR_STRUCT_LITERAL_EXPR)
        return BODY_FEATURE_ARRAY_ALLOC | BODY_FEATURE_MEMBER_EXPR;
    if (kind == HIR_MEMBER_EXPR)
        return BODY_FEATURE_MEMBER_EXPR;
    if (kind == HIR_IF_STMT || kind == HIR_WHILE_STMT || kind == HIR_FOR_STMT)
        return BODY_FEATURE_EXPR_CONTROL;
    if (kind == HIR_STMT && stmt_record_slot(node, 0u) == STMT_RECORD_KIND_ASSIGN)
        return BODY_FEATURE_EXPR_CONTROL;

    if (kind == HIR_CALL_EXPR)
    {
        uint fn_token = INVALID;
        uint wasm_func_index = INVALID;
        uint arg_count = 0u;
        uint mask = 0u;
        if (print_call_node(node))
            mask |= BODY_FEATURE_EXPR_CONTROL;
        uint return_ty = TY_UNKNOWN;
        bool is_user_call = user_call_return_type(node, return_ty);
        bool is_aggregate_return = is_user_call && return_ty >= TY_ARRAY_BASE;
        if (direct_user_call_node(node, fn_token, wasm_func_index, arg_count) ||
            potential_user_call_node(node))
        {
            if (call_is_let_initializer(node) && is_aggregate_return)
                mask |= BODY_FEATURE_LET_AGG_DIRECT | BODY_FEATURE_AGG_COPY | BODY_FEATURE_ARRAY_ALLOC;
            else if (call_is_return_value(node) && is_aggregate_return)
                mask |= BODY_FEATURE_RETURN_AGG_DIRECT;
            else
                mask |= call_is_let_initializer(node)
                            ? BODY_FEATURE_LET_DIRECT
                            : (call_is_return_value(node) ? BODY_FEATURE_RETURN_DIRECT : BODY_FEATURE_DIRECT);
        }
        if (known_host_call_node(node))
            mask |= BODY_FEATURE_HOST;
        return mask;
    }

    if (kind == HIR_LET_STMT || kind == HIR_RETURN_STMT)
    {
        uint mask = 0u;
        if (kind == HIR_LET_STMT)
        {
            uint decl_token = stmt_record_slot(node, 1u);
            if (valid_token(decl_token) &&
                (visible_type_for_token(decl_token) >= TY_ARRAY_BASE ||
                 wasm_agg_local_width_by_token[decl_token] != 0u))
            {
                mask |= BODY_FEATURE_ARRAY_ALLOC | BODY_FEATURE_MEMBER_EXPR;
            }
        }
        uint expr_node = resolve_expr_node(stmt_record_slot(node, kind == HIR_LET_STMT ? 2u : 1u));
        if (valid_node(expr_node) && hir_kind[expr_node] == HIR_CALL_EXPR)
        {
            uint fn_token = INVALID;
            uint wasm_func_index = INVALID;
            uint arg_count = 0u;
            uint return_ty = TY_UNKNOWN;
            bool is_user_call = user_call_return_type(expr_node, return_ty);
            bool is_aggregate_return = is_user_call && return_ty >= TY_ARRAY_BASE;
            if (direct_user_call_node(expr_node, fn_token, wasm_func_index, arg_count) ||
                potential_user_call_node(expr_node))
            {
                if (is_aggregate_return)
                    mask |= kind == HIR_LET_STMT
                                ? (BODY_FEATURE_LET_AGG_DIRECT | BODY_FEATURE_AGG_COPY | BODY_FEATURE_ARRAY_ALLOC)
                                : BODY_FEATURE_RETURN_AGG_DIRECT;
                else
                    mask |= kind == HIR_LET_STMT ? BODY_FEATURE_LET_DIRECT : BODY_FEATURE_RETURN_DIRECT;
            }
            if (known_host_call_node(expr_node))
                mask |= BODY_FEATURE_HOST;
        }
        if (valid_node(expr_node) && hir_kind[expr_node] == HIR_ARRAY_EXPR)
            mask |= BODY_FEATURE_ARRAYS | BODY_FEATURE_ARRAY_ALLOC | BODY_FEATURE_MEMBER_EXPR;
        if (valid_node(expr_node) && hir_kind[expr_node] == HIR_MEMBER_EXPR)
            mask |= BODY_FEATURE_MEMBER_EXPR;
        if (kind == HIR_LET_STMT &&
            valid_node(expr_node) &&
            expr_binary_op_supported(expr_form(expr_node)))
        {
            uint left = resolve_expr_node(expr_record_slot(expr_node, EXPR_RECORD_LEFT));
            uint right = resolve_expr_node(expr_record_slot(expr_node, EXPR_RECORD_RIGHT));
            if (valid_node(left) &&
                hir_kind[left] == HIR_CALL_EXPR &&
                potential_user_call_node(left))
            {
                mask |= BODY_FEATURE_BINARY_DIRECT | BODY_FEATURE_MEMBER_EXPR;
            }
        }
        if (kind == HIR_LET_STMT)
        {
            uint decl_token = INVALID;
            uint expr = INVALID;
            uint value = 0u;
            uint len = 0u;
            if (supported_let_const_fragment(node, decl_token, value, len))
                return mask;
            if (supported_let_expr_fragment(node, decl_token, expr, len))
                mask |= BODY_FEATURE_EXPR_CONTROL |
                        (expr_contains_member(expr) ? BODY_FEATURE_MEMBER_EXPR : 0u);
        }
        else
        {
            uint expr = INVALID;
            uint value = 0u;
            uint len = 0u;
            uint decl_token = INVALID;
            if (return_expr_local_and_len(node, decl_token, len) ||
                return_expr_value_and_len(node, value, len))
            {
                return mask;
            }
            if (return_expr_fragment_and_len(node, expr, len))
                mask |= BODY_FEATURE_EXPR_CONTROL |
                        (expr_contains_member(expr) ? BODY_FEATURE_MEMBER_EXPR : 0u);
        }
        return mask;
    }

    return 0u;
}

void collect_body_features(uint node)
{
    uint mask = collect_feature_mask(node);
    if (mask != 0u)
        atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, mask);
}

void collect_semantic_hir_shape(uint node)
{
    uint row = INVALID;
    if (!semantic_hir_row_for_node(node, row))
        return;
    atomic_u32_max(body_plan, BODY_PLAN_SEMANTIC_MAX_DEPTH, hir_semantic_depth[row]);
}

void collect_function_param_row(uint row)
{
    uint row_limit = call_param_row_count_out[0u];
    if (row >= row_limit)
        return;

    uint fn_token = call_param_row_fn_token[row];
    uint ordinal = call_param_row_ordinal[row];
    if (!supported_function_token(fn_token) || ordinal == INVALID)
        return;

    uint ty = call_param_row_type[row];
    if (!type_is_i32_abi_param(fn_token, ordinal, ty) && ty != TY_FLOAT)
    {
        atomic_u32_add(wasm_func_invalid_count_by_token, fn_token, 1u);
        atomic_u32_min(wasm_func_detail_by_token, fn_token, fn_token);
    }
}

void collect_local_decl(uint node)
{
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }

    uint owner_fn = node_enclosing_fn_token(node);
    if (!valid_token(owner_fn))
        return;

    uint decl_token = stmt_record_slot(node, 1u);
    if (!valid_token(decl_token))
        return;

    uint prior = atomic_u32_compare_exchange(
        wasm_func_local_max_by_token,
        owner_fn,
        INVALID,
        decl_token);
    if (prior != INVALID)
        atomic_u32_max(wasm_func_local_max_by_token, owner_fn, decl_token);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;
    if (node >= active_hir_node_count())
        return;

    collect_local_decl(node);
    collect_semantic_hir_shape(node);
    collect_body_features(node);
    collect_function_param_row(node);
}
