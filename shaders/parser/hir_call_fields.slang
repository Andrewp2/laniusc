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
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;

RWStructuredBuffer<uint> hir_call_callee_node;
RWStructuredBuffer<uint> hir_call_context_stmt_node;
RWStructuredBuffer<uint> hir_call_arg_start;
RWStructuredBuffer<uint> hir_call_arg_end;
RWStructuredBuffer<uint> hir_call_arg_count;
RWStructuredBuffer<uint> hir_call_arg_parent_call;

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

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

uint semantic_row_node(uint row)
{
    if (row >= active_semantic_count())
        return INVALID;
    uint node = hir_semantic_dense_node[row];
    return valid_node(node) ? node : INVALID;
}

uint first_child_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint child = first_child[i];
    return valid_node(child) ? child : INVALID;
}

uint previous_sibling_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint previous = prev_sibling[i];
    return valid_node(previous) && parent[previous] == parent[i] ?
        previous :
        INVALID;
}

bool is_postfix_operator(uint prod)
{
    return prod == PROD_POSTFIX_CALL || prod == PROD_POSTFIX_INDEX ||
           prod == PROD_POSTFIX_MEMBER;
}

bool is_call_arg_container(uint prod)
{
    return prod == PROD_ARGS_SOME || prod == PROD_ARGS_AFTER_COMMA_MORE;
}

uint arg_expr_from_container(uint container)
{
    if (!valid_node(container) || !is_call_arg_container(node_kind[container]))
        return INVALID;
    uint expr = first_child_node(container);
    return valid_node(expr) && hir_kind[expr] == HIR_EXPR ? expr : INVALID;
}

uint first_arg_for_call(uint call_node)
{
    if (!valid_node(call_node) || node_kind[call_node] != PROD_POSTFIX_CALL)
        return INVALID;
    uint arg_list = first_child_node(call_node);
    return valid_node(arg_list) && node_kind[arg_list] == PROD_ARGS_SOME
        ? arg_expr_from_container(arg_list)
        : INVALID;
}

uint direct_path_child(uint node)
{
    uint child = first_child_node(node);
    return valid_node(child) && node_kind[child] == PROD_PATH ? child : INVALID;
}

uint callable_head_for_node(uint node)
{
    if (!valid_node(node))
        return INVALID;

    if (node_kind[node] == PROD_PATH)
        return node;

    uint path = direct_path_child(node);
    return valid_node(path) ? path : node;
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

void clear_fields(uint i)
{
    hir_call_callee_node[i] = INVALID;
    hir_call_context_stmt_node[i] = INVALID;
    hir_call_arg_start[i] = INVALID;
    hir_call_arg_end[i] = INVALID;
    hir_call_arg_count[i] = 0u;
    hir_call_arg_parent_call[i] = INVALID;
}

void publish_call_expr(uint i)
{
    hir_call_callee_node[i] = callee_for_call(i);
    hir_call_arg_start[i] = first_arg_for_call(i);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint i = semantic_row_node(row);
    if (i == INVALID)
        return;

    clear_fields(i);
    if (node_kind[i] == PROD_POSTFIX_CALL)
        publish_call_expr(i);
}
