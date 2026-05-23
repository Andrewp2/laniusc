// HIR predicate record collection for generic bounds, where clauses, and trait
// impl headers.
//
// This pass consumes parser-owned predicate parse nodes, generic-parameter
// declaration records, interned name ids, language type records, and module
// declaration records. It publishes node-keyed predicate records for each
// top-level bound expression and trait impl header so later validation can
// reject bad predicates without treating bounds or impls as comments.

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
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_len_value;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_decl_generic_param_count_by_node;
StructuredBuffer<uint> language_type_code_by_name_id;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> sorted_module_key_order;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> decl_type_key_count_out;
StructuredBuffer<uint> decl_type_key_to_decl_id;
StructuredBuffer<uint> decl_module_id;

RWStructuredBuffer<uint> predicate_owner_node;
RWStructuredBuffer<uint> predicate_subject_token;
RWStructuredBuffer<uint> predicate_bound_token;
RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PARENT_WALK = 128u;
static const uint MAX_GENERIC_PARAM_SEARCH = 64u;
static const uint SORT_PATH_SEGMENTS = 8u;
static const uint MODULE_KEY_SEGMENT_ROW_WIDTH = SORT_PATH_SEGMENTS;
static const uint MAX_SIGNATURE_STACK = 16u;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;

static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_INVALID_SUBJECT = 1u;
static const uint PREDICATE_STATUS_BOUND_NOT_TRAIT = 2u;
static const uint PREDICATE_STATUS_UNSUPPORTED = 3u;
static const uint PREDICATE_STATUS_INVALID_ARG = 4u;
static const uint PREDICATE_STATUS_INVALID_TARGET = 5u;
static const uint PREDICATE_STATUS_MISSING_METHOD = 6u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;

static const uint SIGNATURE_TYPE_VOID = 0u;
static const uint SIGNATURE_TYPE_DECL_BASE = 0x10000u;

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
    return valid_node(node) ? parent[node] : INVALID;
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

uint generic_decl_ancestor(uint node)
{
    uint cur = node;
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        if (generic_decl_item_kind(hir_item_kind[cur]))
            return cur;
        cur = parent_node(cur);
    }
    return INVALID;
}

bool generic_param_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_ENUM_TYPE_PARAM;
}

uint generic_param_slot_for_name(uint decl_node, uint name_token)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint count = type_decl_generic_param_count_by_node[decl_node];
    uint max_slots = count == 0u ? MAX_GENERIC_PARAM_SEARCH : count;
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

uint predicate_list_ancestor(uint node)
{
    uint cur = parent_node(node);
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        uint kind = node_kind[cur];
        if (kind == PROD_BOUND_TYPE_ARGS_SOME)
            return INVALID;
        if (kind == PROD_BOUND_TYPE_IDENT || kind == PROD_BOUND_TYPE_REF)
            return INVALID;
        if (kind == PROD_TYPE_PARAM_BOUND_LIST)
            return cur;
        if (kind == PROD_TYPE_PARAM_BOUND ||
            kind == PROD_WHERE_TYPE_BOUND ||
            generic_decl_item_kind(hir_item_kind[cur]))
            return INVALID;
        cur = parent_node(cur);
    }
    return INVALID;
}

bool top_level_predicate_expr(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return (kind == PROD_BOUND_TYPE_IDENT || kind == PROD_BOUND_TYPE_REF) &&
           valid_node(predicate_list_ancestor(node));
}

uint predicate_subject_token_for_list(uint list_node)
{
    if (!valid_node(list_node))
        return INVALID;

    uint owner = parent_node(list_node);
    if (!valid_node(owner))
        return INVALID;

    if (node_kind[owner] == PROD_WHERE_TYPE_BOUND)
        return hir_token_pos[owner];

    if (node_kind[owner] == PROD_TYPE_PARAM_BOUND)
    {
        uint param_node = parent_node(owner);
        return valid_node(param_node) && node_kind[param_node] == PROD_ENUM_TYPE_PARAM
            ? hir_token_pos[param_node]
            : INVALID;
    }

    return INVALID;
}

uint decl_record_count()
{
    return min(decl_count_out[0], gParams.n_hir_nodes);
}

uint module_record_count()
{
    return min(module_count_out[0], gParams.n_hir_nodes);
}

uint type_decl_key_record_count()
{
    return min(decl_type_key_count_out[0], gParams.n_hir_nodes);
}

uint bound_path_node(uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return INVALID;

    uint child = first_child[expr_node];
    return valid_node(child) && node_kind[child] == PROD_BOUND_TYPE_PATH
        ? child
        : INVALID;
}

