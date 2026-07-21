// Plan scalar if/while conditions entirely from dense compact-HIR identities.

import atomics;
import gpu_index;
import compact_expr_common;
import compact_expr_byte_common;

StructuredBuffer<uint> status;
RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;
StructuredBuffer<uint> compact_hir_nearest_loop;
StructuredBuffer<int> if_depth;

static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_FOR_STMT = 30u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_WHILE = 6u;
static const uint STMT_RECORD_KIND_FOR = 7u;
static const uint STMT_RECORD_KIND_BREAK = 8u;
static const uint STMT_RECORD_KIND_CONTINUE = 9u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;
static const uint BODY_FRAGMENT_WHILE_CLOSE = 15u;
static const uint BODY_FRAGMENT_IF_ELSE = 17u;
static const uint BODY_FRAGMENT_IF_END = 18u;
static const uint BODY_FRAGMENT_BRANCH = 19u;
static const uint BODY_FRAGMENT_IF_OPEN_EXPR_COMPACT_I32 = 72u;
static const uint BODY_FRAGMENT_WHILE_OPEN_EXPR_COMPACT_I32 = 73u;
static const uint BODY_FRAGMENT_FOR_OPEN_RANGE_COMPACT_I32 = 74u;
static const uint BODY_FRAGMENT_FOR_CLOSE_RANGE_COMPACT_I32 = 75u;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool compact_block_close_token(uint block, out uint close_token)
{
    close_token = INVALID;
    if (!valid_node(block) || compact_hir_core[block].kind != HIR_BLOCK) return false;
    uint end = compact_hir_core[block].token_end;
    if (end == 0u || end == INVALID) return false;
    close_token = end - 1u;
    return valid_token(close_token);
}

void publish_compact_control_fragment(uint token, uint len, uint4 meta)
{
    uint slot = token * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = uint4(INVALID, 0u, 0u, 0u);
}

void publish_compact_control_invalid(uint owner_fn, uint detail)
{
    atomic_u32_add(wasm_func_invalid_count_by_token, owner_fn, 1u);
    atomic_u32_min(wasm_func_detail_by_token, owner_fn, detail);
}

void plan_compact_if(uint node, HirCore core, HirPayload payload, uint owner_fn)
{
    if (core.kind != HIR_IF_STMT || payload.a != STMT_RECORD_KIND_IF) return;
    uint token = core.token_start;
    if (!valid_token(token))
    {
        publish_compact_control_invalid(owner_fn, INVALID);
        return;
    }
    if (body_fragment_len[token * 2u] != 0u) return;

    uint condition = payload.b;
    uint then_block = payload.c;
    uint else_block = payload.d;
    uint condition_len = compact_expr_tree_len(condition);
    uint else_token = INVALID;
    uint end_token = INVALID;
    if (condition_len == 0u || !valid_node(then_block) ||
        (valid_node(else_block) && !compact_block_close_token(then_block, else_token)) ||
        !compact_block_close_token(valid_node(else_block) ? else_block : then_block, end_token))
    {
        publish_compact_control_invalid(owner_fn, token);
        return;
    }

    uint open_len = condition_len + 2u;
    publish_compact_control_fragment(
        token,
        open_len,
        uint4(BODY_FRAGMENT_IF_OPEN_EXPR_COMPACT_I32, condition, open_len, token));
    if (valid_node(else_block))
        publish_compact_control_fragment(
            else_token,
            1u,
            uint4(BODY_FRAGMENT_IF_ELSE, 0u, 0u, else_token));
    publish_compact_control_fragment(
        end_token,
        1u,
        uint4(BODY_FRAGMENT_IF_END, 0u, 0u, end_token));
    atomic_u32_add(
        wasm_func_body_len_by_token,
        owner_fn,
        open_len + 1u + (valid_node(else_block) ? 1u : 0u));
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_EXPR_CONTROL);
}

void plan_compact_while(uint node, HirCore core, HirPayload payload, uint owner_fn)
{
    if (core.kind != HIR_WHILE_STMT || payload.a != STMT_RECORD_KIND_WHILE) return;
    uint token = core.token_start;
    if (!valid_token(token))
    {
        publish_compact_control_invalid(owner_fn, INVALID);
        return;
    }
    if (body_fragment_len[token * 2u] != 0u) return;

    uint condition = payload.b;
    uint body = payload.c;
    uint condition_len = compact_expr_tree_len(condition);
    uint close_token = INVALID;
    if (condition_len == 0u || !compact_block_close_token(body, close_token))
    {
        publish_compact_control_invalid(owner_fn, token);
        return;
    }

    uint open_len = condition_len + 7u;
    publish_compact_control_fragment(
        token,
        open_len,
        uint4(BODY_FRAGMENT_WHILE_OPEN_EXPR_COMPACT_I32, condition, open_len, token));
    publish_compact_control_fragment(
        close_token,
        4u,
        uint4(BODY_FRAGMENT_WHILE_CLOSE, 0u, 0u, close_token));
    atomic_u32_add(wasm_func_body_len_by_token, owner_fn, open_len + 4u);
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_EXPR_CONTROL);
}

