// Record struct-literal field expectations from parser-owned HIR metadata.
//
// This pass does not substitute generic arguments itself. It publishes the
// declaration-side field ref plus the contextual type-instance token; the next
// pass substitutes generic slots using the type-instance argument table.

import generated_parse_production_ids;
import tree_walk;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_type_node;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_decl_hir_node_by_token;

RWStructuredBuffer<uint> struct_init_field_context_instance;
RWStructuredBuffer<uint> struct_init_field_expected_ref_tag;
RWStructuredBuffer<uint> struct_init_field_expected_ref_payload;
RWStructuredBuffer<uint> struct_init_field_ordinal;
RWStructuredBuffer<uint> struct_init_field_ordinal_by_node;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_token(uint i)
{
    return i != INVALID && i < active_token_count();
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint node_subtree_end(uint node_i)
{
    if (!valid_node(node_i))
        return INVALID;
    uint end = subtree_end[node_i];
    return end == INVALID ? active_node_count() : min(end, active_node_count());
}

uint struct_init_parent_node(uint node_i)
{
    return parent[node_i];
}

public struct StructInitGraph : ITreeWalkGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint parent(uint node)
    {
        return struct_init_parent_node(node);
    }
}

public struct StructInitProductionPredicate : ITreeWalkKeyPredicate
{
    public static bool matches(uint node, uint prod)
    {
        return node_kind[node] == prod;
    }
}

bool is_item_decl_production(uint prod)
{
    return prod == PROD_FN || prod == PROD_EXTERN_FN || prod == PROD_TYPE_ALIAS ||
           prod == PROD_IMPL_INHERENT || prod == PROD_IMPL_TRAIT || prod == PROD_TRAIT ||
           prod == PROD_ENUM || prod == PROD_STRUCT;
}

bool is_function_like_production(uint prod)
{
    return prod == PROD_FN || prod == PROD_IMPL_METHOD || prod == PROD_IMPL_METHOD_PUB ||
           prod == PROD_TRAIT_METHOD || prod == PROD_TRAIT_METHOD_PUB;
}

bool is_type_expr_production(uint prod)
{
    return prod == PROD_TYPE_IDENT || prod == PROD_TYPE_ARRAY || prod == PROD_TYPE_REF;
}

bool is_type_path_ident_production(uint prod)
{
    return prod == PROD_TYPE_PATH_IDENT || prod == PROD_PATH_IDENT;
}

public struct StructInitItemDeclPredicate : ITreeWalkPredicate
{
    public static bool matches(uint node)
    {
        return is_item_decl_production(node_kind[node]);
    }
}

public struct StructInitFunctionLikePredicate : ITreeWalkPredicate
{
    public static bool matches(uint node)
    {
        return is_function_like_production(node_kind[node]);
    }
}

bool has_ancestor_node(uint node_i, uint ancestor_i)
{
    return has_self_or_ancestor_node<StructInitGraph>(node_i, ancestor_i, 96u);
}

uint ancestor_with_production(uint node_i, uint prod)
{
    uint ancestor;
    return find_ancestor_matching_key<
        StructInitGraph,
        StructInitProductionPredicate>(
        node_i,
        prod,
        96u,
        ancestor) ? ancestor : INVALID;
}

uint item_decl_ancestor(uint node_i)
{
    uint ancestor;
    return find_self_or_ancestor<StructInitGraph, StructInitItemDeclPredicate>(
        node_i,
        96u,
        ancestor) ? ancestor : INVALID;
}

uint function_like_ancestor(uint node_i)
{
    uint ancestor;
    return find_self_or_ancestor<StructInitGraph, StructInitFunctionLikePredicate>(
        node_i,
        96u,
        ancestor) ? ancestor : INVALID;
}

uint first_type_expr_descendant(uint root_i)
{
    if (!valid_node(root_i))
        return INVALID;

    uint n = node_subtree_end(root_i);
    [loop]
    for (uint j = root_i + 1u; j < n; j += 1u)
    {
        if (is_type_expr_production(node_kind[j]) && has_ancestor_node(j, root_i))
            return j;
    }
    return INVALID;
}

uint return_type_node(uint fn_node)
{
    if (!valid_node(fn_node))
        return INVALID;

    uint n = node_subtree_end(fn_node);
    [loop]
    for (uint j = fn_node + 1u; j < n; j += 1u)
    {
        if (node_kind[j] == PROD_RET_TYPE && has_ancestor_node(j, fn_node))
            return first_type_expr_descendant(j);
    }
    return INVALID;
}

uint type_head_token_for_node(uint type_node)
{
    if (!valid_node(type_node))
        return INVALID;

    uint value_node = hir_type_value_node[type_node];
    uint search_root = valid_node(value_node) ? value_node : type_node;
    uint leaf = INVALID;
    uint n = node_subtree_end(search_root);
    [loop]
    for (uint j = search_root + 1u; j < n; j += 1u)
    {
        if (!is_type_path_ident_production(node_kind[j]) || !has_ancestor_node(j, search_root))
            continue;
        uint token = hir_token_pos[j];
        if (valid_token(token))
            leaf = token;
    }
    if (valid_token(leaf))
        return leaf;

    if (valid_node(value_node))
    {
        uint value_head = hir_token_pos[value_node];
        if (valid_token(value_head))
            return value_head;
    }
    uint type_head = hir_token_pos[type_node];
    return valid_token(type_head) ? type_head : INVALID;
}