bool top_level_bound_path_segment_node(uint root_expr_node, uint node)
{
    uint kind = node_kind[node];
    if (kind != PROD_BOUND_TYPE_PATH_IDENT && kind != PROD_PATH_IDENT)
        return false;

    uint cur = parent_node(node);
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        if (cur == root_expr_node)
            return true;

        uint cur_kind = node_kind[cur];
        if (cur_kind == PROD_BOUND_TYPE_IDENT || cur_kind == PROD_BOUND_TYPE_REF)
            return false;

        cur = parent_node(cur);
    }
    return false;
}

uint bound_path_segment_token(uint expr_node, uint segment_i)
{
    uint path = bound_path_node(expr_node);
    if (!valid_node(path))
        return INVALID;

    uint cur_segment = 0u;
    uint end = min(subtree_end[path], active_hir_node_count());
    [loop]
    for (uint node = path + 1u; node < end; node += 1u)
    {
        if (!top_level_bound_path_segment_node(expr_node, node))
            continue;
        if (cur_segment == segment_i)
            return hir_token_pos[node];
        cur_segment += 1u;
    }
    return INVALID;
}

uint bound_path_segment_name_id(uint expr_node, uint segment_i)
{
    uint token = bound_path_segment_token(expr_node, segment_i);
    return valid_token(token) ? name_id_by_token[token] : INVALID;
}

uint bound_path_segment_count(uint expr_node)
{
    uint path = bound_path_node(expr_node);
    if (!valid_node(path))
        return 0u;

    uint count = 0u;
    uint end = min(subtree_end[path], active_hir_node_count());
    [loop]
    for (uint node = path + 1u; node < end; node += 1u)
    {
        if (top_level_bound_path_segment_node(expr_node, node))
            count += 1u;
    }
    return count;
}

uint bound_path_leaf_token(uint expr_node)
{
    uint path = bound_path_node(expr_node);
    if (!valid_node(path))
        return INVALID;

    uint token = INVALID;
    uint end = min(subtree_end[path], active_hir_node_count());
    [loop]
    for (uint node = path + 1u; node < end; node += 1u)
    {
        if (top_level_bound_path_segment_node(expr_node, node))
            token = hir_token_pos[node];
    }
    return token;
}

bool module_key_matches_bound_prefix(uint module_i, uint expr_node, uint prefix_count)
{
    if (module_i >= module_record_count() ||
        prefix_count == 0u ||
        prefix_count > SORT_PATH_SEGMENTS ||
        module_key_segment_count[module_i] != prefix_count)
        return false;

    uint base = module_key_segment_base[module_i];
    [loop]
    for (uint i = 0u; i < SORT_PATH_SEGMENTS; i += 1u)
    {
        if (i >= prefix_count)
            break;
        uint path_name = bound_path_segment_name_id(expr_node, i);
        uint module_name = module_key_segment_name_id[base + i];
        if (path_name == INVALID || module_name != path_name)
            return false;
    }
    return true;
}

uint find_module_for_bound_path_prefix(uint expr_node, uint prefix_count)
{
    uint count = module_record_count();
    [loop]
    for (uint row = 0u; row < count; row += 1u)
    {
        uint module_i = sorted_module_key_order[row];
        if (module_key_matches_bound_prefix(module_i, expr_node, prefix_count))
            return module_i;
    }
    return INVALID;
}

uint find_type_decl_in_module(uint module_id, uint name_id)
{
    if (module_id == INVALID || name_id == INVALID)
        return INVALID;

    uint count = type_decl_key_record_count();
    [loop]
    for (uint row = 0u; row < count; row += 1u)
    {
        uint decl_i = decl_type_key_to_decl_id[row];
        if (decl_i < decl_record_count() &&
            decl_module_id[decl_i] == module_id &&
            decl_namespace[decl_i] == HIR_ITEM_NAMESPACE_TYPE &&
            decl_name_id[decl_i] == name_id)
            return decl_i;
    }
    return INVALID;
}

uint type_decl_for_bound_path(uint expr_node)
{
    uint segment_count = bound_path_segment_count(expr_node);
    if (segment_count == 0u)
        return INVALID;

    uint leaf_name_id = bound_path_segment_name_id(expr_node, segment_count - 1u);
    if (segment_count == 1u)
    {
        uint count = decl_record_count();
        [loop]
        for (uint i = 0u; i < count; i += 1u)
        {
            if (decl_namespace[i] == HIR_ITEM_NAMESPACE_TYPE && decl_name_id[i] == leaf_name_id)
                return i;
        }
        return INVALID;
    }

    uint prefix_count = segment_count - 1u;
    if (prefix_count > SORT_PATH_SEGMENTS)
        return INVALID;

    uint module_i = find_module_for_bound_path_prefix(expr_node, prefix_count);
    return find_type_decl_in_module(module_i, leaf_name_id);
}

bool type_decl_exists_for_bound_path(uint expr_node)
{
    return type_decl_for_bound_path(expr_node) != INVALID;
}

