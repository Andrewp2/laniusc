// Initialize compact-HIR owner propagation needed by generic and predicate consumers.
//
// Scheduling contract:
// - Dispatch after compact generic-parameter ranges are available.
// - This initializes generic-declaration and predicate-list owner propagation. Follow with
//   type_check_type_instances_00a1_propagate_generic_decl_owner until the
//   parent jump table reaches the root.
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
RWStructuredBuffer<uint> generic_decl_parent_jump_a;

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

    generic_decl_owner_by_node_a[node] =
        compact_generic_param_ranges[node].count != 0u ? node : INVALID;
    predicate_bound_list_by_node_a[node] =
        compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_TYPE_PARAM_BOUND_LIST
            ? node
            : INVALID;
    generic_decl_parent_jump_a[node] = valid_node(compact_hir_core[node].parent)
        ? compact_hir_core[node].parent
        : INVALID;

}
