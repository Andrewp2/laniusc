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
import hir_records;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPredicateFacts> compact_hir_predicate_facts;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;

RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;
RWStructuredBuffer<uint> predicate_trait_impl_trait_type_node;

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
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint parent_node(uint node)
{
    return valid_node(node) ? compact_hir_core[node].parent : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = compact_hir_links[node].first_child;
    return valid_node(child) && parent_node(child) == node && child > node
        ? child
        : INVALID;
}

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = compact_hir_links[node].next_sibling;
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
    uint kind = compact_hir_predicate_facts[node].production;
    return kind == PROD_BOUND_TYPE_ARGS_SOME ||
           kind == PROD_BOUND_TYPE_ARGS_AFTER_COMMA_MORE;
}

bool bound_expr_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = compact_hir_predicate_facts[node].production;
    return kind == PROD_BOUND_TYPE_IDENT || kind == PROD_BOUND_TYPE_REF;
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

uint direct_bound_arg_count(uint owner)
{
    if (!bound_expr_node(owner))
        return 0u;
    uint count = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    HirRange range = compact_type_arg_ranges[owner];
    return range.start <= count && range.count <= count - range.start ? range.count : 0u;
}

uint direct_bound_arg_node(uint owner, uint ordinal)
{
    uint count = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    HirRange range = compact_type_arg_ranges[owner];
    if (ordinal >= range.count || range.start > count || range.count > count - range.start)
        return INVALID;
    uint row = range.start + ordinal;
    return compact_type_args[row].value;
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

    uint owner = node;
    uint arg_count = direct_bound_arg_count(owner);
    predicate_bound_arg_count[owner] = arg_count;
    for (uint ordinal = 0u; ordinal < min(arg_count, 3u); ordinal += 1u)
    {
        uint arg_node = direct_bound_arg_node(owner, ordinal);
        if (!valid_node(arg_node))
        {
            publish_status(owner, PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION);
            continue;
        }
        publish_arg_node(owner, ordinal, arg_node);
    }
    if (arg_count > 2u)
        publish_status(owner, PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH);

    uint owner_parent = parent_node(node);
    if (compact_hir_predicate_facts[node].production == PROD_TYPE_IDENT &&
        valid_node(owner_parent) &&
        compact_hir_predicate_facts[owner_parent].production == PROD_IMPL_TRAIT)
        atomic_u32_min(predicate_trait_impl_trait_type_node, owner_parent, node);
}