bool trait_decl_exists_for_bound_path(uint expr_node)
{
    uint decl_i = type_decl_for_bound_path(expr_node);
    return decl_i != INVALID &&
           decl_kind[decl_i] == HIR_ITEM_KIND_TRAIT &&
           decl_namespace[decl_i] == HIR_ITEM_NAMESPACE_TYPE;
}

bool language_type_exists_by_name(uint name_id)
{
    if (name_id == INVALID)
        return false;
    return language_type_code_by_name_id[name_id] != 0u;
}

uint type_path_node(uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_TYPE_IDENT)
        return INVALID;

    uint child = first_child[expr_node];
    return valid_node(child) && node_kind[child] == PROD_TYPE_PATH
        ? child
        : INVALID;
}

bool top_level_type_path_segment_node(uint root_expr_node, uint node)
{
    uint kind = node_kind[node];
    if (kind != PROD_TYPE_PATH_IDENT && kind != PROD_PATH_IDENT)
        return false;

    uint cur = parent_node(node);
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        if (cur == root_expr_node)
            return true;

        if (node_kind[cur] == PROD_TYPE_IDENT)
            return false;

        cur = parent_node(cur);
    }
    return false;
}

uint type_path_segment_token(uint expr_node, uint segment_i)
{
    uint path = type_path_node(expr_node);
    if (!valid_node(path))
        return INVALID;

    uint cur_segment = 0u;
    uint end = min(subtree_end[path], active_hir_node_count());
    [loop]
    for (uint node = path + 1u; node < end; node += 1u)
    {
        if (!top_level_type_path_segment_node(expr_node, node))
            continue;
        if (cur_segment == segment_i)
            return hir_token_pos[node];
        cur_segment += 1u;
    }
    return INVALID;
}

uint type_path_segment_name_id(uint expr_node, uint segment_i)
{
    uint token = type_path_segment_token(expr_node, segment_i);
    return valid_token(token) ? name_id_by_token[token] : INVALID;
}

uint type_path_segment_count(uint expr_node)
{
    uint path = type_path_node(expr_node);
    if (!valid_node(path))
        return 0u;

    uint count = 0u;
    uint end = min(subtree_end[path], active_hir_node_count());
    [loop]
    for (uint node = path + 1u; node < end; node += 1u)
    {
        if (top_level_type_path_segment_node(expr_node, node))
            count += 1u;
    }
    return count;
}

uint type_path_leaf_token(uint expr_node)
{
    uint segment_count = type_path_segment_count(expr_node);
    return segment_count == 0u ? INVALID : type_path_segment_token(expr_node, segment_count - 1u);
}

bool module_key_matches_type_prefix(uint module_i, uint expr_node, uint prefix_count)
{
    if (module_i >= module_record_count() ||
        prefix_count == 0u ||
        prefix_count > SORT_PATH_SEGMENTS ||
        module_key_segment_count[module_i] != prefix_count)
        return false;

    uint base = module_key_segment_base[module_i];
    [loop]
    for (uint i = 0u; i < SORT_PATH_SEGMENTS; i += 1u)
    {
        if (i >= prefix_count)
            break;
        uint path_name = type_path_segment_name_id(expr_node, i);
        uint module_name = module_key_segment_name_id[base + i];
        if (path_name == INVALID || module_name != path_name)
            return false;
    }
    return true;
}

uint find_module_for_type_path_prefix(uint expr_node, uint prefix_count)
{
    uint count = module_record_count();
    [loop]
    for (uint row = 0u; row < count; row += 1u)
    {
        uint module_i = sorted_module_key_order[row];
        if (module_key_matches_type_prefix(module_i, expr_node, prefix_count))
            return module_i;
    }
    return INVALID;
}

uint type_decl_for_type_path(uint expr_node)
{
    uint segment_count = type_path_segment_count(expr_node);
    if (segment_count == 0u)
        return INVALID;

    uint leaf_name_id = type_path_segment_name_id(expr_node, segment_count - 1u);
    if (segment_count == 1u)
    {
        uint count = decl_record_count();
        [loop]
        for (uint i = 0u; i < count; i += 1u)
        {
            if (decl_namespace[i] == HIR_ITEM_NAMESPACE_TYPE && decl_name_id[i] == leaf_name_id)
                return i;
        }
        return INVALID;
    }

    uint prefix_count = segment_count - 1u;
    if (prefix_count > SORT_PATH_SEGMENTS)
        return INVALID;

    uint module_i = find_module_for_type_path_prefix(expr_node, prefix_count);
    return find_type_decl_in_module(module_i, leaf_name_id);
}

