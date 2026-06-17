// Scatter structural predicate-bound argument facts.
//
// Bound predicates use a distinct parse grammar from ordinary HIR type
// expressions, so parser `hir_type_arg_*` records do not describe these rows.
// This pass publishes the nearest bound-argument list owner, supported ordinals,
// and fail-closed structural statuses so predicate semantic collection can avoid
// walking each predicate subtree.
//
// This is still a bounded bridge: owner and ordinal extraction below accepts
// only direct bound-argument grammar shapes it can prove without walking a path
// spine. If those local relations cannot prove the bound-argument
// owner/ordinal, the pass leaves the predicate for the collector to fail closed.
// Do not widen this bridge; replace it with parser-owned bound-argument rows
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
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_bound_path_owner_by_leaf;

RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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
    return valid_node(child) && parent_node(child) == node && child > node
        ? child
        : INVALID;
}

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    uint owner = parent_node(node);
    return valid_node(owner) &&
           valid_node(sibling) &&
           parent_node(sibling) == owner &&
           sibling > node
        ? sibling
        : INVALID;
}

bool bound_args_container(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_BOUND_TYPE_ARGS_SOME ||
           kind == PROD_BOUND_TYPE_ARGS_AFTER_COMMA_MORE;
}

bool bound_expr_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_BOUND_TYPE_IDENT || kind == PROD_BOUND_TYPE_REF;
}

bool bound_path_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_BOUND_TYPE_PATH;
}

bool bound_path_tail_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_BOUND_TYPE_PATH_MORE || kind == PROD_PATH_MORE;
}

bool bound_path_segment_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_BOUND_TYPE_PATH_IDENT ||
           kind == PROD_PATH_IDENT ||
           kind == PROD_PATH_IDENT_ARGS;
}

void publish_status(uint owner, uint status)
{
    if (valid_node(owner))
        atomic_u32_min(predicate_status, owner, status);
}

uint arg_from_container(uint container)
{
    if (!bound_args_container(container))
        return INVALID;

    uint arg = first_child_node(container);
    return bound_expr_node(arg) ? arg : INVALID;
}

uint qualified_path_first_arg_node(uint owner)
{
    if (!valid_node(owner) || node_kind[owner] != PROD_BOUND_TYPE_IDENT)
        return INVALID;

    uint path = first_child_node(owner);
    if (!bound_path_node(path))
        return INVALID;

    uint leaf = hir_type_path_leaf_node[owner];
    if (!bound_path_segment_node(leaf))
        return INVALID;

    uint arg = next_sibling_node(leaf);
    return bound_expr_node(arg) ? arg : INVALID;
}

uint qualified_path_owner_for_leaf_container(uint container)
{
    if (!bound_path_tail_node(container))
        return INVALID;

    uint segment = first_child_node(container);
    if (!bound_path_segment_node(segment))
        return INVALID;

    uint owner = hir_bound_path_owner_by_leaf[segment];
    return bound_expr_node(owner) ? owner : INVALID;
}

bool bound_ident_has_arg_list(uint node)
{
    if (!valid_node(node) || node_kind[node] != PROD_BOUND_TYPE_IDENT)
        return false;

    uint child = first_child_node(node);
    [loop]
    while (valid_node(child))
    {
        uint kind = node_kind[child];
        if (kind == PROD_BOUND_TYPE_ARGS_SOME)
            return true;
        if (kind == PROD_BOUND_TYPE_ARGS_NONE)
            return false;
        child = next_sibling_node(child);
    }
    if (qualified_path_first_arg_node(node) != INVALID)
        return true;
    return false;
}

uint owner_for_first_arg_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_BOUND_TYPE_ARGS_SOME)
        return INVALID;

    uint owner = parent_node(container);
    return bound_expr_node(owner) ? owner : INVALID;
}

uint previous_arg_context(uint after_comma_container)
{
    if (!valid_node(after_comma_container) ||
        node_kind[after_comma_container] != PROD_BOUND_TYPE_ARGS_AFTER_COMMA_MORE)
        return INVALID;

    uint more = parent_node(after_comma_container);
    uint previous = parent_node(more);
    return bound_args_container(previous) || bound_expr_node(previous)
        ? previous
        : INVALID;
}

bool direct_bound_arg_relation(uint arg_node, out uint owner, out uint ordinal)
{
    owner = INVALID;
    ordinal = INVALID;
    if (!bound_expr_node(arg_node))
        return false;

    uint container = parent_node(arg_node);

    if (bound_path_tail_node(container))
    {
        uint segment = first_child_node(container);
        if (bound_path_segment_node(segment) && next_sibling_node(segment) == arg_node)
        {
            owner = qualified_path_owner_for_leaf_container(container);
            ordinal = 0u;
            return valid_node(owner);
        }
    }

    if (!bound_args_container(container) || arg_from_container(container) != arg_node)
        return false;

    if (node_kind[container] == PROD_BOUND_TYPE_ARGS_SOME)
    {
        owner = owner_for_first_arg_container(container);
        ordinal = 0u;
        return valid_node(owner);
    }

    uint previous = previous_arg_context(container);
    if (!valid_node(previous))
        return false;

    if (bound_expr_node(previous) && qualified_path_first_arg_node(previous) != INVALID)
    {
        owner = previous;
        ordinal = 1u;
        return true;
    }

    if (node_kind[previous] == PROD_BOUND_TYPE_ARGS_SOME)
    {
        owner = owner_for_first_arg_container(previous);
        ordinal = 1u;
        return valid_node(owner);
    }

    uint first = previous_arg_context(previous);
    if (bound_expr_node(first) && qualified_path_first_arg_node(first) != INVALID)
    {
        owner = first;
        ordinal = 2u;
        return true;
    }

    if (valid_node(first) && node_kind[first] == PROD_BOUND_TYPE_ARGS_SOME)
    {
        owner = owner_for_first_arg_container(first);
        ordinal = 2u;
        return valid_node(owner);
    }

    return false;
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

    uint owner = INVALID;
    uint ordinal = INVALID;
    if (!direct_bound_arg_relation(node, owner, ordinal))
        return;

    publish_arg_node(owner, ordinal, node);

    if (node_kind[node] != PROD_BOUND_TYPE_IDENT)
    {
        publish_status(owner, PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE);
        return;
    }

    if (bound_ident_has_arg_list(node))
        publish_status(owner, PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE);
}
