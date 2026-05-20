// GPU method declaration collection from parser/HIR tree records.
//
// Scheduling contract:
// - Dispatch after parser HIR nodes and tree parent links are available.
// - This pass records fn_item nodes whose parent production is impl_method.
// - Later passes attach module ids, interned method name ids, and receiver
//   type refs from GPU module/name/type tables.
// - It does not inspect source bytes, hash token text, scan impl token bodies,
//   build a direct lookup table, or decide whether a call resolves.

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
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> method_decl_impl_node;
RWStructuredBuffer<uint> method_decl_name_token;
RWStructuredBuffer<uint> method_decl_param_offset;
RWStructuredBuffer<uint> method_decl_receiver_mode;
RWStructuredBuffer<uint> method_decl_visibility;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;

static const uint METHOD_RECEIVER_NONE = 0u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint METHOD_RECEIVER_EXPLICIT = 3u;

static const uint METHOD_VIS_PRIVATE = 0u;
static const uint METHOD_VIS_PUBLIC = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

uint node_production(uint i)
{
    return valid_node(i) ? node_kind[i] : INVALID;
}

uint method_collect_parent_record(uint i)
{
    return parent[i];
}

uint method_collect_first_child_record(uint i)
{
    return first_child[i];
}

uint method_collect_next_sibling_record(uint i)
{
    return next_sibling[i];
}

public struct MethodCollectWalkGraph : ITreeWalkGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint parent(uint node)
    {
        return method_collect_parent_record(node);
    }
}

public struct MethodCollectChildGraph : ITreeChildGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint first_child(uint node)
    {
        return method_collect_first_child_record(node);
    }

    public static uint next_sibling(uint node)
    {
        return method_collect_next_sibling_record(node);
    }
}

public struct MethodCollectProductionPredicate : ITreeWalkKeyPredicate
{
    public static bool matches(uint node, uint key)
    {
        return node_kind[node] == key;
    }
}

uint first_child_node(uint i)
{
    uint child;
    return tree_child_first<MethodCollectChildGraph>(i, child) ? child : INVALID;
}

uint parent_node(uint i)
{
    uint p = valid_node(i) ? method_collect_parent_record(i) : INVALID;
    return valid_node(p) ? p : INVALID;
}

bool is_impl_method_production(uint prod)
{
    return prod == PROD_IMPL_METHOD || prod == PROD_IMPL_METHOD_PUB;
}

bool is_param_production(uint prod)
{
    return prod == PROD_PARAM_NAMED || prod == PROD_PARAM_SELF || prod == PROD_PARAM_SELF_REF;
}

uint ancestor_impl_node(uint i)
{
    uint ancestor;
    if (find_ancestor_matching_key<
        MethodCollectWalkGraph,
        MethodCollectProductionPredicate>(
        i,
        PROD_IMPL_INHERENT,
        32u,
        ancestor))
        return ancestor;

    return find_ancestor_matching_key<
        MethodCollectWalkGraph,
        MethodCollectProductionPredicate>(
        i,
        PROD_IMPL_TRAIT,
        32u,
        ancestor) ? ancestor : INVALID;
}

uint direct_child_with_production(uint i, uint prod)
{
    uint child;
    return tree_child_first_matching_key<
        MethodCollectChildGraph,
        MethodCollectProductionPredicate>(
        i,
        prod,
        16u,
        child) ? child : INVALID;
}

uint first_method_param_token(uint fn_node)
{
    uint child = direct_child_with_production(fn_node, PROD_PARAMS_SOME);
    if (child != INVALID)
    {
        uint param = first_child_node(child);
        if (param != INVALID && hir_kind[param] == HIR_PARAM &&
            is_param_production(node_kind[param]))
            return hir_token_pos[param];
    }
    return INVALID;
}

uint method_receiver_mode(uint fn_node)
{
    uint child = direct_child_with_production(fn_node, PROD_PARAMS_SOME);
    if (child != INVALID)
    {
        uint param = first_child_node(child);
        if (param == INVALID || hir_kind[param] != HIR_PARAM)
            return METHOD_RECEIVER_NONE;
        uint prod = node_kind[param];
        if (prod == PROD_PARAM_SELF)
            return METHOD_RECEIVER_SELF;
        if (prod == PROD_PARAM_SELF_REF)
            return METHOD_RECEIVER_REF_SELF;
        if (prod == PROD_PARAM_NAMED)
            return METHOD_RECEIVER_EXPLICIT;
    }
    return METHOD_RECEIVER_NONE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count())
        return;

    if (node_kind[i] != PROD_IMPL_FN || hir_kind[i] != HIR_FN)
        return;

    uint method_parent = parent_node(i);
    if (method_parent == INVALID || !is_impl_method_production(node_kind[method_parent]))
        return;

    uint impl_node = ancestor_impl_node(i);
    uint fn_token = hir_token_pos[i];
    if (fn_token == INVALID || impl_node == INVALID || fn_token >= gParams.n_tokens)
        return;

    method_decl_impl_node[fn_token] = impl_node;
    method_decl_name_token[fn_token] = fn_token + 1u;
    method_decl_param_offset[fn_token] = first_method_param_token(i);
    method_decl_receiver_mode[fn_token] = method_receiver_mode(i);
    method_decl_visibility[fn_token] =
        node_kind[method_parent] == PROD_IMPL_METHOD_PUB ? METHOD_VIS_PUBLIC : METHOD_VIS_PRIVATE;
}