bool valid_impl_target_type(uint expr_node)
{
    uint segment_count = type_path_segment_count(expr_node);
    if (segment_count == 0u)
        return false;

    uint leaf_token = type_path_leaf_token(expr_node);
    uint leaf_name_id = valid_token(leaf_token) ? name_id_by_token[leaf_token] : INVALID;
    if (segment_count == 1u && language_type_exists_by_name(leaf_name_id))
        return true;

    return type_decl_for_type_path(expr_node) != INVALID;
}

uint method_name_id_from_fn_token(uint fn_token)
{
    uint name_token = fn_token + 1u;
    return valid_token(name_token) ? name_id_by_token[name_token] : INVALID;
}

bool method_param_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_PARAM_NAMED ||
           kind == PROD_PARAM_SELF ||
           kind == PROD_PARAM_SELF_REF;
}

bool signature_type_expr_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_TYPE_IDENT ||
           kind == PROD_TYPE_ARRAY ||
           kind == PROD_TYPE_REF;
}

bool type_arg_container_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_TYPE_ARGS_SOME ||
           kind == PROD_TYPE_ARGS_MORE ||
           kind == PROD_TYPE_ARGS_AFTER_COMMA_MORE;
}

bool direct_type_arg_expr(uint owner_type_node, uint arg_node)
{
    if (!valid_node(owner_type_node) ||
        !signature_type_expr_node(arg_node) ||
        owner_type_node == arg_node)
        return false;

    bool saw_arg_container = false;
    uint cur = parent_node(arg_node);
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        if (cur == owner_type_node)
            return saw_arg_container;

        if (type_arg_container_node(cur))
        {
            saw_arg_container = true;
        }
        else if (signature_type_expr_node(cur))
        {
            return false;
        }

        cur = parent_node(cur);
    }
    return false;
}

uint direct_type_arg_count(uint owner_type_node)
{
    if (!valid_node(owner_type_node))
        return 0u;

    uint count = 0u;
    uint end = min(subtree_end[owner_type_node], active_hir_node_count());
    [loop]
    for (uint node = owner_type_node + 1u; node < end; node += 1u)
    {
        if (direct_type_arg_expr(owner_type_node, node))
            count += 1u;
    }
    return count;
}

uint direct_type_arg_node(uint owner_type_node, uint ordinal)
{
    if (!valid_node(owner_type_node))
        return INVALID;

    uint seen = 0u;
    uint end = min(subtree_end[owner_type_node], active_hir_node_count());
    [loop]
    for (uint node = owner_type_node + 1u; node < end; node += 1u)
    {
        if (!direct_type_arg_expr(owner_type_node, node))
            continue;
        if (seen == ordinal)
            return node;
        seen += 1u;
    }
    return INVALID;
}

uint direct_child_at(uint node, uint ordinal)
{
    if (!valid_node(node))
        return INVALID;

    uint seen = 0u;
    uint end = min(subtree_end[node], active_hir_node_count());
    [loop]
    for (uint child = node + 1u; child < end; child += 1u)
    {
        if (parent_node(child) != node)
            continue;
        if (seen == ordinal)
            return child;
        seen += 1u;
    }
    return INVALID;
}

uint first_signature_type_descendant(uint root)
{
    if (!valid_node(root))
        return INVALID;

    uint end = min(subtree_end[root], active_hir_node_count());
    [loop]
    for (uint node = root + 1u; node < end; node += 1u)
    {
        if (signature_type_expr_node(node))
            return node;
    }
    return INVALID;
}

uint method_param_node_at(uint method_node, uint ordinal)
{
    if (!valid_node(method_node))
        return INVALID;

    uint seen = 0u;
    uint end = min(subtree_end[method_node], active_hir_node_count());
    [loop]
    for (uint node = method_node + 1u; node < end; node += 1u)
    {
        if (!method_param_node(node))
            continue;
        if (seen == ordinal)
            return node;
        seen += 1u;
    }
    return INVALID;
}

uint method_param_count(uint method_node)
{
    if (!valid_node(method_node))
        return 0u;

    uint count = 0u;
    uint end = min(subtree_end[method_node], active_hir_node_count());
    [loop]
    for (uint node = method_node + 1u; node < end; node += 1u)
    {
        if (method_param_node(node))
            count += 1u;
    }
    return count;
}

uint method_param_type_node(uint param_node)
{
    if (!valid_node(param_node))
        return INVALID;

    uint kind = node_kind[param_node];
    if (kind == PROD_PARAM_SELF_REF)
        return INVALID;
    return first_signature_type_descendant(param_node);
}

uint method_return_type_node(uint method_node)
{
    if (!valid_node(method_node))
        return INVALID;

    uint end = min(subtree_end[method_node], active_hir_node_count());
    [loop]
    for (uint node = method_node + 1u; node < end; node += 1u)
    {
        if (node_kind[node] == PROD_RET_TYPE)
            return first_signature_type_descendant(node);
    }
    return INVALID;
}

