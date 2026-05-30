// Scatter structural predicate-bound argument facts.
//
// Bound predicates use a distinct parse grammar from ordinary HIR type
// expressions, so parser `hir_type_arg_*` records do not describe these rows.
// This pass publishes the nearest bound-argument list owner, supported ordinals,
// and fail-closed structural statuses so predicate semantic collection can avoid
// walking each predicate subtree.
//
// This is still a bounded bridge: owner and ordinal extraction below use capped
// grammar parent walks. If those walks cannot prove the relation, the pass marks
// the predicate unsupported instead of publishing a truncated argument list. Do
// not widen those walks; replace this pass with parser-owned bound-argument rows
// before claiming an unbounded predicate solver.

import atomics;
import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;

RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PARENT_WALK = 128u;

static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH = 11u;
static const uint PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE = 12u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION = 22u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint parent_node(uint node)
{
    return valid_node(node) ? parent[node] : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) && parent_node(child) == node ? child : INVALID;
}

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    return valid_node(sibling) && parent_node(sibling) == parent_node(node)
        ? sibling
        : INVALID;
}

bool bound_expr_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_BOUND_TYPE_IDENT || kind == PROD_BOUND_TYPE_REF;
}

void publish_status(uint owner, uint status)
{
    if (valid_node(owner))
        atomic_u32_min(predicate_status, owner, status);
}

uint enclosing_bound_args_node(uint node, out bool exhausted)
{
    exhausted = false;
    uint cur = parent_node(node);
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        uint kind = node_kind[cur];
        if (kind == PROD_BOUND_TYPE_ARGS_SOME)
            return cur;
        if (kind == PROD_TYPE_PARAM_BOUND_LIST ||
            kind == PROD_TYPE_PARAM_BOUND ||
            kind == PROD_WHERE_TYPE_BOUND)
            return INVALID;
        cur = parent_node(cur);
    }
    exhausted = valid_node(cur);
    return INVALID;
}

bool bound_ident_has_arg_list(uint node)
{
    if (!valid_node(node) || node_kind[node] != PROD_BOUND_TYPE_IDENT)
        return false;

    uint child = first_child_node(node);
    [loop]
    for (uint guard = 0u; guard < 4u && valid_node(child); guard += 1u)
    {
        uint kind = node_kind[child];
        if (kind == PROD_BOUND_TYPE_ARGS_SOME)
            return true;
        if (kind == PROD_BOUND_TYPE_ARGS_NONE)
            return false;
        child = next_sibling_node(child);
    }
    return false;
}

uint bound_arg_ordinal(
    uint arg_node,
    uint args_node,
    out bool valid_ordinal,
    out bool exhausted)
{
    valid_ordinal = false;
    exhausted = false;
    if (!valid_node(arg_node) || !valid_node(args_node))
        return INVALID;

    uint ordinal = 0u;
    uint cur = parent_node(arg_node);
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        if (cur == args_node)
        {
            valid_ordinal = true;
            return ordinal;
        }

        if (node_kind[cur] == PROD_BOUND_TYPE_ARGS_AFTER_COMMA_MORE)
            ordinal += 1u;

        cur = parent_node(cur);
    }
    exhausted = valid_node(cur);
    return INVALID;
}

void publish_arg_node(uint owner, uint ordinal, uint arg_node)
{
    if (!valid_node(owner))
        return;

    atomic_u32_max(predicate_bound_arg_count, owner, ordinal + 1u);
    if (ordinal == 0u)
        predicate_bound_first_arg_token[owner] = arg_node;
    else if (ordinal == 1u)
        predicate_bound_second_arg_token[owner] = arg_node;
    else
        publish_status(owner, PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!bound_expr_node(node))
        return;

    bool owner_walk_exhausted = false;
    uint args_node = enclosing_bound_args_node(node, owner_walk_exhausted);
    if (owner_walk_exhausted)
    {
        publish_status(node, PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION);
        return;
    }

    if (!valid_node(args_node))
        return;

    uint owner = parent_node(args_node);
    if (!bound_expr_node(owner))
        return;

    bool valid_ordinal = false;
    bool ordinal_walk_exhausted = false;
    uint ordinal = bound_arg_ordinal(node, args_node, valid_ordinal, ordinal_walk_exhausted);
    if (ordinal_walk_exhausted)
    {
        publish_status(owner, PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION);
        return;
    }

    if (!valid_ordinal)
        return;

    if (node_kind[node] != PROD_BOUND_TYPE_IDENT)
    {
        publish_status(owner, PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE);
        return;
    }

    publish_arg_node(owner, ordinal, node);

    if (bound_ident_has_arg_list(node))
        publish_status(owner, PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE);
}
