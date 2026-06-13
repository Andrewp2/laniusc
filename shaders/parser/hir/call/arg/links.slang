// Seed parser-owned call-argument links from grammar tree records.
//
// This pass builds the linked list that Pareas-style pointer jumping consumes:
// every non-first argument points at its previous argument, while first
// arguments carry the owning call as the list root seed.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirCall;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_end;

RWStructuredBuffer<uint> hir_call_arg_end;
RWStructuredBuffer<uint> hir_call_arg_owner_a;
RWStructuredBuffer<uint> hir_call_arg_link_a;
RWStructuredBuffer<uint> hir_call_arg_rank_a;
RWStructuredBuffer<uint> hir_call_arg_owner_b;
RWStructuredBuffer<uint> hir_call_arg_link_b;
RWStructuredBuffer<uint> hir_call_arg_rank_b;

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
    return gHirCall.uses_status_count != 0u ? min(gHirCall.n, tree_count_status[5u]) : gHirCall.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint parent_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint p = parent[node];
    return valid_node(p) ? p : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
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

uint previous_arg_for_after_comma_container(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_ARGS_AFTER_COMMA_MORE)
        return INVALID;

    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return arg_expr_from_container(previous_container);
}

uint owner_seed_for_first_arg_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_ARGS_SOME)
        return INVALID;
    uint call_node = parent_node(container);
    return valid_node(call_node) && node_kind[call_node] == PROD_POSTFIX_CALL
        ? call_node
        : INVALID;
}

uint end_token_for_arg_expr(uint expr_node)
{
    if (!valid_node(expr_node))
        return INVALID;
    return hir_token_end[expr_node];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirCall.n)
        return;

    hir_call_arg_end[node] = INVALID;
    hir_call_arg_owner_a[node] = INVALID;
    hir_call_arg_link_a[node] = INVALID;
    hir_call_arg_rank_a[node] = 0u;
    hir_call_arg_owner_b[node] = INVALID;
    hir_call_arg_link_b[node] = INVALID;
    hir_call_arg_rank_b[node] = 0u;

    if (!valid_node(node) || hir_kind[node] != HIR_EXPR)
        return;

    uint container = parent_node(node);
    if (!valid_node(container) || !is_call_arg_container(node_kind[container]))
        return;
    if (arg_expr_from_container(container) != node)
        return;

    hir_call_arg_end[node] = end_token_for_arg_expr(node);

    if (node_kind[container] == PROD_ARGS_SOME)
    {
        hir_call_arg_owner_a[node] = owner_seed_for_first_arg_container(container);
        return;
    }

    uint previous = previous_arg_for_after_comma_container(container);
    if (valid_node(previous))
    {
        hir_call_arg_link_a[node] = previous;
        hir_call_arg_rank_a[node] = 1u;
    }
}
