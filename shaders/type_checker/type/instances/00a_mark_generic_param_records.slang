// Initialize raw-tree owner propagation needed by predicate and alias consumers.
//
// Scheduling contract:
// - Dispatch after HIR item records and interned token names are available.
// - This initializes generic-declaration and predicate-list owner propagation. Follow with
//   type_check_type_instances_00a1_propagate_generic_decl_owner until the
//   parent jump table reaches the root.
// - Generic parameter rows themselves come from the compact HIR side table.
// - This pass also publishes declaration-token to HIR-node facts for later
//   consumers; it does not scan declaration subtrees.

import hir_records;
import fixed.compact_method;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;

RWStructuredBuffer<uint> generic_decl_owner_by_node_a;
RWStructuredBuffer<uint> predicate_bound_list_by_node_a;
RWStructuredBuffer<uint> generic_decl_parent_jump_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;

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

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool generic_decl_item_kind(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_FN ||
           item_kind == HIR_ITEM_KIND_EXTERN_FN ||
           item_kind == HIR_ITEM_KIND_STRUCT ||
           item_kind == HIR_ITEM_KIND_ENUM ||
           item_kind == HIR_ITEM_KIND_TYPE_ALIAS ||
           item_kind == HIR_ITEM_KIND_TRAIT;
}

uint compact_method_signature_flags(uint node)
{
    if (!valid_node(node))
        return 0u;
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint method_count = min(compact_method_count[0u], gParams.n_hir_nodes);
    for (uint row = 0u; row < method_count; row += 1u)
    {
        uint dense = compact_method_cores[row].node;
        if (dense < hir_count && dense == node)
            return compact_method_signatures[row].metadata >> 16u;
    }
    return 0u;
}

bool generic_decl_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint prod = compact_hir_semantic_facts[node].semantic_kind;
    if (prod == HIR_SEMANTIC_TRAIT_METHOD || prod == HIR_SEMANTIC_PUBLIC_TRAIT_METHOD || prod == HIR_SEMANTIC_IMPL_FUNCTION)
        return (compact_method_signature_flags(node) &
                METHOD_SIGNATURE_HAS_GENERICS) != 0u;
    return generic_decl_item_kind(compact_hir_payload[node].a) ||
           prod == HIR_SEMANTIC_IMPL_INHERENT ||
           prod == HIR_SEMANTIC_IMPL_TRAIT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    generic_decl_owner_by_node_a[node] =
        generic_decl_node(node) ? node : INVALID;
    predicate_bound_list_by_node_a[node] =
        compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_TYPE_PARAM_BOUND_LIST
            ? node
            : INVALID;
    generic_decl_parent_jump_a[node] = valid_node(compact_hir_core[node].parent)
        ? compact_hir_core[node].parent
        : INVALID;

}
