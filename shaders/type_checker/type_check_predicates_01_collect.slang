// HIR predicate record collection for generic bounds, where clauses, and trait
// impl headers.
//
// This pass consumes parser-owned predicate parse nodes, generic-parameter
// declaration records, interned name ids, language type records, and module
// declaration records. It publishes node-keyed predicate records for each
// top-level bound expression, trait impl header, and unsupported trait-method
// contract shape so later validation can reject bad predicates without treating
// bounds or impls as comments.

import generated_parse_production_ids;
import fixed_key;
import range_query;

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
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_len_value;
StructuredBuffer<uint> hir_type_arg_start;
StructuredBuffer<uint> hir_type_arg_count;
StructuredBuffer<uint> hir_type_arg_next;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_method_impl_receiver_type_node;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_decl_generic_param_count_by_node;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> generic_decl_owner_by_node;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_node;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_key_order;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> language_type_code_by_name_id;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_visibility;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> sorted_module_key_order;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> decl_type_key_count_out;
StructuredBuffer<uint> decl_type_key_to_decl_id;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<uint> import_visible_type_count_out;
StructuredBuffer<uint> import_visible_type_key_module_id;
StructuredBuffer<uint> import_visible_type_key_name_id;
StructuredBuffer<uint> import_visible_type_key_to_decl_id;
StructuredBuffer<uint> import_visible_type_status;

RWStructuredBuffer<uint> predicate_owner_node;
RWStructuredBuffer<uint> predicate_subject_token;
RWStructuredBuffer<uint> predicate_bound_token;
RWStructuredBuffer<uint> predicate_bound_decl_id;
RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> predicate_method_contract_owner_node;
StructuredBuffer<uint> predicate_method_contract_name_token;
StructuredBuffer<uint> predicate_method_contract_name_id;
StructuredBuffer<uint> predicate_method_contract_param_count;
StructuredBuffer<uint> predicate_method_contract_first_param_node;
StructuredBuffer<uint> predicate_method_contract_return_type_node;
StructuredBuffer<uint> predicate_method_contract_visibility;
StructuredBuffer<uint> predicate_method_contract_status;
StructuredBuffer<uint> predicate_method_contract_param_next_node;
StructuredBuffer<uint> predicate_method_contract_param_type_node;
StructuredBuffer<uint> predicate_method_contract_key_order;
StructuredBuffer<uint> predicate_method_contract_owner_range_first;
StructuredBuffer<uint> predicate_method_contract_owner_range_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PARENT_WALK = 128u;
static const uint SORT_PATH_SEGMENTS = 8u;
static const uint MODULE_KEY_SEGMENT_ROW_WIDTH = SORT_PATH_SEGMENTS;
static const uint MAX_SIGNATURE_STACK = 16u;
static const uint MAX_METHOD_SIGNATURE_PARAMS = 32u;
static const uint MAX_METHOD_CONTRACTS_PER_OWNER = 32u;
static const uint MAX_TYPE_ARG_SHAPE_SCAN = 64u;
static const uint MAX_PREDICATE_PATH_SCAN = 64u;
static const uint PREDICATE_ARG_TYPE_CODE_BIT = 0x80000000u;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;

static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;

static const uint TYPE_REF_INSTANCE = 3u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_INVALID_SUBJECT = 1u;
static const uint PREDICATE_STATUS_BOUND_NOT_TRAIT = 2u;
static const uint PREDICATE_STATUS_UNSUPPORTED = 3u;
static const uint PREDICATE_STATUS_INVALID_ARG = 4u;
static const uint PREDICATE_STATUS_INVALID_TARGET = 5u;
static const uint PREDICATE_STATUS_MISSING_METHOD = 6u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH = 11u;
static const uint PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE = 12u;
static const uint PREDICATE_STATUS_BOUND_ARITY_MISMATCH = 13u;
static const uint PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE = 14u;
static const uint PREDICATE_STATUS_INVALID_IMPL_ARG = 15u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE = 17u;
static const uint PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND = 18u;
static const uint PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD = 20u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION = 22u;
static const uint IMPORT_VISIBLE_STATUS_OK = 0u;

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

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) && parent_node(child) == node ? child : INVALID;
}

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    return valid_node(sibling) && parent_node(sibling) == parent_node(node)
        ? sibling
        : INVALID;
}

uint direct_child_at(uint node, uint ordinal)
{
    uint child = first_child_node(node);
    [loop]
    for (uint seen = 0u; seen <= ordinal && seen < 8u && valid_node(child); seen += 1u)
    {
        if (seen == ordinal)
            return child;
        child = next_sibling_node(child);
    }
    return INVALID;
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

bool callable_generic_decl_item_kind(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_FN ||
           item_kind == HIR_ITEM_KIND_EXTERN_FN;
}

uint generic_decl_owner_for_node(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint owner = generic_decl_owner_by_node[node];
    // Owner records also include impl headers; this pass only supports item-style
    // generic owners for bound predicates, so impl-bound predicates fail closed.
    return valid_node(owner) && generic_decl_item_kind(hir_item_kind[owner])
        ? owner
        : INVALID;
}

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.n_tokens);
}

bool generic_param_key_less(uint row, uint owner, uint name_id)
{
    if (row >= active_generic_param_count())
        return false;

    uint row_owner = generic_param_owner_node[row];
    if (row_owner != owner)
        return row_owner < owner;
    return generic_param_name_id[row] < name_id;
}

bool generic_param_key_matches(uint row, uint owner, uint name_id, uint kind)
{
    return row < active_generic_param_count() &&
           generic_param_owner_node[row] == owner &&
           generic_param_name_id[row] == name_id &&
           generic_param_kind[row] == kind;
}

uint generic_param_row_for_name(uint decl_node, uint name_token, uint kind)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint count = active_generic_param_count();
    uint lo = 0u;
    uint hi = count;
    [unroll]
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint row = generic_param_key_order[mid];
        if (row >= count || !generic_param_key_less(row, decl_node, name_id))
            hi = mid;
        else
            lo = mid + 1u;
    }

    if (lo >= count)
        return INVALID;
    uint row = generic_param_key_order[lo];
    return generic_param_key_matches(row, decl_node, name_id, kind) ? row : INVALID;
}

uint generic_param_slot_for_name(uint decl_node, uint name_token)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint count = type_decl_generic_param_count_by_node[decl_node];
    uint row = generic_param_row_for_name(decl_node, name_token, GENERIC_PARAM_KIND_TYPE);
    if (row == INVALID)
        return INVALID;

    uint param_token = generic_param_token[row];
    // Slots are published for declaration tokens by the generic-param pass.
    uint slot = valid_token(param_token)
        ? type_generic_param_slot_by_token[param_token]
        : INVALID;
    return slot != INVALID && (count == 0u || slot < count) ? slot : INVALID;
}