bool compact_numeric_range(
    HirPayload statement,
    out uint range,
    out uint start,
    out uint end)
{
    range = statement.c;
    uint root = valid_node(range) ? compact_expr_root[range] : INVALID;
    if (valid_node(root)) range = root;
    start = INVALID;
    end = INVALID;
    if (!valid_node(range)) return false;
    HirPayload range_payload = compact_hir_payload[range];
    if (range_payload.a != HIR_EXPR_RANGE) return false;
    start = range_payload.b;
    end = range_payload.c;
    return valid_node(start) && valid_node(end);
}

void plan_compact_numeric_for(uint node, HirCore core, HirPayload payload, uint owner_fn)
{
    if (core.kind != HIR_FOR_STMT || payload.a != STMT_RECORD_KIND_FOR) return;
    uint range = INVALID;
    uint start = INVALID;
    uint end = INVALID;
    if (!compact_numeric_range(payload, range, start, end)) return;

    uint token = core.token_start;
    uint binding_token = payload.b;
    uint body = payload.d;
    uint end_token = compact_hir_core[range].token_end;
    uint close_token = INVALID;
    uint binding_local = INVALID;
    uint end_local = INVALID;
    uint start_len = compact_expr_tree_len(start);
    uint end_len = compact_expr_tree_len(end);
    bool has_close = compact_block_close_token(body, close_token);
    bool has_binding_local =
        function_non_param_local_index(binding_token, owner_fn, binding_local);
    bool has_end_local = function_non_param_local_index(end_token, owner_fn, end_local);
    if (!valid_token(token) || !valid_token(binding_token) || !valid_token(end_token) ||
        start_len == 0u || end_len == 0u ||
        !has_close || !has_binding_local || !has_end_local)
    {
        publish_compact_control_invalid(owner_fn, valid_token(token) ? token : INVALID);
        return;
    }
    if (body_fragment_len[token * 2u] != 0u) return;

    uint open_len = start_len + local_set_len(binding_local) +
                    end_len + local_set_len(end_local) + 4u +
                    local_get_len(binding_local) + local_get_len(end_local) + 5u;
    uint close_len = local_get_len(binding_local) + local_set_len(binding_local) + 8u;
    publish_compact_control_fragment(
        token,
        open_len,
        uint4(BODY_FRAGMENT_FOR_OPEN_RANGE_COMPACT_I32, binding_local, range, end_local));
    publish_compact_control_fragment(
        close_token,
        close_len,
        uint4(BODY_FRAGMENT_FOR_CLOSE_RANGE_COMPACT_I32, binding_local, close_len, close_token));
    atomic_u32_add(wasm_func_body_len_by_token, owner_fn, open_len + close_len);
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_EXPR_CONTROL);
}

void plan_compact_loop_branch(uint node, HirCore core, HirPayload payload, uint owner_fn)
{
    bool is_break = core.kind == HIR_BREAK_STMT && payload.a == STMT_RECORD_KIND_BREAK;
    bool is_continue =
        core.kind == HIR_CONTINUE_STMT && payload.a == STMT_RECORD_KIND_CONTINUE;
    if (!is_break && !is_continue) return;

    uint token = core.token_start;
    uint loop = valid_node(node) ? compact_hir_nearest_loop[node] : INVALID;
    if (!valid_token(token) || !valid_node(loop))
    {
        publish_compact_control_invalid(owner_fn, valid_token(token) ? token : INVALID);
        return;
    }
    HirCore loop_core = compact_hir_core[loop];
    HirPayload loop_payload = compact_hir_payload[loop];
    bool is_while_loop =
        loop_core.kind == HIR_WHILE_STMT && loop_payload.a == STMT_RECORD_KIND_WHILE;
    bool is_for_loop =
        loop_core.kind == HIR_FOR_STMT && loop_payload.a == STMT_RECORD_KIND_FOR;
    if ((!is_while_loop && !is_for_loop) || !valid_token(loop_core.token_start))
    {
        publish_compact_control_invalid(owner_fn, token);
        return;
    }

    int branch_if_depth = if_depth[token];
    int loop_if_depth = if_depth[loop_core.token_start];
    if (branch_if_depth < loop_if_depth)
    {
        publish_compact_control_invalid(owner_fn, token);
        return;
    }
    uint depth = uint(branch_if_depth - loop_if_depth);
    if (is_break) depth += is_for_loop ? 2u : 1u;
    uint len = 1u + u32_leb_len(depth);
    publish_compact_control_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_BRANCH, depth, len, token));
    atomic_u32_add(wasm_func_body_len_by_token, owner_fn, len);
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_EXPR_CONTROL);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE) return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u) return;

    uint node = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (!valid_node(node)) return;
    HirCore core = compact_hir_core[node];
    if (core.kind != HIR_IF_STMT && core.kind != HIR_WHILE_STMT &&
        core.kind != HIR_FOR_STMT && core.kind != HIR_BREAK_STMT &&
        core.kind != HIR_CONTINUE_STMT) return;
    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn)) return;

    HirPayload payload = compact_hir_payload[node];
    plan_compact_if(node, core, payload, owner_fn);
    plan_compact_while(node, core, payload, owner_fn);
    plan_compact_numeric_for(node, core, payload, owner_fn);
    plan_compact_loop_branch(node, core, payload, owner_fn);
}