uint signature_path_head_identity(uint type_node)
{
    if (!valid_node(type_node) || node_kind[type_node] != PROD_TYPE_IDENT)
        return INVALID;

    uint segment_count = type_path_segment_count(type_node);
    if (segment_count == 0u)
        return INVALID;

    uint leaf_token = type_path_leaf_token(type_node);
    if (!valid_token(leaf_token))
        return INVALID;

    uint leaf_name_id = name_id_by_token[leaf_token];
    if (segment_count == 1u && language_type_exists_by_name(leaf_name_id))
        return language_type_code_by_name_id[leaf_name_id];

    uint decl_i = type_decl_for_type_path(type_node);
    if (decl_i != INVALID)
        return SIGNATURE_TYPE_DECL_BASE + decl_i;

    return INVALID;
}

bool trait_signature_generic_slot(uint type_node, uint trait_node, out uint slot)
{
    slot = INVALID;
    if (!valid_node(type_node) ||
        node_kind[type_node] != PROD_TYPE_IDENT ||
        direct_type_arg_count(type_node) != 0u ||
        type_path_segment_count(type_node) != 1u)
        return false;

    uint leaf_token = type_path_leaf_token(type_node);
    slot = valid_token(leaf_token)
        ? generic_param_slot_for_name(trait_node, leaf_token)
        : INVALID;
    return slot != INVALID;
}

uint ref_inner_type_node(uint type_node)
{
    return direct_child_at(type_node, 0u);
}

uint array_elem_type_node(uint type_node)
{
    return direct_child_at(type_node, 0u);
}

uint array_tail_node(uint type_node)
{
    return direct_child_at(type_node, 1u);
}

uint array_tail_kind(uint type_node)
{
    uint tail = array_tail_node(type_node);
    return valid_node(tail) ? node_kind[tail] : INVALID;
}

uint array_len_token(uint type_node)
{
    uint tail = array_tail_node(type_node);
    uint len = direct_child_at(tail, 0u);
    return valid_node(len) ? hir_token_pos[len] : INVALID;
}

bool array_lengths_match(uint trait_type, uint impl_type)
{
    uint trait_len_value = hir_type_len_value[trait_type];
    uint impl_len_value = hir_type_len_value[impl_type];
    if (trait_len_value != INVALID || impl_len_value != INVALID)
        return trait_len_value == impl_len_value;

    uint trait_len_token = array_len_token(trait_type);
    uint impl_len_token = array_len_token(impl_type);
    if (!valid_token(trait_len_token) || !valid_token(impl_len_token))
        return false;

    uint trait_name = name_id_by_token[trait_len_token];
    uint impl_name = name_id_by_token[impl_len_token];
    return trait_name != INVALID && trait_name == impl_name;
}

bool push_signature_pair(
    inout uint top,
    inout uint trait_stack[MAX_SIGNATURE_STACK],
    inout uint impl_stack[MAX_SIGNATURE_STACK],
    inout uint subst_stack[MAX_SIGNATURE_STACK],
    uint trait_type,
    uint impl_type,
    bool substitute_trait_generics)
{
    if (top >= MAX_SIGNATURE_STACK)
        return false;

    trait_stack[top] = trait_type;
    impl_stack[top] = impl_type;
    subst_stack[top] = substitute_trait_generics ? 1u : 0u;
    top += 1u;
    return true;
}