bool context_for_type_node(uint type_node, out uint decl_token, out uint instance_i)
{
    decl_token = INVALID;
    instance_i = INVALID;
    uint type_head = type_head_token_for_node(type_node);
    if (!valid_token(type_head))
        return false;

    uint tag = type_expr_ref_tag[type_head];
    uint payload = type_expr_ref_payload[type_head];
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
    {
        uint instance_decl = type_instance_decl_token[payload];
        if (!valid_token(instance_decl))
            return false;
        decl_token = instance_decl;
        instance_i = payload;
        return true;
    }
    if (tag == TYPE_REF_SCALAR && payload >= TY_STRUCT_BASE && payload < TY_ENUM_BASE)
    {
        decl_token = payload - TY_STRUCT_BASE;
        return valid_token(decl_token);
    }
    return false;
}

uint let_annotation_type_node(uint let_node)
{
    if (!valid_node(let_node))
        return INVALID;

    uint n = node_subtree_end(let_node);
    [loop]
    for (uint j = let_node + 1u; j < n; j += 1u)
    {
        if (node_kind[j] == PROD_LET_TYPE && has_ancestor_node(j, let_node))
            return first_type_expr_descendant(j);
    }
    return INVALID;
}

bool context_for_struct_literal_node(uint literal_node, out uint decl_token, out uint instance_i)
{
    decl_token = INVALID;
    instance_i = INVALID;
    uint let_node = ancestor_with_production(literal_node, PROD_LET_STMT);
    if (context_for_type_node(let_annotation_type_node(let_node), decl_token, instance_i))
        return true;

    uint return_node = ancestor_with_production(literal_node, PROD_RETURN_STMT);
    uint fn_node = function_like_ancestor(return_node);
    return context_for_type_node(return_type_node(fn_node), decl_token, instance_i);
}

uint struct_node_for_decl_token(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;
    uint node = type_decl_hir_node_by_token[decl_token];
    return valid_node(node) && node_kind[node] == PROD_STRUCT ? node : INVALID;
}

bool same_name_id(uint left_token, uint right_token)
{
    if (!valid_token(left_token) || !valid_token(right_token))
        return false;
    uint left_name = name_id_by_token[left_token];
    uint right_name = name_id_by_token[right_token];
    return left_name != INVALID && left_name == right_name;
}

bool literal_head_matches_decl(uint literal_node, uint decl_token)
{
    uint head_node = hir_struct_lit_head_node[literal_node];
    if (!valid_node(head_node) || !valid_token(decl_token))
        return false;
    return same_name_id(hir_token_pos[head_node], decl_token);
}

bool field_node_for_literal_field(uint struct_node, uint field_token, out uint field_node, out uint field_ordinal)
{
    field_node = INVALID;
    field_ordinal = INVALID;
    if (!valid_node(struct_node) || !valid_token(field_token))
        return false;

    uint field_name = name_id_by_token[field_token];
    if (field_name == INVALID)
        return false;

    uint ordinal = 0u;
    uint n = node_subtree_end(struct_node);
    [loop]
    for (uint j = struct_node + 1u; j < n; j += 1u)
    {
        if (node_kind[j] != PROD_STRUCT_FIELD ||
            hir_struct_field_parent_struct[j] != struct_node)
            continue;

        uint decl_field_token = hir_token_pos[j];
        if (valid_token(decl_field_token) && name_id_by_token[decl_field_token] == field_name)
        {
            field_node = j;
            field_ordinal = ordinal;
            return true;
        }
        ordinal += 1u;
    }
    return false;
}

uint generic_param_slot_for_name(uint decl_node, uint param_token)
{
    if (!valid_node(decl_node) || !valid_token(param_token))
        return INVALID;

    uint param_name = name_id_by_token[param_token];
    if (param_name == INVALID)
        return INVALID;

    uint slot = 0u;
    uint n = node_subtree_end(decl_node);
    [loop]
    for (uint j = decl_node + 1u; j < n; j += 1u)
    {
        if (node_kind[j] != PROD_ENUM_TYPE_PARAM || item_decl_ancestor(j) != decl_node)
            continue;

        uint decl_param_token = hir_token_pos[j];
        if (valid_token(decl_param_token) && name_id_by_token[decl_param_token] == param_name)
            return slot;
        slot += 1u;
    }
    return INVALID;
}

void publish_struct_init_field_node(uint field_node)
{
    uint literal_node = hir_struct_lit_field_parent_lit[field_node];
    if (!valid_node(literal_node))
        return;

    uint field_token = hir_token_pos[field_node];
    if (!valid_token(field_token))
        return;

    uint decl_token = INVALID;
    uint instance_i = INVALID;
    if (!context_for_struct_literal_node(literal_node, decl_token, instance_i))
        return;
    if (!valid_token(decl_token) || !literal_head_matches_decl(literal_node, decl_token))
        return;

    uint struct_node = struct_node_for_decl_token(decl_token);
    if (!valid_node(struct_node))
        return;

    uint decl_field_node;
    uint field_ordinal;
    if (!field_node_for_literal_field(struct_node, field_token, decl_field_node, field_ordinal))
        return;

    uint field_type_node = hir_struct_field_type_node[decl_field_node];
    uint type_head = type_head_token_for_node(field_type_node);
    if (!valid_token(type_head))
        return;

    uint tag = type_expr_ref_tag[type_head];
    uint payload = type_expr_ref_payload[type_head];
    if (tag == TYPE_REF_GENERIC_PARAM)
        payload = generic_param_slot_for_name(struct_node, payload);

    struct_init_field_context_instance[field_token] = instance_i;
    struct_init_field_expected_ref_tag[field_token] = tag;
    struct_init_field_expected_ref_payload[field_token] = payload;
    struct_init_field_ordinal[field_token] = field_ordinal;
    struct_init_field_ordinal_by_node[field_node] = field_ordinal;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (!valid_node(i))
        return;

    struct_init_field_ordinal_by_node[i] = INVALID;

    if (node_kind[i] != PROD_STRUCT_LIT_FIELD)
        return;
    publish_struct_init_field_node(i);
}
