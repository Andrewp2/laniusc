// HIR-derived declaration generic parameter counts.
//
// This pass records the expected type-argument arity for generic declarations
// using parser-owned HIR item records and parse-tree ancestry. Consumers use the
// token-indexed declaration-name record instead of scanning token neighborhoods.

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
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;

RWStructuredBuffer<uint> type_decl_generic_param_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PARENT_WALK = 128u;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;

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
           item_kind == HIR_ITEM_KIND_TYPE_ALIAS;
}

uint generic_decl_ancestor(uint node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < MAX_PARENT_WALK; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        if (generic_decl_item_kind(hir_item_kind[cur]))
            return cur;
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        cur = p;
    }
    return INVALID;
}

uint generic_type_param_count_for_decl(uint decl_node)
{
    uint count = 0u;
    uint active = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < active; node += 1u)
    {
        if (node_kind[node] == PROD_ENUM_TYPE_PARAM &&
            generic_decl_ancestor(node) == decl_node &&
            valid_token(hir_token_pos[node]))
        {
            count += 1u;
        }
    }
    return count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || !generic_decl_item_kind(hir_item_kind[node]))
        return;

    uint name_token = hir_item_name_token[node];
    if (!valid_token(name_token))
        return;

    type_decl_generic_param_count[name_token] = generic_type_param_count_for_decl(node);
}