bool signature_types_match(
    uint type_node,
    uint impl_type_node,
    uint trait_node,
    uint impl_trait_type_node,
    bool substitute_trait_generics)
{
    uint trait_stack[MAX_SIGNATURE_STACK];
    uint impl_stack[MAX_SIGNATURE_STACK];
    uint subst_stack[MAX_SIGNATURE_STACK];
    uint top = 0u;
    if (!push_signature_pair(
            top,
            trait_stack,
            impl_stack,
            subst_stack,
            type_node,
            impl_type_node,
            substitute_trait_generics))
        return false;

    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (top == 0u)
            return true;

        top -= 1u;
        uint trait_type = trait_stack[top];
        uint impl_type = impl_stack[top];
        bool subst = subst_stack[top] != 0u;

        if (!valid_node(trait_type) || !valid_node(impl_type))
            return false;

        if (subst)
        {
            uint slot;
            if (trait_signature_generic_slot(trait_type, trait_node, slot))
            {
                uint arg_node = direct_type_arg_node(impl_trait_type_node, slot);
                if (!valid_node(arg_node))
                    return false;
                trait_type = arg_node;
                subst = false;
            }
        }

        uint trait_kind = node_kind[trait_type];
        uint impl_kind = node_kind[impl_type];
        if (trait_kind != impl_kind)
            return false;

        if (trait_kind == PROD_TYPE_IDENT)
        {
            uint trait_identity = signature_path_head_identity(trait_type);
            uint impl_identity = signature_path_head_identity(impl_type);
            if (trait_identity == INVALID || trait_identity != impl_identity)
                return false;

            uint arg_count = direct_type_arg_count(trait_type);
            if (arg_count != direct_type_arg_count(impl_type))
                return false;

            [loop]
            for (uint ordinal = 0u; ordinal < 8u; ordinal += 1u)
            {
                if (ordinal >= arg_count)
                    break;
                if (!push_signature_pair(
                        top,
                        trait_stack,
                        impl_stack,
                        subst_stack,
                        direct_type_arg_node(trait_type, ordinal),
                        direct_type_arg_node(impl_type, ordinal),
                        subst))
                    return false;
            }
        }
        else if (trait_kind == PROD_TYPE_REF)
        {
            if (!push_signature_pair(
                    top,
                    trait_stack,
                    impl_stack,
                    subst_stack,
                    ref_inner_type_node(trait_type),
                    ref_inner_type_node(impl_type),
                    subst))
                return false;
        }
        else if (trait_kind == PROD_TYPE_ARRAY)
        {
            uint trait_tail = array_tail_kind(trait_type);
            uint impl_tail = array_tail_kind(impl_type);
            if (trait_tail != impl_tail)
                return false;
            if (trait_tail == PROD_TYPE_ARRAY_TAIL &&
                !array_lengths_match(trait_type, impl_type))
                return false;
            if (trait_tail != PROD_TYPE_ARRAY_TAIL &&
                trait_tail != PROD_TYPE_SLICE_TAIL)
                return false;
            if (!push_signature_pair(
                    top,
                    trait_stack,
                    impl_stack,
                    subst_stack,
                    array_elem_type_node(trait_type),
                    array_elem_type_node(impl_type),
                    subst))
                return false;
        }
        else
        {
            return false;
        }
    }

    return false;
}

bool method_param_signature_matches(
    uint trait_param,
    uint impl_param,
    uint trait_node,
    uint impl_trait_type_node)
{
    if (!valid_node(trait_param) || !valid_node(impl_param))
        return false;

    uint trait_kind = node_kind[trait_param];
    uint impl_kind = node_kind[impl_param];
    if (trait_kind != impl_kind)
        return false;

    uint trait_type = method_param_type_node(trait_param);
    uint impl_type = method_param_type_node(impl_param);
    if (!valid_node(trait_type) && !valid_node(impl_type))
        return true;
    if (!valid_node(trait_type) || !valid_node(impl_type))
        return false;

    return signature_types_match(
        trait_type,
        impl_type,
        trait_node,
        impl_trait_type_node,
        true);
}

bool method_return_signature_matches(
    uint trait_method,
    uint impl_method,
    uint trait_node,
    uint impl_trait_type_node)
{
    uint trait_type = method_return_type_node(trait_method);
    uint impl_type = method_return_type_node(impl_method);
    if (!valid_node(trait_type) && !valid_node(impl_type))
        return true;
    if (!valid_node(trait_type) || !valid_node(impl_type))
        return false;

    return signature_types_match(
        trait_type,
        impl_type,
        trait_node,
        impl_trait_type_node,
        true);
}

bool method_signatures_match(
    uint trait_method,
    uint impl_method,
    uint trait_node,
    uint impl_trait_type_node)
{
    uint param_count = method_param_count(trait_method);
    [loop]
    for (uint ordinal = 0u; ordinal < 32u; ordinal += 1u)
    {
        if (ordinal >= param_count)
            break;
        uint trait_param = method_param_node_at(trait_method, ordinal);
        uint impl_param = method_param_node_at(impl_method, ordinal);
        if (!method_param_signature_matches(
                trait_param,
                impl_param,
                trait_node,
                impl_trait_type_node))
            return false;
    }

    return method_return_signature_matches(
        trait_method,
        impl_method,
        trait_node,
        impl_trait_type_node);
}

uint impl_method_node_for_name(uint impl_node, uint method_name_id)
{
    if (!valid_node(impl_node) || method_name_id == INVALID)
        return INVALID;

    uint end = min(subtree_end[impl_node], active_hir_node_count());
    [loop]
    for (uint node = impl_node + 1u; node < end; node += 1u)
    {
        if (node_kind[node] != PROD_IMPL_FN)
            continue;

        uint fn_token = hir_token_pos[node];
        if (valid_token(fn_token) && method_name_id_from_fn_token(fn_token) == method_name_id)
            return node;
    }
    return INVALID;
}

