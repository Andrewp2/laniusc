// Derive parser-owned call expression and argument metadata from the tree.
//
// This pass consumes production ids plus the inverted tree arrays. It does not
// inspect token neighborhoods, source bytes, helper names, or stdlib names.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirCall;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> hir_call_callee_node;
RWStructuredBuffer<uint> hir_call_arg_start;
RWStructuredBuffer<uint> hir_call_arg_end;
RWStructuredBuffer<uint> hir_call_arg_count;
RWStructuredBuffer<uint> hir_call_arg_parent_call;
RWStructuredBuffer<uint> hir_call_arg_ordinal;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR = 14u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirCall.uses_ll1 != 0u ? min(gHirCall.n, ll1_status[5u]) : gHirCall.n;
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint first_child_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint child = i + 1u;
    return valid_node(child) && parent[child] == i ? child : INVALID;
}

uint previous_sibling_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint p = parent[i];
    if (!valid_node(p))
        return INVALID;

    uint child = first_child_node(p);
    uint prev = INVALID;
    [loop]
    for (uint guard = 0u; guard < 256u && valid_node(child) && parent[child] == p &&
                          child < i;
         guard += 1u)
    {
        prev = child;
        child = subtree_end[child];
    }
    return prev;
}

uint ancestor_with_production(uint i, uint prod)
{
    uint cur = i;
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        uint p = parent[cur];
        if (!valid_node(p))
            return INVALID;
        if (node_kind[p] == prod)
            return p;
        cur = p;
    }
    return INVALID;
}

bool is_postfix_operator(uint prod)
{
    return prod == PROD_POSTFIX_CALL || prod == PROD_POSTFIX_INDEX ||
           prod == PROD_POSTFIX_MEMBER || prod == PROD_POSTFIX_INC ||
           prod == PROD_POSTFIX_DEC;
}

bool is_call_arg_container(uint prod)
{
    return prod == PROD_ARGS_SOME || prod == PROD_ARGS_AFTER_COMMA_MORE;
}

uint first_descendant_with_production(uint i, uint prod)
{
    if (!valid_node(i))
        return INVALID;
    uint end = min(subtree_end[i], active_node_count());
    [loop]
    for (uint j = i + 1u; j < end; j += 1u)
    {
        if (node_kind[j] == prod)
            return j;
    }
    return INVALID;
}

uint callable_head_for_node(uint node)
{
    uint path = first_descendant_with_production(node, PROD_PATH);
    return valid_node(path) ? path : node;
}

bool is_top_level_arg_expr_for_call(uint expr_node, uint call_node)
{
    if (!valid_node(expr_node) || hir_kind[expr_node] != HIR_EXPR)
        return false;

    uint arg_container = parent[expr_node];
    if (!valid_node(arg_container) || !is_call_arg_container(node_kind[arg_container]))
        return false;

    return ancestor_with_production(arg_container, PROD_POSTFIX_CALL) == call_node;
}

uint callee_for_call(uint call_node)
{
    uint p = parent[call_node];
    if (!valid_node(p))
        return INVALID;

    if (node_kind[p] == PROD_POSTFIX)
        return callable_head_for_node(previous_sibling_node(call_node));

    if (is_postfix_operator(node_kind[p]))
        return p;

    return INVALID;
}

uint end_token_for_arg_expr(uint expr_node)
{
    if (!valid_node(expr_node))
        return INVALID;

    uint arg_container = parent[expr_node];
    if (!valid_node(arg_container))
        return INVALID;

    uint next = subtree_end[expr_node];
    uint container_end = min(subtree_end[arg_container], active_node_count());
    if (valid_node(next) && next < container_end && parent[next] == arg_container)
    {
        uint next_pos = hir_token_pos[next];
        if (next_pos != INVALID)
            return next_pos;
    }

    uint end_node = min(subtree_end[expr_node], active_node_count());
    if (end_node > expr_node + 1u)
    {
        uint last_pos = hir_token_pos[end_node - 1u];
        if (last_pos != INVALID)
            return last_pos + 1u;
    }

    uint start = hir_token_pos[expr_node];
    return start == INVALID ? INVALID : start + 1u;
}

void clear_fields(uint i)
{
    hir_call_callee_node[i] = INVALID;
    hir_call_arg_start[i] = INVALID;
    hir_call_arg_end[i] = INVALID;
    hir_call_arg_count[i] = 0u;
    hir_call_arg_parent_call[i] = INVALID;
    hir_call_arg_ordinal[i] = INVALID;
}

void publish_call_expr(uint i)
{
    hir_call_callee_node[i] = callee_for_call(i);

    uint first_arg = INVALID;
    uint arg_count = 0u;
    uint end = min(subtree_end[i], active_node_count());
    [loop]
    for (uint j = i + 1u; j < end; j += 1u)
    {
        if (is_top_level_arg_expr_for_call(j, i))
        {
            if (first_arg == INVALID)
                first_arg = j;
            arg_count += 1u;
        }
    }

    hir_call_arg_start[i] = first_arg;
    hir_call_arg_count[i] = arg_count;
}

void publish_call_arg(uint i)
{
    uint arg_container = parent[i];
    if (!valid_node(arg_container) || !is_call_arg_container(node_kind[arg_container]))
        return;

    uint call_node = ancestor_with_production(arg_container, PROD_POSTFIX_CALL);
    if (!valid_node(call_node))
        return;

    uint ordinal = 0u;
    uint end = min(i, active_node_count());
    [loop]
    for (uint j = call_node + 1u; j < end; j += 1u)
    {
        if (is_top_level_arg_expr_for_call(j, call_node))
            ordinal += 1u;
    }

    hir_call_arg_parent_call[i] = call_node;
    hir_call_arg_ordinal[i] = ordinal;
    hir_call_arg_end[i] = end_token_for_arg_expr(i);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gHirCall.n)
        return;

    clear_fields(i);

    if (!valid_node(i))
        return;

    if (node_kind[i] == PROD_POSTFIX_CALL)
        publish_call_expr(i);

    if (hir_kind[i] == HIR_EXPR)
        publish_call_arg(i);
}
