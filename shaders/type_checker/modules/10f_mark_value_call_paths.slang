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

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_start;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;

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
static const uint TK_LPAREN = 4u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_COLON = 38u;
static const uint TK_PATH_COLON = 114u;

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
    return hir_status[5u];
}

uint token_kind(uint token_i)
{
    return token_i < gParams.n_tokens ? token_words[token_i].kind : 0u;
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

bool path_colon(uint kind)
{
    return kind == TK_COLON || kind == TK_PATH_COLON;
}

bool call_open(uint kind)
{
    return kind == TK_LPAREN || kind == TK_CALL_LPAREN || kind == TK_GROUP_LPAREN;
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

uint associated_type_method_token(uint type_node)
{
    if (!valid_node(type_node) || hir_kind[type_node] != HIR_TYPE)
        return INVALID;

    uint cursor = hir_token_end[type_node];
    if (!valid_token(cursor + 3u))
        return INVALID;
    if (!path_colon(token_kind(cursor)) || !path_colon(token_kind(cursor + 1u)))
        return INVALID;
    uint method_token = cursor + 2u;
    uint call_open_token = method_token + 1u;
    return call_open(token_kind(call_open_token)) ? method_token : INVALID;
}

uint associated_method_token_before_call_open(uint call_open_token)
{
    if (!valid_token(call_open_token) || call_open_token < 3u)
        return INVALID;
    uint method_token = call_open_token - 1u;
    if (method_token < 2u ||
        !path_colon(token_kind(method_token - 2u)) ||
        !path_colon(token_kind(method_token - 1u)))
        return INVALID;
    return method_token;
}

void mark_associated_receiver_span(uint owner_token, uint method_token)
{
    if (!valid_token(owner_token) || !valid_token(method_token) || owner_token >= method_token)
        return;

    [loop]
    for (uint token = owner_token; token < method_token; token += 1u)
        module_value_path_associated_method_token[token] = method_token;
}

bool mark_associated_type_call(uint type_node, uint owner_token, uint path_i)
{
    uint method_token = associated_type_method_token(type_node);
    if (!valid_token(method_token) || method_token == owner_token)
        return false;

    uint call_open_token = method_token + 1u;
    uint receiver_token = type_path_leaf_token(type_node, path_i, owner_token);

    module_value_path_call_head[owner_token] = 1u;
    module_value_path_call_open[owner_token] = call_open_token;
    mark_associated_receiver_span(owner_token, method_token);
    module_value_path_associated_method_token[owner_token] = method_token;
    module_value_path_associated_method_token[receiver_token] = method_token;
    module_value_path_associated_receiver_token[method_token] = receiver_token;
    if (path_i != INVALID && path_i < gParams.n_hir_nodes)
    {
        module_value_path_call_path_id[owner_token] = path_i;
        module_value_path_call_path_id[receiver_token] = path_i;
        module_value_path_call_path_id[call_open_token] = path_i;
        module_value_path_call_path_id[method_token] = path_i;
    }
    module_value_path_call_leaf[method_token] = 1u;
    module_value_path_call_leaf[owner_token] = 1u;
    return true;
}

uint associated_expr_method_token(uint call_node)
{
    if (!valid_hir_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint first_arg = hir_call_arg_start[call_node];
    if (valid_hir_node(first_arg))
    {
        uint first_arg_token = hir_token_pos[first_arg];
        uint method_token = first_arg_token > 0u
            ? associated_method_token_before_call_open(first_arg_token - 1u)
            : INVALID;
        if (valid_token(method_token))
            return method_token;
    }

    uint callee_node = hir_call_callee_node[call_node];
    if (valid_hir_node(callee_node))
    {
        uint callee_end = hir_token_end[callee_node];
        uint method_token = associated_method_token_before_call_open(callee_end);
        if (valid_token(method_token))
            return method_token;
        method_token = callee_end != INVALID && callee_end > 0u
            ? associated_method_token_before_call_open(callee_end - 1u)
            : INVALID;
        if (valid_token(method_token))
            return method_token;
    }

    return INVALID;
}

bool mark_associated_expr_call(uint call_node)
{
    uint owner_token = hir_token_pos[call_node];
    if (!valid_token(owner_token))
        return false;

    uint method_token = associated_expr_method_token(call_node);
    if (!valid_token(method_token) || method_token == owner_token)
        return false;

    uint path_i = path_id_by_owner_token[owner_token];
    uint receiver_token = path_leaf_token(path_i);
    if (!valid_token(receiver_token))
        receiver_token = owner_token;
    uint call_open_token = method_token + 1u;

    module_value_path_call_head[owner_token] = 1u;
    module_value_path_call_open[owner_token] = call_open_token;
    mark_associated_receiver_span(owner_token, method_token);
    module_value_path_associated_method_token[owner_token] = method_token;
    module_value_path_associated_method_token[receiver_token] = method_token;
    module_value_path_associated_receiver_token[method_token] = receiver_token;
    if (path_i != INVALID && path_i < gParams.n_hir_nodes)
    {
        module_value_path_call_path_id[owner_token] = path_i;
        module_value_path_call_path_id[receiver_token] = path_i;
        module_value_path_call_path_id[call_open_token] = path_i;
        module_value_path_call_path_id[method_token] = path_i;
    }
    module_value_path_call_leaf[method_token] = 1u;
    return true;
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
        mark_associated_expr_call(i);
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
    if (hir_kind[i] == HIR_TYPE && mark_associated_type_call(i, token_i, path_i))
        return;

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

    uint call_expr = INVALID;
    if (parent_kind == HIR_CALL_EXPR && hir_call_callee_node[name_parent] == callee_anchor)
        call_expr = name_parent;
    else
        call_expr = next_sibling[callee_anchor];

    if (call_expr != INVALID && call_expr < active_hir_node_count() &&
        hir_kind[call_expr] == HIR_CALL_EXPR)
    {
        module_value_path_call_head[token_i] = 1u;
        module_value_path_call_open[token_i] = end_i - 1u;
        if (path_i != INVALID && path_i < gParams.n_hir_nodes)
        {
            module_value_path_call_path_id[end_i - 1u] = path_i;
            uint leaf = call_leaf_token_for_path(path_i);
            if (leaf < gParams.n_tokens)
            {
                module_value_path_call_path_id[leaf] = path_i;
                module_value_path_call_leaf[leaf] = 1u;
            }
        }
    }
}