uint trait_impl_method_status(
    uint trait_node,
    uint impl_node,
    uint impl_trait_type_node,
    out uint detail_token)
{
    detail_token = INVALID;
    if (!valid_node(trait_node) || !valid_node(impl_node))
        return PREDICATE_STATUS_OK;

    uint end = min(subtree_end[trait_node], active_hir_node_count());
    [loop]
    for (uint node = trait_node + 1u; node < end; node += 1u)
    {
        if (node_kind[node] != PROD_TRAIT_METHOD)
            continue;

        uint fn_token = hir_token_pos[node];
        uint name_token = fn_token + 1u;
        uint name_id = method_name_id_from_fn_token(fn_token);
        if (!valid_token(fn_token) ||
            !valid_token(name_token) ||
            name_id == INVALID)
            continue;

        uint impl_method = impl_method_node_for_name(impl_node, name_id);
        if (!valid_node(impl_method))
        {
            detail_token = name_token;
            return PREDICATE_STATUS_MISSING_METHOD;
        }

        if (method_param_count(node) != method_param_count(impl_method))
        {
            detail_token = name_token;
            return PREDICATE_STATUS_METHOD_ARITY_MISMATCH;
        }

        if (!method_signatures_match(node, impl_method, trait_node, impl_trait_type_node))
        {
            detail_token = name_token;
            return PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH;
        }
    }
    return PREDICATE_STATUS_OK;
}

uint direct_type_expr_child(uint node, uint ordinal)
{
    uint seen = 0u;
    uint child = valid_node(node) ? first_child[node] : INVALID;
    [loop]
    for (uint guard = 0u; guard < 64u && valid_node(child); guard += 1u)
    {
        if (node_kind[child] == PROD_IMPL_METHODS_NONE ||
            node_kind[child] == PROD_IMPL_METHODS_SOME)
            break;

        if (node_kind[child] == PROD_TYPE_IDENT)
        {
            if (seen == ordinal)
                return child;
            seen += 1u;
        }

        uint next = child + 1u < active_hir_node_count() ? child + 1u : INVALID;
        while (valid_node(next) && parent_node(next) != node)
        {
            if (subtree_end[child] > next)
                next = subtree_end[child];
            else
                next += 1u;
        }
        child = next;
    }
    return INVALID;
}

void validate_trait_impl_node(uint node)
{
    uint trait_type_node = direct_type_expr_child(node, 0u);
    uint target_type_node = direct_type_expr_child(node, 1u);
    uint trait_token = type_path_leaf_token(trait_type_node);
    uint target_token = type_path_leaf_token(target_type_node);
    uint trait_arg0 = direct_type_arg_node(trait_type_node, 0u);
    uint trait_arg1 = direct_type_arg_node(trait_type_node, 1u);

    predicate_owner_node[node] = node;
    predicate_bound_token[node] = trait_token;
    predicate_subject_token[node] = target_token;
    predicate_bound_arg_count[node] = direct_type_arg_count(trait_type_node);
    predicate_bound_first_arg_token[node] = valid_node(trait_arg0)
        ? type_path_leaf_token(trait_arg0)
        : INVALID;
    predicate_bound_second_arg_token[node] = valid_node(trait_arg1)
        ? type_path_leaf_token(trait_arg1)
        : INVALID;

    uint trait_decl_i = type_decl_for_type_path(trait_type_node);
    if (!valid_node(trait_type_node) || !valid_token(trait_token) ||
        trait_decl_i == INVALID ||
        decl_kind[trait_decl_i] != HIR_ITEM_KIND_TRAIT ||
        decl_namespace[trait_decl_i] != HIR_ITEM_NAMESPACE_TYPE)
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }

    if (!valid_node(target_type_node) || !valid_token(target_token) ||
        !valid_impl_target_type(target_type_node))
    {
        predicate_status[node] = PREDICATE_STATUS_INVALID_TARGET;
        return;
    }

    uint trait_node = trait_decl_i < decl_record_count() ? decl_hir_node[trait_decl_i] : INVALID;
    if (!valid_node(trait_node))
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }

    uint detail_token = INVALID;
    uint method_status = trait_impl_method_status(trait_node, node, trait_type_node, detail_token);
    if (method_status != PREDICATE_STATUS_OK)
    {
        predicate_bound_first_arg_token[node] = detail_token;
        predicate_bound_second_arg_token[node] = INVALID;
        predicate_status[node] = method_status;
        return;
    }

    predicate_status[node] = PREDICATE_STATUS_OK;
}

bool valid_bound_type_arg(uint owner_decl_node, uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return false;
    uint segment_count = bound_path_segment_count(expr_node);
    if (segment_count == 0u)
        return false;

    uint token = bound_path_leaf_token(expr_node);
    if (!valid_token(token))
        return false;

    uint name_id = name_id_by_token[token];
    if (segment_count == 1u)
    {
        if (generic_param_slot_for_name(owner_decl_node, token) != INVALID)
            return true;
        if (language_type_exists_by_name(name_id))
            return true;
    }
    return type_decl_exists_for_bound_path(expr_node);
}

