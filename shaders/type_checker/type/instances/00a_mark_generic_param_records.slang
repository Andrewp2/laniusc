// Mark HIR generic-parameter declaration records.
//
// Scheduling contract:
// - Dispatch after HIR item records and interned token names are available.
// - This initializes generic-declaration owner propagation. Follow with
//   type_check_type_instances_00a1_propagate_generic_decl_owner until the
//   parent jump table reaches the root.
// - A counted prefix scan over generic_param_flag compacts the marked rows.
// - This pass also publishes declaration-token to HIR-node facts for later
//   consumers; it does not scan declaration subtrees.

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
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;

RWStructuredBuffer<uint> generic_param_flag;
RWStructuredBuffer<uint> generic_decl_owner_by_node_a;
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

bool generic_param_record_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_ENUM_TYPE_PARAM || kind == PROD_ENUM_CONST_PARAM;
}

bool generic_decl_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint prod = node_kind[node];
    return generic_decl_item_kind(hir_item_kind[node]) ||
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

    generic_param_flag[node] = generic_param_record_node(node) ? 1u : 0u;
    generic_decl_owner_by_node_a[node] = generic_decl_node(node) ? node : INVALID;
    generic_decl_parent_jump_a[node] = valid_node(parent[node]) ? parent[node] : INVALID;

    if (generic_decl_item_kind(hir_item_kind[node]))
    {
        uint name_token = hir_item_name_token[node];
        if (valid_token(name_token))
            type_decl_hir_node_by_token[name_token] = node;
    }
}
