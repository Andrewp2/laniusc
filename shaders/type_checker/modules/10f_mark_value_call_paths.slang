// GPU HIR value-path context marker for qualified value path consumers.
//
// Scheduling contract:
// - Dispatch after type_check_modules_10d_clear_type_path_types.slang.
// - This pass marks HIR path-expression heads whose enclosing HIR name
//   expression is a value expression. The value-path projection consumes this
//   marker to distinguish value paths from module/import metadata paths. A
//   second marker identifies the subset followed by a sibling HIR call
//   expression.
// - It does not inspect source bytes, hash token text, resolve names, or
//   perform any CPU lookup.

import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_start;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> module_value_path_call_head;
RWStructuredBuffer<uint> module_value_path_call_open;
RWStructuredBuffer<uint> module_value_path_call_path_id;
RWStructuredBuffer<uint> module_value_path_call_leaf;
RWStructuredBuffer<uint> module_value_path_associated_method_token;
RWStructuredBuffer<uint> module_value_path_associated_receiver_token;
RWStructuredBuffer<uint> module_value_path_expr_head;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_NONE = 0u;
static const uint HIR_TYPE = 5u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_PATH_EXPR = 33u;
static const uint MAX_PATH_SEGMENTS = 9u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint parser_hir_node_count()
{
    return gParams.n_hir_nodes;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_hir_node(uint node)
{
    return node != INVALID && node < parser_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool metadata_path_context_step(inout uint node, uint active_count, out bool done)
{
    done = true;
    if (node == INVALID || node >= active_count)
        return false;
    uint kind = hir_kind[node];
    if (kind == HIR_MODULE_ITEM || kind == HIR_IMPORT_ITEM || kind == HIR_TYPE)
        return true;
    if (kind != HIR_NONE)
        return false;
    node = parent[node];
    done = false;
    return false;
}

bool metadata_path_context(uint node)
{
    uint active_count = active_hir_node_count();
    bool done = false;

    bool found = metadata_path_context_step(node, active_count, done);
    if (found || done)
        return found;
    found = metadata_path_context_step(node, active_count, done);
    if (found || done)
        return found;
    found = metadata_path_context_step(node, active_count, done);
    if (found || done)
        return found;
    found = metadata_path_context_step(node, active_count, done);
    return found;
}

void mark_call_head(uint owner_token, uint call_node)
{
    if (!valid_token(owner_token))
        return;

    uint encoded_call_node = valid_hir_node(call_node) ? call_node + 1u : 1u;
    atomic_u32_max(module_value_path_call_head, owner_token, encoded_call_node);
}

uint path_leaf_token(uint path_i)
{
    if (path_i == INVALID || path_i >= gParams.n_hir_nodes)
        return INVALID;
    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (count == 0u)
        return INVALID;
    uint slot = path_segment_base[path_i] + count - 1u;
    return slot < gParams.n_tokens * MAX_PATH_SEGMENTS ? path_segment_token[slot] : INVALID;
}

uint call_leaf_token_for_path(uint path_i)
{
    return path_leaf_token(path_i);
}

uint path_segment_token_at(uint path_i, uint segment_i)
{
    if (path_i == INVALID || path_i >= gParams.n_hir_nodes)
        return INVALID;
    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (segment_i >= count)
        return INVALID;
    uint slot = path_segment_base[path_i] + segment_i;
    return slot < gParams.n_tokens * MAX_PATH_SEGMENTS ? path_segment_token[slot] : INVALID;
}

uint type_path_leaf_token(uint type_node, uint fallback_path_i, uint fallback_token)
{
    uint leaf_node = valid_node(type_node) ? hir_type_path_leaf_node[type_node] : INVALID;
    uint leaf_token = valid_node(leaf_node) ? hir_token_pos[leaf_node] : INVALID;
    if (valid_token(leaf_token))
        return leaf_token;
    leaf_token = fallback_path_i != INVALID && fallback_path_i < gParams.n_hir_nodes
        ? path_leaf_token(fallback_path_i)
        : INVALID;
    return valid_token(leaf_token) ? leaf_token : fallback_token;
}

uint path_id_for_callee_node(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;

    if (hir_kind[callee_node] == HIR_PATH_EXPR || hir_kind[callee_node] == HIR_TYPE)
    {
        uint path_i = path_id_by_owner_hir[callee_node];
        return path_i != INVALID && path_i < gParams.n_hir_nodes ? path_i : INVALID;
    }

    if (hir_kind[callee_node] == HIR_NAME_EXPR)
    {
        uint child = first_child[callee_node];
        if (valid_node(child) && (hir_kind[child] == HIR_PATH_EXPR || hir_kind[child] == HIR_TYPE))
        {
            uint path_i = path_id_by_owner_hir[child];
            return path_i != INVALID && path_i < gParams.n_hir_nodes ? path_i : INVALID;
        }
    }

    return INVALID;
}

void mark_associated_receiver_span(uint owner_token, uint method_token)
{
    if (!valid_token(owner_token) || !valid_token(method_token) || owner_token >= method_token)
        return;

    [loop]
    for (uint token = owner_token; token < method_token; token += 1u)
        module_value_path_associated_method_token[token] = method_token;
}

uint receiver_token_for_associated_path(uint path_i, uint method_token)
{
    if (path_i == INVALID || path_i >= gParams.n_hir_nodes)
        return INVALID;
    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (count == 0u)
        return INVALID;
    uint leaf_token = path_segment_token_at(path_i, count - 1u);
    if (method_token == leaf_token && count > 1u)
        return path_segment_token_at(path_i, count - 2u);
    return leaf_token;
}

uint hir_callee_leaf_token(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;

    uint start = hir_token_pos[callee_node];
    uint end = hir_token_end[callee_node];
    if (!valid_token(start) || end == INVALID || end <= start || end > gParams.n_tokens)
        return INVALID;

    for (uint step = 1u; step <= 32u; step += 1u)
    {
        if (step > end - start)
            return INVALID;
        uint token = end - step;
        if (valid_token(token) && name_id_by_token[token] != INVALID)
            return token;
    }

    return INVALID;
}

uint call_leaf_token_for_callee_path(uint path_i, uint callee_node)
{
    uint path_leaf = path_leaf_token(path_i);
    uint hir_leaf = hir_callee_leaf_token(callee_node);
    if (valid_token(hir_leaf) && hir_leaf != path_leaf)
        return hir_leaf;
    return path_leaf;
}

bool mark_path_call(uint path_i, uint call_node, uint leaf_token)
{
    if (path_i == INVALID || path_i >= gParams.n_hir_nodes)
        return false;

    uint owner_token = path_owner_token[path_i];
    uint call_token = valid_hir_node(call_node) ? hir_token_pos[call_node] : INVALID;
    if (!valid_token(owner_token) || !valid_token(call_token))
        return false;

    module_value_path_expr_head[owner_token] = 1u;
    mark_call_head(owner_token, call_node);
    module_value_path_call_open[owner_token] = call_token;
    module_value_path_call_path_id[owner_token] = path_i;
    module_value_path_call_path_id[call_token] = path_i;
    if (valid_token(leaf_token))
    {
        module_value_path_call_path_id[leaf_token] = path_i;
        module_value_path_call_leaf[leaf_token] = 1u;
        if (leaf_token != owner_token)
        {
            uint receiver_token = receiver_token_for_associated_path(path_i, leaf_token);
            mark_associated_receiver_span(owner_token, leaf_token);
            module_value_path_associated_method_token[owner_token] = leaf_token;
            module_value_path_associated_method_token[leaf_token] = leaf_token;
            module_value_path_associated_receiver_token[leaf_token] = receiver_token;
            if (valid_token(receiver_token))
                module_value_path_call_path_id[receiver_token] = path_i;
        }
    }
    return true;
}

bool mark_hir_call(uint call_node)
{
    if (!valid_hir_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_node = hir_call_callee_node[call_node];
    uint path_i = path_id_for_callee_node(callee_node);
    return mark_path_call(path_i, call_node, call_leaf_token_for_callee_path(path_i, callee_node));
}

uint call_expr_for_callee_anchor(uint callee_anchor)
{
    if (!valid_node(callee_anchor))
        return INVALID;

    uint owner = parent[callee_anchor];
    if (valid_node(owner) &&
        hir_kind[owner] == HIR_CALL_EXPR &&
        hir_call_callee_node[owner] == callee_anchor)
        return owner;

    uint child = first_child[callee_anchor];
    if (valid_node(child) &&
        hir_kind[child] == HIR_CALL_EXPR &&
        hir_call_callee_node[child] == callee_anchor)
        return child;

    uint sibling = next_sibling[callee_anchor];
    return valid_node(sibling) && hir_kind[sibling] == HIR_CALL_EXPR ? sibling : INVALID;
}

uint call_expr_for_enclosing_callee(uint node)
{
    uint cursor = node;
    for (uint step = 0u; step < 8u; step += 1u)
    {
        uint call_expr = call_expr_for_callee_anchor(cursor);
        if (valid_hir_node(call_expr))
            return call_expr;

        uint owner = valid_node(cursor) ? parent[cursor] : INVALID;
        if (!valid_node(owner) || owner == cursor)
            return INVALID;
        cursor = owner;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= parser_hir_node_count())
        return;
    if (hir_kind[i] == HIR_CALL_EXPR)
    {
        mark_hir_call(i);
        return;
    }
    if (i >= active_hir_node_count())
        return;
    if (hir_kind[i] != HIR_PATH_EXPR && hir_kind[i] != HIR_TYPE)
        return;

    uint token_i = hir_token_pos[i];
    uint end_i = hir_token_end[i];
    if (token_i == INVALID || end_i == INVALID || token_i >= gParams.n_tokens ||
        token_i >= end_i)
        return;

    uint path_i = path_id_by_owner_hir[i];
    uint callee_anchor = i;
    uint name_expr = parent[i];
    uint name_parent = INVALID;
    if (name_expr != INVALID && name_expr < active_hir_node_count() &&
        hir_kind[name_expr] == HIR_NAME_EXPR)
    {
        callee_anchor = name_expr;
        name_parent = parent[name_expr];
    }
    else
    {
        name_parent = parent[i];
    }
    if (name_parent == INVALID || name_parent >= active_hir_node_count())
        return;
    if (metadata_path_context(name_parent))
        return;
    uint parent_kind = hir_kind[name_parent];

    module_value_path_expr_head[token_i] = 1u;

    uint call_expr = call_expr_for_enclosing_callee(callee_anchor);
    if (valid_hir_node(call_expr) && hir_kind[call_expr] == HIR_CALL_EXPR)
    {
        uint call_callee = hir_call_callee_node[call_expr];
        mark_path_call(path_i, call_expr, call_leaf_token_for_callee_path(path_i, call_callee));
    }
}