uint enclosing_bound_args_node(uint node)
{
    uint cur = parent_node(node);
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        uint kind = node_kind[cur];
        if (kind == PROD_BOUND_TYPE_ARGS_SOME)
            return cur;
        if (kind == PROD_TYPE_PARAM_BOUND_LIST ||
            kind == PROD_TYPE_PARAM_BOUND ||
            kind == PROD_WHERE_TYPE_BOUND ||
            generic_decl_item_kind(hir_item_kind[cur]))
            return INVALID;
        cur = parent_node(cur);
    }
    return INVALID;
}

bool top_level_bound_arg_expr(uint predicate_expr_node, uint arg_expr_node)
{
    uint args_node = enclosing_bound_args_node(arg_expr_node);
    if (valid_node(args_node) && parent_node(args_node) == predicate_expr_node)
        return true;

    uint cur = parent_node(arg_expr_node);
    [loop]
    for (uint step = 0u; step < MAX_PARENT_WALK && valid_node(cur); step += 1u)
    {
        if (cur == predicate_expr_node)
            return true;

        uint kind = node_kind[cur];
        if (kind == PROD_BOUND_TYPE_IDENT || kind == PROD_BOUND_TYPE_REF)
            return false;
        if (kind == PROD_TYPE_PARAM_BOUND_LIST ||
            kind == PROD_TYPE_PARAM_BOUND ||
            kind == PROD_WHERE_TYPE_BOUND ||
            generic_decl_item_kind(hir_item_kind[cur]))
            return false;

        cur = parent_node(cur);
    }
    return false;
}

uint validate_bound_type_args(
    uint owner_decl_node,
    uint predicate_expr_node,
    out uint arg_count,
    out uint first_arg_token,
    out uint second_arg_token)
{
    arg_count = 0u;
    first_arg_token = INVALID;
    second_arg_token = INVALID;

    uint end = min(subtree_end[predicate_expr_node], active_hir_node_count());
    [loop]
    for (uint node = predicate_expr_node + 1u; node < end; node += 1u)
    {
        uint kind = node_kind[node];
        if (kind != PROD_BOUND_TYPE_IDENT && kind != PROD_BOUND_TYPE_REF)
            continue;

        if (top_level_bound_arg_expr(predicate_expr_node, node))
        {
            uint token = kind == PROD_BOUND_TYPE_IDENT
                ? bound_path_leaf_token(node)
                : hir_token_pos[node];
            if (first_arg_token == INVALID)
                first_arg_token = token;
            else if (second_arg_token == INVALID)
                second_arg_token = token;
            arg_count += 1u;
        }

        if (!valid_bound_type_arg(owner_decl_node, node))
            return PREDICATE_STATUS_INVALID_ARG;
    }

    return PREDICATE_STATUS_OK;
}

void clear_predicate_record(uint node)
{
    predicate_owner_node[node] = INVALID;
    predicate_subject_token[node] = INVALID;
    predicate_bound_token[node] = INVALID;
    predicate_bound_arg_count[node] = 0u;
    predicate_bound_first_arg_token[node] = INVALID;
    predicate_bound_second_arg_token[node] = INVALID;
    predicate_status[node] = INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    clear_predicate_record(node);

    if (node_kind[node] == PROD_IMPL_TRAIT)
    {
        validate_trait_impl_node(node);
        return;
    }

    if (!top_level_predicate_expr(node))
        return;

    uint owner_decl = generic_decl_ancestor(node);
    uint list_node = predicate_list_ancestor(node);
    uint subject_token = predicate_subject_token_for_list(list_node);
    uint bound_token = node_kind[node] == PROD_BOUND_TYPE_IDENT
        ? bound_path_leaf_token(node)
        : hir_token_pos[node];

    predicate_owner_node[node] = owner_decl;
    predicate_subject_token[node] = subject_token;
    predicate_bound_token[node] = bound_token;

    if (!valid_node(owner_decl) ||
        !valid_token(subject_token) ||
        generic_param_slot_for_name(owner_decl, subject_token) == INVALID)
    {
        predicate_status[node] = PREDICATE_STATUS_INVALID_SUBJECT;
        return;
    }

    if (node_kind[node] != PROD_BOUND_TYPE_IDENT || bound_path_segment_count(node) == 0u)
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED;
        return;
    }

    if (!valid_token(bound_token) || !trait_decl_exists_for_bound_path(node))
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }

    uint arg_count;
    uint first_arg_token;
    uint second_arg_token;
    uint arg_status = validate_bound_type_args(
        owner_decl,
        node,
        arg_count,
        first_arg_token,
        second_arg_token);
    predicate_bound_arg_count[node] = arg_count;
    predicate_bound_first_arg_token[node] = first_arg_token;
    predicate_bound_second_arg_token[node] = second_arg_token;
    predicate_status[node] = arg_status;
}