uint predicate_list_ancestor(uint node, out bool exhausted)
{
    exhausted = false;
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
    exhausted = valid_node(cur);
    return INVALID;
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

uint path_record_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

uint import_visible_type_record_count()
{
    return min(import_visible_type_count_out[0], max(gParams.n_tokens, 1u));
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

bool path_subtree_scan_supported(uint path)
{
    if (!valid_node(path))
        return false;

    uint end = min(subtree_end[path], active_hir_node_count());
    return end <= path + 1u + MAX_PREDICATE_PATH_SCAN;
}

bool bound_path_scan_supported(uint expr_node)
{
    return path_subtree_scan_supported(bound_path_node(expr_node));
}

bool bound_ident_has_direct_arg_list(uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return false;

    uint child = first_child_node(expr_node);
    [loop]
    for (uint guard = 0u; guard < 4u && valid_node(child); guard += 1u)
    {
        uint kind = node_kind[child];
        if (kind == PROD_BOUND_TYPE_ARGS_SOME)
            return true;
        if (kind == PROD_BOUND_TYPE_ARGS_NONE)
            return false;
        child = next_sibling_node(child);
    }
    return false;
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
    if (!valid_node(path) || !path_subtree_scan_supported(path))
        return INVALID;

    uint cur_segment = 0u;
    uint end = min(subtree_end[path], active_hir_node_count());
    uint seen = 0u;
    [loop]
    for (uint node = path + 1u; node < end && seen < MAX_PREDICATE_PATH_SCAN; node += 1u)
    {
        seen += 1u;
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
    if (!valid_node(path) || !path_subtree_scan_supported(path))
        return 0u;

    uint count = 0u;
    uint end = min(subtree_end[path], active_hir_node_count());
    uint seen = 0u;
    [loop]
    for (uint node = path + 1u; node < end && seen < MAX_PREDICATE_PATH_SCAN; node += 1u)
    {
        seen += 1u;
        if (top_level_bound_path_segment_node(expr_node, node))
            count += 1u;
    }
    return count;
}

uint bound_path_leaf_token(uint expr_node)
{
    uint path = bound_path_node(expr_node);
    if (!valid_node(path) || !path_subtree_scan_supported(path))
        return INVALID;

    uint token = INVALID;
    uint end = min(subtree_end[path], active_hir_node_count());
    uint seen = 0u;
    [loop]
    for (uint node = path + 1u; node < end && seen < MAX_PREDICATE_PATH_SCAN; node += 1u)
    {
        seen += 1u;
        if (top_level_bound_path_segment_node(expr_node, node))
            token = hir_token_pos[node];
    }
    return token;
}

uint module_key_segment_value(uint module_i, uint segment_i)
{
    uint value = INVALID;
    if (module_i < module_record_count() &&
        segment_i < min(module_key_segment_count[module_i], MODULE_KEY_SEGMENT_ROW_WIDTH))
    {
        value = module_key_segment_name_id[module_key_segment_base[module_i] + segment_i];
    }
    return fixed_key_encode_nullable_u32(value, INVALID);
}

public struct BoundModulePrefixLookupKey
{
    uint expr_node;
    uint prefix_count;
}

public struct BoundModulePrefixFixedKey : IFixedU32RowKey<BoundModulePrefixLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint module_i = sorted_module_key_order[row];
        return module_key_segment_value(module_i, lane);
    }

    public static uint key_lane(BoundModulePrefixLookupKey key, uint lane)
    {
        uint value = lane < key.prefix_count
            ? bound_path_segment_name_id(key.expr_node, lane)
            : INVALID;
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct BoundModulePrefixCompare : IRowQueryCompare<BoundModulePrefixLookupKey>
{
    public static int compare(uint row, BoundModulePrefixLookupKey key)
    {
        return fixed_u32_row_key_compare<BoundModulePrefixLookupKey, BoundModulePrefixFixedKey>(
            row,
            key,
            SORT_PATH_SEGMENTS);
    }
}

uint find_module_for_bound_path_prefix(uint expr_node, uint prefix_count)
{
    if (prefix_count == 0u || prefix_count > SORT_PATH_SEGMENTS)
        return INVALID;

    BoundModulePrefixLookupKey key;
    key.expr_node = expr_node;
    key.prefix_count = prefix_count;
    uint row = find_equal_query<BoundModulePrefixLookupKey, BoundModulePrefixCompare>(
        module_record_count(),
        key);
    return row == INVALID ? INVALID : sorted_module_key_order[row];
}

public struct ImportVisibleTypeLookupKey
{
    uint module_id;
    uint name_id;
}

public struct TypeDeclLookupKey
{
    uint module_id;
    uint name_id;
}

public struct TypeDeclFixedKey : IFixedU32RowKey<TypeDeclLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint decl_i = decl_type_key_to_decl_id[row];
        uint value = INVALID;
        if (decl_i < decl_record_count())
        {
            if (lane == 0u)
                value = decl_module_id[decl_i];
            else if (lane == 1u)
                value = decl_namespace[decl_i];
            else
                value = decl_name_id[decl_i];
        }
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(TypeDeclLookupKey key, uint lane)
    {
        uint value = lane == 0u
            ? key.module_id
            : (lane == 1u ? HIR_ITEM_NAMESPACE_TYPE : key.name_id);
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct TypeDeclKeyCompare : IRowQueryCompare<TypeDeclLookupKey>
{
    public static int compare(uint row, TypeDeclLookupKey key)
    {
        return fixed_u32_row_key_compare<TypeDeclLookupKey, TypeDeclFixedKey>(
            row,
            key,
            3u);
    }
}

uint find_type_decl_in_module(uint module_id, uint name_id)
{
    if (module_id == INVALID || name_id == INVALID)
        return INVALID;

    TypeDeclLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    uint row = find_equal_query<TypeDeclLookupKey, TypeDeclKeyCompare>(
        type_decl_key_record_count(),
        key);
    if (row == INVALID)
        return INVALID;

    uint decl_i = decl_type_key_to_decl_id[row];
    return decl_i < decl_record_count() ? decl_i : INVALID;
}

public struct ImportVisibleTypeFixedKey : IFixedU32RowKey<ImportVisibleTypeLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint value = lane == 0u
            ? import_visible_type_key_module_id[row]
            : import_visible_type_key_name_id[row];
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(ImportVisibleTypeLookupKey key, uint lane)
    {
        uint value = lane == 0u ? key.module_id : key.name_id;
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct ImportVisibleTypeKeyCompare : IRowQueryCompare<ImportVisibleTypeLookupKey>
{
    public static int compare(uint row, ImportVisibleTypeLookupKey key)
    {
        return fixed_u32_row_key_compare<ImportVisibleTypeLookupKey, ImportVisibleTypeFixedKey>(
            row,
            key,
            2u);
    }
}

uint find_import_visible_type_decl(uint module_id, uint name_id)
{
    if (module_id == INVALID || name_id == INVALID)
        return INVALID;

    ImportVisibleTypeLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    uint row = find_equal_query<ImportVisibleTypeLookupKey, ImportVisibleTypeKeyCompare>(
        import_visible_type_record_count(),
        key);
    if (row == INVALID || import_visible_type_status[row] != IMPORT_VISIBLE_STATUS_OK)
        return INVALID;

    uint decl_i = import_visible_type_key_to_decl_id[row];
    return decl_i < decl_record_count() ? decl_i : INVALID;
}

uint owner_module_for_decl_node(uint owner_decl_node)
{
    if (!valid_node(owner_decl_node))
        return INVALID;

    uint name_token = hir_item_name_token[owner_decl_node];
    if (!valid_token(name_token))
        return INVALID;

    uint decl_i = decl_id_by_name_token[name_token];
    return decl_i < decl_record_count() ? decl_module_id[decl_i] : INVALID;
}

bool decl_visible_from_module(uint owner_module, uint decl_i)
{
    if (decl_i >= decl_record_count())
        return false;

    uint decl_module = decl_module_id[decl_i];
    if (decl_module != INVALID && decl_module == owner_module)
        return true;

    return decl_visibility[decl_i] == HIR_ITEM_VIS_PUBLIC;
}

uint type_decl_for_unqualified_bound_path(uint expr_node, uint owner_decl_node)
{
    uint leaf_name_id = bound_path_segment_name_id(expr_node, 0u);
    uint owner_module = owner_module_for_decl_node(owner_decl_node);
    if (owner_module == INVALID)
        return INVALID;

    uint local_decl = find_type_decl_in_module(owner_module, leaf_name_id);
    if (local_decl != INVALID)
        return local_decl;

    return find_import_visible_type_decl(owner_module, leaf_name_id);
}

uint type_decl_for_bound_path(uint expr_node, uint owner_decl_node)
{
    uint segment_count = bound_path_segment_count(expr_node);
    if (segment_count == 0u)
        return INVALID;

    uint leaf_name_id = bound_path_segment_name_id(expr_node, segment_count - 1u);
    if (segment_count == 1u)
        return type_decl_for_unqualified_bound_path(expr_node, owner_decl_node);

    uint prefix_count = segment_count - 1u;
    if (prefix_count > SORT_PATH_SEGMENTS)
        return INVALID;

    uint owner_module = owner_module_for_decl_node(owner_decl_node);
    uint module_i = find_module_for_bound_path_prefix(expr_node, prefix_count);
    uint decl_i = find_type_decl_in_module(module_i, leaf_name_id);
    return decl_visible_from_module(owner_module, decl_i) ? decl_i : INVALID;
}

bool type_decl_exists_for_bound_path(uint expr_node, uint owner_decl_node)
{
    return type_decl_for_bound_path(expr_node, owner_decl_node) != INVALID;
}

bool trait_decl_exists_for_bound_path(uint expr_node, uint owner_decl_node)
{
    uint decl_i = type_decl_for_bound_path(expr_node, owner_decl_node);
    return decl_i != INVALID &&
           decl_kind[decl_i] == HIR_ITEM_KIND_TRAIT &&
           decl_namespace[decl_i] == HIR_ITEM_NAMESPACE_TYPE;
}

uint trait_decl_generic_param_count(uint decl_i)
{
    if (decl_i >= decl_record_count())
        return INVALID;

    uint trait_node = decl_hir_node[decl_i];
    return valid_node(trait_node)
        ? type_decl_generic_param_count_by_node[trait_node]
        : INVALID;
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

bool type_path_scan_supported(uint expr_node)
{
    return path_subtree_scan_supported(type_path_node(expr_node));
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
    if (!valid_node(path) || !path_subtree_scan_supported(path))
        return INVALID;

    uint cur_segment = 0u;
    uint end = min(subtree_end[path], active_hir_node_count());
    uint seen = 0u;
    [loop]
    for (uint node = path + 1u; node < end && seen < MAX_PREDICATE_PATH_SCAN; node += 1u)
    {
        seen += 1u;
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
    if (!valid_node(path) || !path_subtree_scan_supported(path))
        return 0u;

    uint count = 0u;
    uint end = min(subtree_end[path], active_hir_node_count());
    uint seen = 0u;
    [loop]
    for (uint node = path + 1u; node < end && seen < MAX_PREDICATE_PATH_SCAN; node += 1u)
    {
        seen += 1u;
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

uint owner_module_for_type_path(uint expr_node)
{
    if (!valid_node(expr_node))
        return INVALID;

    uint path_i = path_id_by_owner_hir[expr_node];
    return path_i != INVALID && path_i < path_record_count()
        ? path_owner_module_id[path_i]
        : INVALID;
}

public struct TypeModulePrefixLookupKey
{
    uint expr_node;
    uint prefix_count;
}

public struct TypeModulePrefixFixedKey : IFixedU32RowKey<TypeModulePrefixLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint module_i = sorted_module_key_order[row];
        return module_key_segment_value(module_i, lane);
    }

    public static uint key_lane(TypeModulePrefixLookupKey key, uint lane)
    {
        uint value = lane < key.prefix_count
            ? type_path_segment_name_id(key.expr_node, lane)
            : INVALID;
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct TypeModulePrefixCompare : IRowQueryCompare<TypeModulePrefixLookupKey>
{
    public static int compare(uint row, TypeModulePrefixLookupKey key)
    {
        return fixed_u32_row_key_compare<TypeModulePrefixLookupKey, TypeModulePrefixFixedKey>(
            row,
            key,
            SORT_PATH_SEGMENTS);
    }
}

uint find_module_for_type_path_prefix(uint expr_node, uint prefix_count)
{
    if (prefix_count == 0u || prefix_count > SORT_PATH_SEGMENTS)
        return INVALID;

    TypeModulePrefixLookupKey key;
    key.expr_node = expr_node;
    key.prefix_count = prefix_count;
    uint row = find_equal_query<TypeModulePrefixLookupKey, TypeModulePrefixCompare>(
        module_record_count(),
        key);
    return row == INVALID ? INVALID : sorted_module_key_order[row];
}

uint type_decl_for_unqualified_type_path(uint expr_node)
{
    uint leaf_name_id = type_path_segment_name_id(expr_node, 0u);
    uint owner_module = owner_module_for_type_path(expr_node);
    if (owner_module == INVALID)
        return INVALID;

    uint local_decl = find_type_decl_in_module(owner_module, leaf_name_id);
    if (local_decl != INVALID)
        return local_decl;

    return find_import_visible_type_decl(owner_module, leaf_name_id);
}

uint type_decl_for_type_path(uint expr_node)
{
    uint segment_count = type_path_segment_count(expr_node);
    if (segment_count == 0u)
        return INVALID;

    uint leaf_name_id = type_path_segment_name_id(expr_node, segment_count - 1u);
    if (segment_count == 1u)
        return type_decl_for_unqualified_type_path(expr_node);

    uint prefix_count = segment_count - 1u;
    if (prefix_count > SORT_PATH_SEGMENTS)
        return INVALID;

    uint owner_module = owner_module_for_type_path(expr_node);
    uint module_i = find_module_for_type_path_prefix(expr_node, prefix_count);
    uint decl_i = find_type_decl_in_module(module_i, leaf_name_id);
    return decl_visible_from_module(owner_module, decl_i) ? decl_i : INVALID;
}

uint validate_trait_impl_target_type(uint expr_node)
{
    if (!type_path_scan_supported(expr_node))
        return PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;

    uint segment_count = type_path_segment_count(expr_node);
    if (segment_count == 0u)
        return PREDICATE_STATUS_INVALID_TARGET;

    uint leaf_token = type_path_leaf_token(expr_node);
    uint leaf_name_id = valid_token(leaf_token) ? name_id_by_token[leaf_token] : INVALID;
    uint arg_count = valid_node(expr_node) ? hir_type_arg_count[expr_node] : 0u;
    if (segment_count == 1u && language_type_exists_by_name(leaf_name_id))
        return arg_count == 0u
            ? PREDICATE_STATUS_OK
            : PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;

    uint decl_i = type_decl_for_type_path(expr_node);
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return PREDICATE_STATUS_INVALID_TARGET;
    if (decl_kind[decl_i] == HIR_ITEM_KIND_TRAIT &&
        decl_namespace[decl_i] == HIR_ITEM_NAMESPACE_TYPE)
        return PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;
    if (decl_kind[decl_i] == HIR_ITEM_KIND_TYPE_ALIAS &&
        valid_token(leaf_token) &&
        type_expr_ref_tag[leaf_token] == TYPE_REF_INSTANCE)
        return PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;

    uint decl_node = decl_hir_node[decl_i];
    uint expected_arg_count = valid_node(decl_node)
        ? type_decl_generic_param_count_by_node[decl_node]
        : INVALID;
    if (expected_arg_count == INVALID)
        return PREDICATE_STATUS_INVALID_TARGET;

    return arg_count == 0u && expected_arg_count == 0u
        ? PREDICATE_STATUS_OK
        : PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;
}

bool trait_impl_type_arg_resolves(uint arg_node)
{
    if (!type_path_scan_supported(arg_node))
        return false;

    uint segment_count = type_path_segment_count(arg_node);
    if (segment_count == 0u)
        return false;

    uint leaf_token = type_path_leaf_token(arg_node);
    uint leaf_name_id = valid_token(leaf_token) ? name_id_by_token[leaf_token] : INVALID;
    if (segment_count == 1u && language_type_exists_by_name(leaf_name_id))
        return true;

    return type_decl_for_type_path(arg_node) != INVALID;
}

bool type_arg_requires_instance_args(uint arg_node)
{
    if (!type_path_scan_supported(arg_node))
        return true;

    uint segment_count = type_path_segment_count(arg_node);
    if (segment_count == 0u)
        return false;

    uint leaf_token = type_path_leaf_token(arg_node);
    uint leaf_name_id = valid_token(leaf_token) ? name_id_by_token[leaf_token] : INVALID;
    if (segment_count == 1u && language_type_exists_by_name(leaf_name_id))
        return false;

    uint decl_i = type_decl_for_type_path(arg_node);
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return false;

    uint decl_node = decl_hir_node[decl_i];
    uint expected_arg_count = valid_node(decl_node)
        ? type_decl_generic_param_count_by_node[decl_node]
        : 0u;
    return expected_arg_count > 0u && direct_type_arg_count(arg_node) == 0u;
}

bool type_expr_contains_nested_type_args(uint root)
{
    if (!valid_node(root))
        return false;

    uint end = min(subtree_end[root], active_hir_node_count());
    uint node = root + 1u;
    uint seen = 0u;
    [loop]
    for (;
         node < end && seen < MAX_TYPE_ARG_SHAPE_SCAN;
         node += 1u, seen += 1u)
    {
        if (node_kind[node] == PROD_TYPE_ARGS_SOME && parent_node(node) != root)
            return true;
        if (node_kind[node] == PROD_TYPE_IDENT && direct_type_arg_count(node) != 0u)
            return true;
    }

    return node < end;
}

bool trait_type_region_contains_nested_type_args(uint trait_type_node, uint target_type_node)
{
    if (!valid_node(trait_type_node))
        return false;

    uint end = valid_node(target_type_node)
        ? target_type_node
        : min(subtree_end[trait_type_node], active_hir_node_count());
    bool seen_trait_arg_list = false;
    uint node = trait_type_node + 1u;
    uint seen = 0u;
    [loop]
    for (;
         node < end && seen < MAX_TYPE_ARG_SHAPE_SCAN;
         node += 1u, seen += 1u)
    {
        if (node_kind[node] != PROD_TYPE_ARGS_SOME)
            continue;
        if (seen_trait_arg_list)
            return true;
        seen_trait_arg_list = true;
    }

    return node < end;
}

bool trait_method_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_TRAIT_METHOD || kind == PROD_TRAIT_METHOD_PUB;
}

uint method_contract_name_token(uint method_node)
{
    if (!valid_node(method_node))
        return INVALID;
    uint token = predicate_method_contract_name_token[method_node];
    return valid_token(token) ? token : INVALID;
}

uint method_contract_name_id(uint method_node)
{
    if (!valid_node(method_node))
        return INVALID;
    return predicate_method_contract_name_id[method_node];
}

bool method_contract_lookup_row_valid(uint method_node)
{
    if (!valid_node(method_node))
        return false;
    return valid_node(predicate_method_contract_owner_node[method_node]) &&
           method_contract_name_id(method_node) != INVALID;
}

public struct MethodContractLookupKey
{
    uint owner_node;
    uint name_id;
}

public struct MethodContractFixedKey : IFixedU32RowKey<MethodContractLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint method_node = row < active_hir_node_count()
            ? predicate_method_contract_key_order[row]
            : INVALID;
        if (!method_contract_lookup_row_valid(method_node))
            return 0u;

        if (lane == 0u)
            return fixed_key_encode_nullable_u32(
                predicate_method_contract_owner_node[method_node],
                INVALID);
        return fixed_key_encode_nullable_u32(method_contract_name_id(method_node), INVALID);
    }

    public static uint key_lane(MethodContractLookupKey key, uint lane)
    {
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(key.owner_node, INVALID);
        return fixed_key_encode_nullable_u32(key.name_id, INVALID);
    }
}

public struct MethodContractKeyCompare : IRowQueryCompare<MethodContractLookupKey>
{
    public static int compare(uint row, MethodContractLookupKey key)
    {
        return fixed_u32_row_key_compare<MethodContractLookupKey, MethodContractFixedKey>(
            row,
            key,
            2u);
    }
}

QueryRange method_contract_range_for_owner_name(uint owner_node, uint name_id)
{
    MethodContractLookupKey key;
    key.owner_node = owner_node;
    key.name_id = name_id;
    return equal_range_query<MethodContractLookupKey, MethodContractKeyCompare>(
        active_hir_node_count(),
        key);
}

QueryRange method_contract_range_for_owner(uint owner_node)
{
    QueryRange range;
    range.begin = 0u;
    range.end = 0u;
    if (!valid_node(owner_node))
        return range;

    uint first = predicate_method_contract_owner_range_first[owner_node];
    uint count = predicate_method_contract_owner_range_count[owner_node];
    if (first == INVALID || count == 0u)
        return range;

    uint active = active_hir_node_count();
    range.begin = min(first, active);
    range.end = min(first + count, active);
    if (range.end < range.begin)
        range.end = range.begin;
    return range;
}

bool method_contract_node_matches_owner_name(uint method_node, uint owner_node, uint name_id)
{
    return method_contract_lookup_row_valid(method_node) &&
           predicate_method_contract_owner_node[method_node] == owner_node &&
           method_contract_name_id(method_node) == name_id;
}

bool method_contract_order_row_matches_owner(uint row, uint owner_node)
{
    uint active = active_hir_node_count();
    if (row >= active)
        return false;

    uint method_node = predicate_method_contract_key_order[row];
    return method_contract_lookup_row_valid(method_node) &&
           predicate_method_contract_owner_node[method_node] == owner_node;
}

bool method_contract_order_row_matches_owner_name(uint row, uint owner_node, uint name_id)
{
    uint active = active_hir_node_count();
    if (row >= active)
        return false;

    uint method_node = predicate_method_contract_key_order[row];
    return method_contract_node_matches_owner_name(method_node, owner_node, name_id);
}

bool method_contract_range_matches_owner(uint owner_node, QueryRange range)
{
    if (!valid_node(owner_node))
        return false;
    if (range.begin >= range.end)
        return true;
    if (range.end > active_hir_node_count())
        return false;

    return method_contract_order_row_matches_owner(range.begin, owner_node) &&
           method_contract_order_row_matches_owner(range.end - 1u, owner_node);
}

uint method_contract_range_count(QueryRange range)
{
    return range.end >= range.begin ? range.end - range.begin : INVALID;
}

bool method_contract_range_within_owner_window(QueryRange range)
{
    uint count = method_contract_range_count(range);
    return count != INVALID && count <= MAX_METHOD_CONTRACTS_PER_OWNER;
}

bool method_contract_range_matches_owner_name(
    uint owner_node,
    uint name_id,
    QueryRange range)
{
    if (!valid_node(owner_node) || name_id == INVALID)
        return false;
    if (range.begin >= range.end)
        return true;
    if (range.end > active_hir_node_count())
        return false;

    return method_contract_order_row_matches_owner_name(range.begin, owner_node, name_id) &&
           method_contract_order_row_matches_owner_name(range.end - 1u, owner_node, name_id);
}

uint first_method_contract_for_owner_name(uint owner_node, uint name_id)
{
    if (!valid_node(owner_node) || name_id == INVALID)
        return INVALID;

    QueryRange range = method_contract_range_for_owner_name(owner_node, name_id);
    if (range.begin >= range.end ||
        !method_contract_range_matches_owner_name(owner_node, name_id, range))
        return INVALID;

    uint method_node = predicate_method_contract_key_order[range.begin];
    return method_contract_node_matches_owner_name(method_node, owner_node, name_id)
        ? method_node
        : INVALID;
}

bool duplicate_method_contract_for_owner_name(uint owner_node, uint name_id)
{
    if (!valid_node(owner_node) || name_id == INVALID)
        return false;

    QueryRange range = method_contract_range_for_owner_name(owner_node, name_id);
    return range.end > range.begin + 1u &&
           method_contract_range_matches_owner_name(owner_node, name_id, range);
}

uint direct_type_arg_count(uint owner_type_node)
{
    return valid_node(owner_type_node) ? hir_type_arg_count[owner_type_node] : 0u;
}

uint direct_type_arg_node(uint owner_type_node, uint ordinal)
{
    if (!valid_node(owner_type_node))
        return INVALID;

    uint node = hir_type_arg_start[owner_type_node];
    [loop]
    for (uint seen = 0u; seen <= ordinal && seen < 8u && valid_node(node); seen += 1u)
    {
        if (seen == ordinal)
            return node;
        node = hir_type_arg_next[node];
    }
    return INVALID;
}

uint method_param_node_at(uint method_node, uint ordinal)
{
    if (!valid_node(method_node))
        return INVALID;

    uint node = predicate_method_contract_first_param_node[method_node];
    [loop]
    for (uint seen = 0u;
         seen <= ordinal && seen < MAX_METHOD_SIGNATURE_PARAMS && valid_node(node);
         seen += 1u)
    {
        if (seen == ordinal)
            return node;
        node = predicate_method_contract_param_next_node[node];
    }
    return INVALID;
}

uint method_param_count(uint method_node)
{
    if (!valid_node(method_node))
        return 0u;

    return predicate_method_contract_param_count[method_node];
}

uint method_param_type_node(uint param_node)
{
    if (!valid_node(param_node))
        return INVALID;

    // 00c owns parameter-shape extraction; this collector only consumes the
    // node-keyed relation and fails closed if it was not published.
    uint contract_type_node = predicate_method_contract_param_type_node[param_node];
    return valid_node(contract_type_node) ? contract_type_node : INVALID;
}

uint method_return_type_node(uint method_node)
{
    if (!valid_node(method_node))
        return INVALID;

    uint type_node = predicate_method_contract_return_type_node[method_node];
    return valid_node(type_node) ? type_node : INVALID;
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
    if (param_count > MAX_METHOD_SIGNATURE_PARAMS)
        return false;

    [loop]
    for (uint ordinal = 0u; ordinal < MAX_METHOD_SIGNATURE_PARAMS; ordinal += 1u)
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
    return first_method_contract_for_owner_name(impl_node, method_name_id);
}

uint trait_method_node_for_name(uint trait_node, uint method_name_id)
{
    return first_method_contract_for_owner_name(trait_node, method_name_id);
}

uint trait_owner_node_for_method(uint method_node)
{
    uint owner = valid_node(method_node)
        ? predicate_method_contract_owner_node[method_node]
        : INVALID;
    return valid_node(owner) && hir_item_kind[owner] == HIR_ITEM_KIND_TRAIT
        ? owner
        : INVALID;
}

bool duplicate_trait_method_node(uint method_node)
{
    uint trait_node = trait_owner_node_for_method(method_node);
    uint name_id = method_contract_name_id(method_node);
    if (!valid_node(trait_node) || name_id == INVALID)
        return false;

    QueryRange range = method_contract_range_for_owner_name(trait_node, name_id);
    if (range.end <= range.begin + 1u)
        return false;

    uint first_method = predicate_method_contract_key_order[range.begin];
    return method_contract_node_matches_owner_name(first_method, trait_node, name_id) &&
           first_method != method_node;
}

bool impl_method_is_public(uint impl_method)
{
    return valid_node(impl_method) &&
           predicate_method_contract_visibility[impl_method] == HIR_ITEM_VIS_PUBLIC;
}

bool trait_impl_method_visibility_matches(uint trait_method, uint impl_method)
{
    return node_kind[trait_method] != PROD_TRAIT_METHOD_PUB || impl_method_is_public(impl_method);
}

bool trait_impl_header_is_public(uint impl_node)
{
    uint cur = parent_node(impl_node);
    [loop]
    for (uint guard = 0u; guard < 4u && valid_node(cur); guard += 1u)
    {
        uint kind = node_kind[cur];
        if (kind == PROD_PUB_IMPL)
            return true;
        if (kind == PROD_ITEM_IMPL)
            return false;
        cur = parent_node(cur);
    }
    return false;
}

bool trait_impl_header_visibility_matches_trait(uint trait_decl_i, uint impl_node)
{
    if (trait_decl_i >= decl_record_count())
        return false;
    bool trait_is_public = decl_visibility[trait_decl_i] == HIR_ITEM_VIS_PUBLIC;
    bool impl_is_public = trait_impl_header_is_public(impl_node);
    return trait_is_public == impl_is_public;
}

uint method_unsupported_contract_status(uint method_node)
{
    if (!valid_node(method_node))
        return PREDICATE_STATUS_OK;

    uint record_status = predicate_method_contract_status[method_node];
    return record_status != INVALID ? record_status : PREDICATE_STATUS_OK;
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

    QueryRange trait_methods = method_contract_range_for_owner(trait_node);
    if (!method_contract_range_matches_owner(trait_node, trait_methods))
        return PREDICATE_STATUS_MISSING_METHOD;
    if (!method_contract_range_within_owner_window(trait_methods))
        return PREDICATE_STATUS_METHOD_ARITY_MISMATCH;

    QueryRange impl_methods = method_contract_range_for_owner(impl_node);
    if (!method_contract_range_matches_owner(impl_node, impl_methods) ||
        !method_contract_range_within_owner_window(impl_methods))
        return PREDICATE_STATUS_METHOD_ARITY_MISMATCH;

    uint trait_method_count = method_contract_range_count(trait_methods);
    uint impl_method_count = method_contract_range_count(impl_methods);
    [loop]
    for (uint offset = 0u; offset < MAX_METHOD_CONTRACTS_PER_OWNER; offset += 1u)
    {
        if (offset >= trait_method_count)
            break;
        uint row = trait_methods.begin + offset;
        uint node = predicate_method_contract_key_order[row];
        if (!method_contract_lookup_row_valid(node) ||
            predicate_method_contract_owner_node[node] != trait_node)
            continue;

        uint name_token = method_contract_name_token(node);
        uint name_id = method_contract_name_id(node);
        if (!valid_token(name_token) || name_id == INVALID)
            continue;

        uint impl_method = impl_method_node_for_name(impl_node, name_id);
        if (!valid_node(impl_method))
        {
            detail_token = name_token;
            return PREDICATE_STATUS_MISSING_METHOD;
        }

        uint trait_contract_status = method_unsupported_contract_status(node);
        if (trait_contract_status != PREDICATE_STATUS_OK)
        {
            detail_token = name_token;
            return trait_contract_status;
        }

        uint impl_contract_status = method_unsupported_contract_status(impl_method);
        if (impl_contract_status != PREDICATE_STATUS_OK)
        {
            uint impl_name_token = method_contract_name_token(impl_method);
            detail_token = valid_token(impl_name_token) ? impl_name_token : name_token;
            return impl_contract_status;
        }

        if (duplicate_method_contract_for_owner_name(impl_node, name_id))
        {
            uint impl_name_token = method_contract_name_token(impl_method);
            detail_token = valid_token(impl_name_token) ? impl_name_token : name_token;
            return PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD;
        }

        if (!trait_impl_method_visibility_matches(node, impl_method))
        {
            uint impl_name_token = method_contract_name_token(impl_method);
            detail_token = valid_token(impl_name_token) ? impl_name_token : name_token;
            return PREDICATE_STATUS_METHOD_ARITY_MISMATCH;
        }

        uint trait_param_count = method_param_count(node);
        uint impl_param_count = method_param_count(impl_method);
        if (trait_param_count > MAX_METHOD_SIGNATURE_PARAMS ||
            impl_param_count > MAX_METHOD_SIGNATURE_PARAMS)
        {
            detail_token = name_token;
            return PREDICATE_STATUS_METHOD_ARITY_MISMATCH;
        }

        if (trait_param_count != impl_param_count)
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

    if (impl_method_count != trait_method_count)
    {
        uint impl_token = hir_token_pos[impl_node];
        detail_token = valid_token(impl_token) ? impl_token : detail_token;
        return PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH;
    }

    return PREDICATE_STATUS_OK;
}

uint impl_receiver_type_node(uint impl_node)
{
    uint type_node = valid_node(impl_node)
        ? hir_method_impl_receiver_type_node[impl_node]
        : INVALID;
    return valid_node(type_node) ? type_node : INVALID;
}

uint direct_type_expr_child(uint node, uint ordinal)
{
    uint seen = 0u;
    uint child = direct_child_at(node, 0u);
    [loop]
    for (uint guard = 0u; guard < 8u && valid_node(child); guard += 1u)
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

        child = next_sibling_node(child);
    }
    return INVALID;
}

uint validate_trait_impl_type_args(
    uint trait_type_node,
    uint target_type_node,
    out uint arg_count,
    out uint first_arg_token,
    out uint second_arg_token)
{
    arg_count = 0u;
    first_arg_token = INVALID;
    second_arg_token = INVALID;

    if (!type_path_scan_supported(trait_type_node))
        return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;

    arg_count = direct_type_arg_count(trait_type_node);

    if (arg_count > 2u)
        return PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH;

    if (trait_type_region_contains_nested_type_args(trait_type_node, target_type_node))
        return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;

    if (type_expr_contains_nested_type_args(trait_type_node))
        return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;

    [loop]
    for (uint ordinal = 0u; ordinal < 2u; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;

        uint arg_node = direct_type_arg_node(trait_type_node, ordinal);
        if (!valid_node(arg_node))
            return PREDICATE_STATUS_INVALID_IMPL_ARG;

        if (!type_path_scan_supported(arg_node))
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;

        if (node_kind[arg_node] != PROD_TYPE_IDENT || direct_type_arg_count(arg_node) != 0u)
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;

        if (type_arg_requires_instance_args(arg_node))
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;

        uint token = type_path_leaf_token(arg_node);
        if (!valid_token(token))
            return PREDICATE_STATUS_INVALID_IMPL_ARG;

        if (!trait_impl_type_arg_resolves(arg_node))
            return PREDICATE_STATUS_INVALID_IMPL_ARG;

        if (ordinal == 0u)
            first_arg_token = token;
        else
            second_arg_token = token;
    }

    return PREDICATE_STATUS_OK;
}

void validate_trait_impl_node(uint node)
{
    uint trait_type_node = direct_type_expr_child(node, 0u);
    uint target_type_node = impl_receiver_type_node(node);
    uint trait_token = type_path_leaf_token(trait_type_node);
    uint target_token = type_path_leaf_token(target_type_node);
    uint trait_arg_count;
    uint trait_arg0_token;
    uint trait_arg1_token;
    uint trait_arg_status = validate_trait_impl_type_args(
        trait_type_node,
        target_type_node,
        trait_arg_count,
        trait_arg0_token,
        trait_arg1_token);
    uint target_status = valid_node(target_type_node)
        ? validate_trait_impl_target_type(target_type_node)
        : PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;

    predicate_owner_node[node] = node;
    predicate_bound_token[node] = trait_token;
    predicate_subject_token[node] = target_token;
    predicate_bound_arg_count[node] = trait_arg_count;
    predicate_bound_first_arg_token[node] = trait_arg0_token;
    predicate_bound_second_arg_token[node] = trait_arg1_token;

    uint trait_decl_i = type_decl_for_type_path(trait_type_node);
    if (!valid_node(trait_type_node) || !valid_token(trait_token) ||
        trait_decl_i == INVALID ||
        decl_kind[trait_decl_i] != HIR_ITEM_KIND_TRAIT ||
        decl_namespace[trait_decl_i] != HIR_ITEM_NAMESPACE_TYPE)
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }

    predicate_bound_decl_id[node] = trait_decl_i;

    if (!trait_impl_header_visibility_matches_trait(trait_decl_i, node))
    {
        predicate_status[node] = PREDICATE_STATUS_INVALID_IMPL_ARG;
        return;
    }

    if (target_status == PREDICATE_STATUS_INVALID_TARGET ||
        (target_status == PREDICATE_STATUS_OK &&
         (!valid_node(target_type_node) || !valid_token(target_token))))
    {
        predicate_status[node] = PREDICATE_STATUS_INVALID_TARGET;
        return;
    }

    if (target_status != PREDICATE_STATUS_OK)
    {
        predicate_status[node] = target_status;
        return;
    }

    if (trait_arg_status != PREDICATE_STATUS_OK)
    {
        predicate_status[node] = trait_arg_status;
        return;
    }

    uint trait_node = trait_decl_i < decl_record_count() ? decl_hir_node[trait_decl_i] : INVALID;
    if (!valid_node(trait_node))
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }

    if (trait_arg_count != trait_decl_generic_param_count(trait_decl_i))
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_ARITY_MISMATCH;
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

void validate_inherent_impl_header_node(uint node)
{
    uint receiver_type_node = impl_receiver_type_node(node);
    uint receiver_token = type_path_leaf_token(receiver_type_node);
    predicate_owner_node[node] = node;
    predicate_bound_token[node] = receiver_token;

    if (!valid_node(receiver_type_node))
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;
        return;
    }

    uint decl_i = type_decl_for_type_path(receiver_type_node);
    if (decl_i != INVALID &&
        decl_i < decl_record_count() &&
        decl_kind[decl_i] == HIR_ITEM_KIND_TRAIT &&
        decl_namespace[decl_i] == HIR_ITEM_NAMESPACE_TYPE)
    {
        predicate_bound_decl_id[node] = decl_i;
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
    }
}

void validate_trait_method_contract_node(uint node)
{
    if (!trait_method_node(node))
        return;

    uint method_status = method_unsupported_contract_status(node);
    if (method_status == PREDICATE_STATUS_OK &&
        !method_contract_lookup_row_valid(node))
        method_status = PREDICATE_STATUS_METHOD_ARITY_MISMATCH;
    if (method_status == PREDICATE_STATUS_OK && duplicate_trait_method_node(node))
        method_status = PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD;
    if (method_status == PREDICATE_STATUS_OK)
        return;

    uint name_token = method_contract_name_token(node);
    uint diagnostic_token = valid_token(name_token) ? name_token : hir_token_pos[node];
    predicate_owner_node[node] = node;
    predicate_bound_token[node] = diagnostic_token;
    predicate_bound_first_arg_token[node] = diagnostic_token;
    predicate_status[node] = method_status;
}

bool valid_bound_type_arg(uint owner_decl_node, uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return false;
    if (!bound_path_scan_supported(expr_node))
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
    return type_decl_exists_for_bound_path(expr_node, owner_decl_node);
}

bool bound_arg_requires_instance_args(uint owner_decl_node, uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return false;
    if (!bound_path_scan_supported(expr_node))
        return true;

    uint segment_count = bound_path_segment_count(expr_node);
    if (segment_count == 0u)
        return false;

    uint token = bound_path_leaf_token(expr_node);
    if (!valid_token(token))
        return false;

    if (segment_count == 1u)
    {
        if (generic_param_slot_for_name(owner_decl_node, token) != INVALID)
            return false;
        uint name_id = name_id_by_token[token];
        if (language_type_exists_by_name(name_id))
            return false;
    }

    uint decl_i = type_decl_for_bound_path(expr_node, owner_decl_node);
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return false;

    uint decl_node = decl_hir_node[decl_i];
    uint expected_arg_count = valid_node(decl_node)
        ? type_decl_generic_param_count_by_node[decl_node]
        : 0u;
    return expected_arg_count > 0u;
}

uint predicate_bound_arg_record_value(uint owner_decl_node, uint arg_node)
{
    uint kind = node_kind[arg_node];
    uint token = kind == PROD_BOUND_TYPE_IDENT
        ? bound_path_leaf_token(arg_node)
        : hir_token_pos[arg_node];
    if (!valid_token(token))
        return INVALID;

    if (kind == PROD_BOUND_TYPE_IDENT &&
        bound_path_segment_count(arg_node) == 1u &&
        generic_param_slot_for_name(owner_decl_node, token) == INVALID)
    {
        uint name_id = name_id_by_token[token];
        uint type_code = name_id != INVALID ? language_type_code_by_name_id[name_id] : 0u;
        if (type_code != 0u)
            return PREDICATE_ARG_TYPE_CODE_BIT | type_code;
    }

    return token;
}

uint predicate_bound_arg_node(uint predicate_expr_node, uint ordinal)
{
    if (ordinal == 0u)
        return predicate_bound_first_arg_token[predicate_expr_node];
    if (ordinal == 1u)
        return predicate_bound_second_arg_token[predicate_expr_node];
    return INVALID;
}

uint predicate_bound_arg_fact_status_value(uint predicate_expr_node)
{
    uint status = predicate_status[predicate_expr_node];
    return status == INVALID ? PREDICATE_STATUS_OK : status;
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

    arg_count = valid_node(predicate_expr_node)
        ? predicate_bound_arg_count[predicate_expr_node]
        : 0u;

    uint fact_status = valid_node(predicate_expr_node)
        ? predicate_bound_arg_fact_status_value(predicate_expr_node)
        : PREDICATE_STATUS_OK;
    if (fact_status != PREDICATE_STATUS_OK)
        return fact_status;

    if (arg_count == 0u && bound_ident_has_direct_arg_list(predicate_expr_node))
        return PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;

    if (arg_count > 2u)
        return PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH;

    [loop]
    for (uint ordinal = 0u; ordinal < 2u; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;

        uint node = predicate_bound_arg_node(predicate_expr_node, ordinal);
        if (!valid_node(node) || node_kind[node] != PROD_BOUND_TYPE_IDENT)
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        if (!bound_path_scan_supported(node))
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        if (bound_arg_requires_instance_args(owner_decl_node, node))
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        if (!valid_bound_type_arg(owner_decl_node, node))
            return PREDICATE_STATUS_INVALID_ARG;

        uint token = predicate_bound_arg_record_value(owner_decl_node, node);
        if (ordinal == 0u)
            first_arg_token = token;
        else
            second_arg_token = token;
    }

    return PREDICATE_STATUS_OK;
}

void clear_predicate_record(uint node)
{
    predicate_owner_node[node] = INVALID;
    predicate_subject_token[node] = INVALID;
    predicate_bound_token[node] = INVALID;
    predicate_bound_decl_id[node] = INVALID;
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

    if (node_kind[node] == PROD_IMPL_INHERENT)
    {
        validate_inherent_impl_header_node(node);
        return;
    }

    if (trait_method_node(node))
    {
        validate_trait_method_contract_node(node);
        return;
    }

    bool predicate_ancestor_exhausted = false;
    uint list_node = INVALID;
    if (node_kind[node] == PROD_BOUND_TYPE_IDENT || node_kind[node] == PROD_BOUND_TYPE_REF)
    {
        list_node = predicate_list_ancestor(node, predicate_ancestor_exhausted);
        if (!valid_node(list_node) && predicate_ancestor_exhausted)
        {
            uint diagnostic_token = node_kind[node] == PROD_BOUND_TYPE_IDENT
                ? bound_path_leaf_token(node)
                : hir_token_pos[node];
            predicate_owner_node[node] = node;
            predicate_bound_token[node] = valid_token(diagnostic_token)
                ? diagnostic_token
                : hir_token_pos[node];
            predicate_bound_first_arg_token[node] = predicate_bound_token[node];
            predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
            return;
        }
    }

    if (!valid_node(list_node))
        return;

    uint owner_decl = generic_decl_owner_for_node(node);
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

    if (!callable_generic_decl_item_kind(hir_item_kind[owner_decl]))
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND;
        return;
    }

    if (node_kind[node] != PROD_BOUND_TYPE_IDENT)
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED;
        return;
    }
    if (!bound_path_scan_supported(node))
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
        return;
    }
    if (bound_path_segment_count(node) == 0u)
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED;
        return;
    }

    uint trait_decl_i = type_decl_for_bound_path(node, owner_decl);
    if (!valid_token(bound_token) ||
        trait_decl_i == INVALID ||
        decl_kind[trait_decl_i] != HIR_ITEM_KIND_TRAIT ||
        decl_namespace[trait_decl_i] != HIR_ITEM_NAMESPACE_TYPE)
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }
    predicate_bound_decl_id[node] = trait_decl_i;

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
    if (arg_status != PREDICATE_STATUS_OK)
    {
        predicate_status[node] = arg_status;
        return;
    }

    uint trait_param_count = trait_decl_generic_param_count(trait_decl_i);
    predicate_status[node] = trait_param_count != INVALID && arg_count == trait_param_count
        ? PREDICATE_STATUS_OK
        : PREDICATE_STATUS_BOUND_ARITY_MISMATCH;
}
