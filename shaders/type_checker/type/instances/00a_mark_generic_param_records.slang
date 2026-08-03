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
import generated_parse_production_ids;
import fixed.compact_method;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;

RWStructuredBuffer<uint> generic_decl_owner_by_node_a;
RWStructuredBuffer<uint> predicate_bound_list_by_node_a;
RWStructuredBuffer<uint> generic_decl_parent_jump_a;
RWStructuredBuffer<uint> type_decl_hir_node_by_token;

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
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
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

bool impl_node_kind(uint kind)
{
    return kind == PROD_IMPL_INHERENT || kind == PROD_IMPL_TRAIT;
}

bool generic_decl_item_production(uint prod)
{
    return prod == PROD_FN || prod == PROD_EXTERN_FN ||
           prod == PROD_STRUCT || prod == PROD_ENUM ||
           prod == PROD_TYPE_ALIAS || prod == PROD_TRAIT;
}

uint compact_method_signature_flags_for_raw_decl(uint node)
{
    if (!valid_node(node))
        return 0u;
    uint dense = raw_to_compact_hir[node];
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (dense >= hir_count)
        return 0u;
    uint method_count = min(compact_method_count[0u], gParams.n_hir_nodes);
    uint row = compact_method_row_for_hir(
        compact_method_cores, method_count, dense);
    return row < method_count ? compact_method_signatures[row].metadata >> 16u : 0u;
}

bool generic_decl_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint prod = node_kind[node];
    if (prod == PROD_TRAIT_METHOD || prod == PROD_TRAIT_METHOD_PUB || prod == PROD_IMPL_FN)
        return (compact_method_signature_flags_for_raw_decl(node) &
                METHOD_SIGNATURE_HAS_GENERICS) != 0u;
    return generic_decl_item_production(prod) ||
           prod == PROD_IMPL_INHERENT ||
           prod == PROD_IMPL_TRAIT;
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
        node_kind[node] == PROD_TYPE_PARAM_BOUND_LIST ? node : INVALID;
    generic_decl_parent_jump_a[node] = valid_node(parent[node]) ? parent[node] : INVALID;

    uint compact_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint dense = node < gParams.n_hir_nodes ? raw_to_compact_hir[node] : INVALID;
    // The dispatch domain is the raw parser tree. A dense HIR row can be
    // mapped from several raw rows, and some semantic rows have no winning
    // raw owner after canonicalization. The first compact rows therefore also
    // visit the dense domain directly so every declaration anchor is covered.
    if (dense >= compact_count && node < compact_count)
        dense = node;
    if (dense < compact_count)
    {
        HirPayload payload = compact_hir_payload[dense];
        uint name_token = payload.b;
        if (generic_decl_item_kind(payload.a) && valid_token(name_token))
            type_decl_hir_node_by_token[name_token] = dense;
    }
}
