// HIR-derived generic parameter use slots.
//
// This pass runs after declaration generic parameter records are complete. It
// only searches declarations with a nonzero generic parameter count, so ordinary
// non-generic functions avoid declaration-subtree scans.

import generated_parse_production_ids;
import tree_walk;

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
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_len_token;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_decl_generic_param_count_by_node;
StructuredBuffer<uint> type_decl_const_param_count_by_node;

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

static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint MAX_GENERIC_PARAM_SEARCH = 64u;

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

public struct GenericParamUseWalkGraph : ITreeWalkGraph
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

public struct GenericParamUseOwnerPredicate : ITreeWalkPredicate
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
        GenericParamUseWalkGraph,
        GenericParamUseOwnerPredicate>(
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

bool decl_has_generic_params(uint decl_node)
{
    uint child = valid_node(decl_node) ? first_child[decl_node] : INVALID;
    return valid_node(child) && node_kind[child] == PROD_ENUM_TYPE_PARAMS_SOME;
}

uint generic_param_slot_for_name(uint decl_node, uint name_token, uint max_slots)
{
    if (!valid_node(decl_node) || !valid_token(name_token) || max_slots == 0u)
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint slot = 0u;
    uint end = min(subtree_end[decl_node], active_hir_node_count());
    [loop]
    for (uint node = decl_node + 1u; node < end && slot < max_slots; node += 1u)
    {
        if (!generic_param_node(node) || generic_decl_ancestor(node) != decl_node)
            continue;

        uint param_token = hir_token_pos[node];
        if (valid_token(param_token) && name_id_by_token[param_token] == name_id)
            return slot;
        slot += 1u;
    }
    return INVALID;
}

uint const_param_slot_for_name(uint decl_node, uint name_token, uint max_slots)
{
    if (!valid_node(decl_node) || !valid_token(name_token) || max_slots == 0u)
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint slot = 0u;
    uint end = min(subtree_end[decl_node], active_hir_node_count());
    [loop]
    for (uint node = decl_node + 1u; node < end && slot < max_slots; node += 1u)
    {
        if (!const_param_node(node) || generic_decl_ancestor(node) != decl_node)
            continue;

        uint param_token = const_param_name_token(node);
        if (valid_token(param_token) && name_id_by_token[param_token] == name_id)
            return slot;
        slot += 1u;
    }
    return INVALID;
}

void publish_const_len_use_slot(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_TYPE ||
        hir_type_form[node] != HIR_TYPE_FORM_ARRAY)
        return;

    uint token = hir_type_len_token[node];
    if (!valid_token(token))
        return;

    uint decl_node = generic_decl_ancestor(node);
    if (!valid_node(decl_node) || !decl_has_generic_params(decl_node))
        return;

    uint count = type_decl_const_param_count_by_node[decl_node];
    uint max_slots = count == 0u ? MAX_GENERIC_PARAM_SEARCH : count;
    uint slot = const_param_slot_for_name(decl_node, token, max_slots);
    if (slot != INVALID)
        type_const_param_slot_by_token[token] = slot;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    publish_const_len_use_slot(node);

    if (!valid_node(node) || hir_kind[node] != HIR_TYPE ||
        hir_type_form[node] != HIR_TYPE_FORM_PATH)
        return;

    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return;

    uint decl_node = generic_decl_ancestor(node);
    if (!valid_node(decl_node) || !decl_has_generic_params(decl_node))
        return;

    uint count = type_decl_generic_param_count_by_node[decl_node];
    uint max_slots = count == 0u ? MAX_GENERIC_PARAM_SEARCH : count;
    uint slot = generic_param_slot_for_name(decl_node, token, max_slots);
    if (slot != INVALID)
        type_generic_param_slot_by_token[token] = slot;
}
