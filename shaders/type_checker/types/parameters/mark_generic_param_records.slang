// Resolve compact-HIR owners needed by generic and predicate consumers.
//
// Scheduling contract:
// - Dispatch after compact generic-parameter ranges are available.
// - Only nodes with actual compact generic-parameter rows seed the ownership
//   relation; syntactically eligible wrappers are not declaration owners.

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
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<HirRange> compact_generic_param_ranges;

RWStructuredBuffer<uint> generic_decl_owner_by_node_a;
RWStructuredBuffer<uint> predicate_bound_list_by_node_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    uint owner = INVALID;
    uint bound_list = INVALID;
    uint current = node;
    uint visited = 0u;
    while (valid_node(current) && visited < active_hir_node_count())
    {
        if (owner == INVALID && compact_generic_param_ranges[current].count != 0u)
            owner = current;
        if (bound_list == INVALID &&
            compact_hir_semantic_facts[current].semantic_kind ==
                HIR_SEMANTIC_TYPE_PARAM_BOUND_LIST)
            bound_list = current;
        if (owner != INVALID && bound_list != INVALID)
            break;
        current = compact_hir_core[current].parent;
        visited += 1u;
    }
    generic_decl_owner_by_node_a[node] = owner;
    predicate_bound_list_by_node_a[node] = bound_list;

}
