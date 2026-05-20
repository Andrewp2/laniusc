// HIR-derived declaration generic parameter records.
//
// This pass records the expected type-argument arity for generic declarations
// using parser-owned HIR item records and parse-tree ancestry. It is deliberately
// fact-shaped: declaration nodes publish their token-to-HIR record and generic
// parameter nodes publish declaration slots plus owner declaration counts.
// Generic parameter use sites are resolved in a later pass after these counts
// are complete.

import generated_parse_production_ids;
import tree_walk;
import atomics;

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
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;

RWStructuredBuffer<uint> type_decl_generic_param_count;
RWStructuredBuffer<uint> type_decl_generic_param_count_by_node;
RWStructuredBuffer<uint> type_decl_const_param_count_by_node;
RWStructuredBuffer<uint> type_decl_hir_node_by_token;
RWStructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> type_const_param_slot_by_token;

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

uint parent_node(uint node)
{
    return parent[node];
}

public struct DeclGenericParamWalkGraph : ITreeWalkGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint parent(uint node)
    {
        return parent_node(node);
    }
}

bool generic_decl_item_kind(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_FN ||
           item_kind == HIR_ITEM_KIND_EXTERN_FN ||
           item_kind == HIR_ITEM_KIND_STRUCT ||
           item_kind == HIR_ITEM_KIND_ENUM ||
           item_kind == HIR_ITEM_KIND_TYPE_ALIAS;
}

public struct DeclGenericParamOwnerPredicate : ITreeWalkPredicate
{
    public static bool matches(uint node)
    {
        return generic_decl_item_kind(hir_item_kind[node]);
    }
}

uint generic_decl_ancestor(uint node)
{
    uint ancestor;
    return find_self_or_ancestor<
        DeclGenericParamWalkGraph,
        DeclGenericParamOwnerPredicate>(
        node,
        MAX_PARENT_WALK,
        ancestor) ? ancestor : INVALID;
}

bool generic_param_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_ENUM_TYPE_PARAM;
}

bool const_param_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_ENUM_CONST_PARAM;
}

uint const_param_name_token(uint node)
{
    uint token = valid_node(node) ? hir_token_pos[node] : INVALID;
    if (token == INVALID)
        return INVALID;
    return valid_token(token + 1u) ? token + 1u : INVALID;
}

uint generic_param_slot_for_node(uint decl_node, uint param_node)
{
    if (!valid_node(decl_node) || !valid_node(param_node))
        return INVALID;

    uint slot = 0u;
    uint end = min(subtree_end[decl_node], active_hir_node_count());
    [loop]
    for (uint node = decl_node + 1u; node < end; node += 1u)
    {
        if (!generic_param_node(node) || generic_decl_ancestor(node) != decl_node)
            continue;
        if (node == param_node)
            return slot;
        slot += 1u;
    }
    return INVALID;
}

uint const_param_slot_for_node(uint decl_node, uint param_node)
{
    if (!valid_node(decl_node) || !valid_node(param_node))
        return INVALID;

    uint slot = 0u;
    uint end = min(subtree_end[decl_node], active_hir_node_count());
    [loop]
    for (uint node = decl_node + 1u; node < end; node += 1u)
    {
        if (!const_param_node(node) || generic_decl_ancestor(node) != decl_node)
            continue;
        if (node == param_node)
            return slot;
        slot += 1u;
    }
    return INVALID;
}

void publish_generic_param_decl_slot(uint node)
{
    if (!generic_param_node(node))
        return;

    uint decl_node = generic_decl_ancestor(node);
    uint token = hir_token_pos[node];
    uint slot = generic_param_slot_for_node(decl_node, node);
    if (valid_token(token) && slot != INVALID)
        type_generic_param_slot_by_token[token] = slot;
}

void publish_const_param_decl_slot(uint node)
{
    if (!const_param_node(node))
        return;

    uint decl_node = generic_decl_ancestor(node);
    uint token = const_param_name_token(node);
    uint slot = const_param_slot_for_node(decl_node, node);
    if (valid_token(token) && slot != INVALID)
        type_const_param_slot_by_token[token] = slot;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    if (generic_decl_item_kind(hir_item_kind[node]))
    {
        uint name_token = hir_item_name_token[node];
        if (valid_token(name_token))
            type_decl_hir_node_by_token[name_token] = node;
    }

    publish_generic_param_decl_slot(node);
    publish_const_param_decl_slot(node);

    if (node_kind[node] == PROD_ENUM_CONST_PARAM)
    {
        uint const_decl_node = generic_decl_ancestor(node);
        if (valid_node(const_decl_node))
            atomic_u32_add(type_decl_const_param_count_by_node, const_decl_node, 1u);
        return;
    }

    if (node_kind[node] != PROD_ENUM_TYPE_PARAM || !valid_token(hir_token_pos[node]))
        return;

    uint decl_node = generic_decl_ancestor(node);
    if (!valid_node(decl_node))
        return;

    uint decl_name_token = hir_item_name_token[decl_node];
    uint decl_head_token = hir_token_pos[decl_node];
    atomic_u32_add(type_decl_generic_param_count_by_node, decl_node, 1u);
    if (valid_token(decl_name_token))
        atomic_u32_add(type_decl_generic_param_count, decl_name_token, 1u);
    if (valid_token(decl_head_token))
        atomic_u32_add(type_decl_generic_param_count, decl_head_token, 1u);
}
