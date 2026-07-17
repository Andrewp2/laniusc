// HIR predicate record collection shared by generic bounds, where clauses, and
// trait/inherent impl headers.
//
// This pass consumes parser-owned predicate parse nodes, generic-parameter
// declaration records, interned name ids, language type records, and module
// declaration records. It publishes node-keyed predicate records for each
// top-level bound expression, trait impl header, and unsupported trait-method
// contract shape so later validation can reject bad predicates without treating
// bounds or impls as comments.

import generated_parse_production_ids;
import fixed.key;
import range_query;

#define PREDICATE_COLLECT_METHOD_RECORDS 0
#ifndef PREDICATE_COLLECT_IMPL_RECORDS
#define PREDICATE_COLLECT_IMPL_RECORDS 0
#endif
#ifndef PREDICATE_BOUND_DECL_RESOLUTION
#define PREDICATE_BOUND_DECL_RESOLUTION 1
#endif
#ifndef PREDICATE_BOUND_ARGUMENT_VALIDATION
#define PREDICATE_BOUND_ARGUMENT_VALIDATION 1
#endif
#define PREDICATE_BOUND_PATH_RESOLUTION \
    (PREDICATE_BOUND_DECL_RESOLUTION || PREDICATE_BOUND_ARGUMENT_VALIDATION)

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

#if PREDICATE_BOUND_PATH_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
#endif

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
#if PREDICATE_BOUND_PATH_RESOLUTION
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> subtree_end;
#endif
StructuredBuffer<uint> hir_token_pos;
#if PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> hir_type_path_leaf_node;
#endif
#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> hir_type_arg_start;
StructuredBuffer<uint> hir_type_arg_count;
#endif
#if PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> hir_type_arg_next;
#endif
#if PREDICATE_BOUND_DECL_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> hir_item_kind;
#endif
StructuredBuffer<uint> hir_item_name_token;
#if PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> hir_item_visibility;
StructuredBuffer<uint> hir_method_impl_receiver_type_node;
StructuredBuffer<uint> predicate_trait_impl_trait_type_node;
#endif
StructuredBuffer<uint> name_id_by_token;
#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_generic_param_slot_by_token;
#endif
#if PREDICATE_BOUND_DECL_RESOLUTION
StructuredBuffer<uint> generic_decl_owner_by_node;
StructuredBuffer<uint> predicate_bound_list_by_node;
#endif
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> generic_param_token;
#endif
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_key_order;
#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> language_type_code_by_name_id;
#endif
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> decl_hir_node;
#endif
StructuredBuffer<uint> decl_visibility;
#if PREDICATE_BOUND_PATH_RESOLUTION
StructuredBuffer<uint> module_table_count_out;
StructuredBuffer<uint> sorted_module_key_order;
StructuredBuffer<uint> module_key_canonical_id;
StructuredBuffer<uint> decl_type_key_count_out;
StructuredBuffer<uint> decl_type_key_to_decl_id;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_prefix_id;
#endif
#if PREDICATE_BOUND_PATH_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_id_by_owner_hir;
#endif
#if PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> resolved_type_status;
#endif
#if PREDICATE_BOUND_PATH_RESOLUTION
StructuredBuffer<uint> import_visible_type_count_out;
StructuredBuffer<uint> import_visible_type_key_module_id;
StructuredBuffer<uint> import_visible_type_key_name_id;
StructuredBuffer<uint> import_visible_type_key_to_decl_id;
StructuredBuffer<uint> import_visible_type_status;
#endif

RWStructuredBuffer<uint> predicate_owner_node;
#if PREDICATE_BOUND_DECL_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
RWStructuredBuffer<uint> predicate_subject_token;
RWStructuredBuffer<uint> predicate_bound_token;
#endif
RWStructuredBuffer<uint> predicate_bound_decl_id;
RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;
#if PREDICATE_BOUND_DECL_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
RWStructuredBuffer<uint> predicate_syntax_token;
#endif
#if PREDICATE_COLLECT_METHOD_RECORDS
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
#endif

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PREDICATE_ARG_TYPE_CODE_BIT = 0x80000000u;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;

static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

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
static const uint PREDICATE_STATUS_EXTRA_IMPL_METHOD = 23u;
static const uint PREDICATE_STATUS_DUPLICATE_IMPL_METHOD = 24u;
static const uint PREDICATE_STATUS_IMPL_VISIBILITY_MISMATCH = 25u;
static const uint PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH = 26u;
static const uint PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG = 28u;
static const uint PREDICATE_STATUS_IMPL_TARGET_PATH_MISSING = 29u;
static const uint PREDICATE_STATUS_IMPL_TARGET_DECL_MISSING = 30u;
static const uint PREDICATE_STATUS_IMPL_TARGET_DECL_KIND = 31u;
static const uint PREDICATE_STATUS_IMPL_TARGET_DECL_IDENTITY = 32u;
static const uint PREDICATE_STATUS_IMPL_TARGET_ARITY = 33u;
static const uint PREDICATE_STATUS_IMPL_TARGET_ARG_SHAPE = 34u;
static const uint IMPORT_VISIBLE_STATUS_OK = 0u;

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

uint source_file_count()
{
    return max(gParams.n_source_files, 1u);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint parent_node(uint node)
{
    return valid_node(node) ? parent[node] : INVALID;
}

#if PREDICATE_BOUND_PATH_RESOLUTION
uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) && parent_node(child) == node && child > node
        ? child
        : INVALID;
}

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    uint owner = parent_node(node);
    return valid_node(owner) &&
           valid_node(sibling) &&
           parent_node(sibling) == owner &&
           sibling > node
        ? sibling
        : INVALID;
}
#endif

#if PREDICATE_BOUND_DECL_RESOLUTION
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
#endif

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.n_tokens);
}

uint generic_owner_token_for_decl(uint decl_node)
{
    if (!valid_node(decl_node))
        return INVALID;
    uint name_token = hir_item_name_token[decl_node];
    return valid_token(name_token) ? name_token : hir_token_pos[decl_node];
}

#if PREDICATE_BOUND_PATH_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_compact_hir(uint hir)
{
    return hir != INVALID && hir < active_compact_hir_count();
}
#endif

#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
uint generic_type_param_count_for_raw_decl(uint decl_node)
{
    uint owner_token = generic_owner_token_for_decl(decl_node);
    return valid_token(owner_token)
        ? type_decl_generic_param_count_by_owner_token[owner_token]
        : 0u;
}

uint compact_decl_name_token(uint hir)
{
    if (!valid_compact_hir(hir))
        return INVALID;
    uint token = compact_hir_payload[hir].b;
    return valid_token(token) ? token : compact_hir_core[hir].token_start;
}

uint generic_type_param_count_for_compact_decl(uint hir)
{
    uint owner_token = compact_decl_name_token(hir);
    return valid_token(owner_token)
        ? type_decl_generic_param_count_by_owner_token[owner_token]
        : 0u;
}
#endif

public struct GenericParamLookupKey
{
    uint owner;
    uint name_id;
}

int compare_generic_param_key(uint row, GenericParamLookupKey key)
{
    if (row >= active_generic_param_count())
        return 1;

    int owner_cmp = fixed_u32_lane_compare(generic_param_owner_token[row], key.owner);
    if (owner_cmp != 0)
        return owner_cmp;
    return fixed_u32_lane_compare(generic_param_name_id[row], key.name_id);
}

public struct GenericParamKeyCompare : IRowQueryCompare<GenericParamLookupKey>
{
    public static int compare(uint row, GenericParamLookupKey key)
    {
        if (row >= active_generic_param_count())
            return 1;
        return compare_generic_param_key(generic_param_key_order[row], key);
    }
}

bool generic_param_key_matches(uint row, uint owner, uint name_id, uint kind)
{
    return row < active_generic_param_count() &&
           generic_param_owner_token[row] == owner &&
           generic_param_name_id[row] == name_id &&
           generic_param_kind[row] == kind;
}

bool generic_param_key_less(uint row, uint owner, uint name_id)
{
    if (row >= active_generic_param_count())
        return false;

    uint row_owner = generic_param_owner_token[row];
    if (row_owner != owner)
        return row_owner < owner;
    return generic_param_name_id[row] < name_id;
}

uint generic_param_row_for_name(uint decl_node, uint name_token, uint kind)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint owner_token = generic_owner_token_for_decl(decl_node);
    if (!valid_token(owner_token))
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint count = active_generic_param_count();
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint row = generic_param_key_order[mid];
        if (row >= count || !generic_param_key_less(row, owner_token, name_id))
            hi = mid;
        else
            lo = mid + 1u;
    }

    if (lo >= count)
        return INVALID;

    uint row = generic_param_key_order[lo];
    return generic_param_key_matches(row, owner_token, name_id, kind) ? row : INVALID;
}

bool generic_type_param_declared_on(uint decl_node, uint name_token)
{
    return generic_param_row_for_name(decl_node, name_token, GENERIC_PARAM_KIND_TYPE) != INVALID;
}

#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
uint generic_param_slot_for_name(uint decl_node, uint name_token)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint count = generic_type_param_count_for_raw_decl(decl_node);
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
#endif

#if PREDICATE_BOUND_DECL_RESOLUTION
uint predicate_list_for_direct_bound(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint parent0 = parent_node(node);
    if (!valid_node(parent0))
        return INVALID;

    uint kind0 = node_kind[parent0];
    if (kind0 == PROD_TYPE_PARAM_BOUND_LIST)
        return parent0;
    if (kind0 != PROD_TYPE_PARAM_BOUND_MORE)
        return INVALID;

    uint direct_list = parent_node(parent0);
    if (valid_node(direct_list) && node_kind[direct_list] == PROD_TYPE_PARAM_BOUND_LIST)
        return direct_list;

    uint list_node = predicate_bound_list_by_node[node];
    if (!valid_node(list_node) || node_kind[list_node] != PROD_TYPE_PARAM_BOUND_LIST)
        return INVALID;

    uint owner = parent_node(list_node);
    if (valid_node(owner) && node_kind[owner] == PROD_TYPE_PARAM_BOUND)
        return INVALID;

    return list_node;
}

bool unsupported_direct_bound_list_relation(uint node)
{
    if (!valid_node(node))
        return false;

    uint parent0 = parent_node(node);
    if (!valid_node(parent0) || node_kind[parent0] != PROD_TYPE_PARAM_BOUND_MORE)
        return false;

    uint parent1 = parent_node(parent0);
    if (!valid_node(parent1) || node_kind[parent1] != PROD_TYPE_PARAM_BOUND_MORE)
        return false;

    uint list_node = predicate_bound_list_by_node[node];
    uint owner = valid_node(list_node) && node_kind[list_node] == PROD_TYPE_PARAM_BOUND_LIST
        ? parent_node(list_node)
        : INVALID;
    return valid_node(owner) && node_kind[owner] == PROD_TYPE_PARAM_BOUND;
}

bool direct_type_param_bound_list(uint list_node)
{
    if (!valid_node(list_node))
        return false;

    uint owner = parent_node(list_node);
    return valid_node(owner) && node_kind[owner] == PROD_TYPE_PARAM_BOUND;
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
#endif

uint decl_record_count()
{
    return min(decl_count_out[0], gParams.n_hir_nodes);
}

#if PREDICATE_BOUND_PATH_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
uint path_record_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}
#endif

#if PREDICATE_BOUND_PATH_RESOLUTION
uint module_record_count()
{
    return min(module_table_count_out[0], gParams.n_hir_nodes);
}

uint type_decl_key_record_count()
{
    return min(decl_type_key_count_out[0], gParams.n_hir_nodes);
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

bool bound_ident_has_direct_arg_list(uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return false;

    uint child = first_child_node(expr_node);
    // A bound identifier has a grammar-fixed path/argument child shape. Probe
    // the bounded local shape and fail closed instead of walking an arbitrary
    // sibling list.
    for (uint step = 0u; step < 3u; step += 1u)
    {
        if (!valid_node(child))
            return false;
        uint kind = node_kind[child];
        if (kind == PROD_BOUND_TYPE_ARGS_SOME)
            return true;
        if (kind == PROD_BOUND_TYPE_ARGS_NONE)
            return false;
        child = next_sibling_node(child);
    }
    return false;
}

bool bound_path_container(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_BOUND_TYPE_PATH ||
           kind == PROD_BOUND_TYPE_PATH_MORE ||
           kind == PROD_PATH_MORE;
}

bool bound_path_segment_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_BOUND_TYPE_PATH_IDENT ||
           kind == PROD_PATH_IDENT ||
           kind == PROD_PATH_IDENT_ARGS;
}

bool bound_path_tail_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_BOUND_TYPE_PATH_MORE || kind == PROD_PATH_MORE;
}

uint bound_path_record_id(uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return INVALID;
    uint owner = raw_to_compact_hir[expr_node];
    uint path_i = valid_compact_hir(owner) ? path_id_by_owner_hir[owner] : INVALID;
    return path_i < path_record_count() ? path_i : INVALID;
}

bool bound_path_shape_supported(uint expr_node)
{
    uint path_i = bound_path_record_id(expr_node);
    if (path_i == INVALID)
        return false;
    uint base = path_segment_base[path_i];
    uint count = path_segment_count[path_i];
    return count != 0u && base <= gParams.n_tokens && count <= gParams.n_tokens - base;
}

uint bound_path_segment_token(uint expr_node, uint segment_i)
{
    uint path_i = bound_path_record_id(expr_node);
    if (path_i == INVALID || segment_i >= path_segment_count[path_i])
        return INVALID;
    uint slot = path_segment_base[path_i] + segment_i;
    return slot < gParams.n_tokens ? path_segment_token[slot] : INVALID;
}

uint bound_path_segment_name_id(uint expr_node, uint segment_i)
{
    uint path_i = bound_path_record_id(expr_node);
    if (path_i == INVALID || segment_i >= path_segment_count[path_i])
        return INVALID;
    uint slot = path_segment_base[path_i] + segment_i;
    return slot < gParams.n_tokens ? path_segment_name_id[slot] : INVALID;
}

uint bound_path_segment_count(uint expr_node)
{
    uint path_i = bound_path_record_id(expr_node);
    return path_i == INVALID ? 0u : path_segment_count[path_i];
}

uint bound_path_leaf_token(uint expr_node)
{
    uint segment_count = bound_path_segment_count(expr_node);
    if (segment_count == 0u)
        return INVALID;

    return bound_path_segment_token(expr_node, segment_count - 1u);
}

public struct BoundModulePrefixLookupKey
{
    uint canonical_id;
}

public struct BoundModulePrefixCompare : IRowQueryCompare<BoundModulePrefixLookupKey>
{
    public static int compare(uint row, BoundModulePrefixLookupKey key)
    {
        uint module_i = sorted_module_key_order[row];
        uint row_id = module_key_canonical_id[module_i];
        return row_id < key.canonical_id ? -1 : (row_id > key.canonical_id ? 1 : 0);
    }
}

uint find_module_for_bound_path_prefix(uint expr_node, uint prefix_count)
{
    uint path_i = bound_path_record_id(expr_node);
    if (path_i == INVALID || prefix_count == 0u ||
        prefix_count >= path_segment_count[path_i])
        return INVALID;

    BoundModulePrefixLookupKey key;
    key.canonical_id = path_prefix_id[path_segment_base[path_i] + prefix_count - 1u];
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
#endif

#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
uint trait_decl_generic_param_count(uint decl_i)
{
    if (decl_i >= decl_record_count())
        return INVALID;

    uint trait_node = decl_hir_node[decl_i];
    return valid_compact_hir(trait_node)
        ? generic_type_param_count_for_compact_decl(trait_node)
        : INVALID;
}

bool language_type_exists_by_name(uint name_id)
{
    if (name_id == INVALID)
        return false;
    return language_type_code_by_name_id[name_id] != 0u;
}
#endif

#if PREDICATE_COLLECT_IMPL_RECORDS
uint type_path_record_id(uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_TYPE_IDENT)
        return INVALID;

    uint owner = raw_to_compact_hir[expr_node];
    uint path_i = valid_compact_hir(owner) ? path_id_by_owner_hir[owner] : INVALID;
    return path_i != INVALID && path_i < path_record_count() ? path_i : INVALID;
}

bool type_path_scan_supported(uint expr_node)
{
    uint path_i = type_path_record_id(expr_node);
    if (path_i != INVALID)
    {
        uint count = path_segment_count[path_i];
        return count != 0u && path_segment_base[path_i] + count <= gParams.n_tokens;
    }

    uint token = valid_node(expr_node) && node_kind[expr_node] == PROD_TYPE_IDENT
        ? hir_token_pos[expr_node]
        : INVALID;
    return valid_token(token) && name_id_by_token[token] != INVALID;
}

uint type_path_segment_count(uint expr_node)
{
    uint path_i = type_path_record_id(expr_node);
    if (path_i == INVALID)
    {
        uint token = valid_node(expr_node) && node_kind[expr_node] == PROD_TYPE_IDENT
            ? hir_token_pos[expr_node]
            : INVALID;
        return valid_token(token) && name_id_by_token[token] != INVALID ? 1u : 0u;
    }

    uint count = path_segment_count[path_i];
    return path_segment_base[path_i] + count <= gParams.n_tokens ? count : 0u;
}

uint type_path_segment_token(uint expr_node, uint segment_i)
{
    uint path_i = type_path_record_id(expr_node);
    uint count = path_i != INVALID ? path_segment_count[path_i] : 0u;
    if (path_i == INVALID)
    {
        uint token = valid_node(expr_node) && node_kind[expr_node] == PROD_TYPE_IDENT
            ? hir_token_pos[expr_node]
            : INVALID;
        return segment_i == 0u && valid_token(token) && name_id_by_token[token] != INVALID
            ? token
            : INVALID;
    }

    if (path_segment_base[path_i] + count > gParams.n_tokens || segment_i >= count)
        return INVALID;

    uint slot = path_segment_base[path_i] + segment_i;
    return slot < gParams.n_tokens ? path_segment_token[slot] : INVALID;
}

uint type_path_leaf_token(uint expr_node)
{
    uint segment_count = type_path_segment_count(expr_node);
    return segment_count == 0u ? INVALID : type_path_segment_token(expr_node, segment_count - 1u);
}

uint type_decl_for_type_path(uint expr_node)
{
    uint path_i = type_path_record_id(expr_node);
    if (path_i == INVALID || resolved_type_status[path_i] != 0u)
        return INVALID;
    uint decl_i = resolved_type_decl[path_i];
    return decl_i < decl_record_count() ? decl_i : INVALID;
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
    if (decl_kind[decl_i] == HIR_ITEM_KIND_TYPE_ALIAS)
        return PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;

    uint decl_node = decl_hir_node[decl_i];
    uint expected_arg_count = valid_compact_hir(decl_node)
        ? generic_type_param_count_for_compact_decl(decl_node)
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
#endif

#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
bool supported_predicate_type_arg_decl(uint decl_i)
{
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return false;
    if (decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_TYPE)
        return false;

    uint kind = decl_kind[decl_i];
    if (kind == HIR_ITEM_KIND_STRUCT || kind == HIR_ITEM_KIND_ENUM)
        return true;

    if (kind != HIR_ITEM_KIND_TYPE_ALIAS)
        return false;

    uint decl_node = decl_hir_node[decl_i];
    uint name_token = compact_decl_name_token(decl_node);
    return valid_token(name_token) &&
           type_expr_ref_tag[name_token] == TYPE_REF_SCALAR &&
           type_expr_ref_payload[name_token] != 0u;
}

uint alias_type_code_for_decl(uint decl_i)
{
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return 0u;
    if (decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_TYPE ||
        decl_kind[decl_i] != HIR_ITEM_KIND_TYPE_ALIAS)
        return 0u;

    uint decl_node = decl_hir_node[decl_i];
    uint name_token = compact_decl_name_token(decl_node);
    if (!valid_token(name_token) || type_expr_ref_tag[name_token] != TYPE_REF_SCALAR)
        return 0u;

    return type_expr_ref_payload[name_token];
}

uint nominal_type_code_for_decl(uint decl_i)
{
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return 0u;
    if (decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_TYPE)
        return 0u;

    uint name_token = decl_name_id[decl_i] != INVALID && valid_compact_hir(decl_hir_node[decl_i])
        ? compact_decl_name_token(decl_hir_node[decl_i])
        : INVALID;
    if (!valid_token(name_token))
        return 0u;

    uint kind = decl_kind[decl_i];
    if (kind == HIR_ITEM_KIND_STRUCT)
        return TY_STRUCT_BASE + name_token;
    if (kind == HIR_ITEM_KIND_ENUM)
        return TY_ENUM_BASE + name_token;
    if (kind == HIR_ITEM_KIND_TYPE_ALIAS)
        return alias_type_code_for_decl(decl_i);
    return 0u;
}

uint encoded_type_code(uint type_code)
{
    return type_code == 0u ? INVALID : (PREDICATE_ARG_TYPE_CODE_BIT | type_code);
}

uint encoded_language_type_arg_for_token(uint token)
{
    if (!valid_token(token))
        return INVALID;
    uint name_id = name_id_by_token[token];
    uint type_code = name_id != INVALID ? language_type_code_by_name_id[name_id] : 0u;
    return encoded_type_code(type_code);
}

#if PREDICATE_BOUND_ARGUMENT_VALIDATION
uint encoded_alias_type_arg_for_bound(uint owner_decl_node, uint arg_node)
{
    uint decl_i = type_decl_for_bound_path(arg_node, owner_decl_node);
    return encoded_type_code(alias_type_code_for_decl(decl_i));
}
#endif

#if PREDICATE_COLLECT_IMPL_RECORDS
uint encoded_alias_type_arg_for_type_node(uint arg_node)
{
    uint decl_i = type_decl_for_type_path(arg_node);
    return encoded_type_code(alias_type_code_for_decl(decl_i));
}

uint encoded_alias_type_arg_for_type_token(uint owner_type_node, uint token)
{
    uint decl_i = type_decl_for_type_arg_token(token);
    return encoded_type_code(alias_type_code_for_decl(decl_i));
}
#endif

#if PREDICATE_BOUND_ARGUMENT_VALIDATION
uint encoded_concrete_type_arg_for_bound(uint owner_decl_node, uint arg_node)
{
    uint encoded_language = encoded_language_type_arg_for_token(bound_path_leaf_token(arg_node));
    if (encoded_language != INVALID)
        return encoded_language;

    uint decl_i = type_decl_for_bound_path(arg_node, owner_decl_node);
    return encoded_type_code(nominal_type_code_for_decl(decl_i));
}
#endif
#endif

#if PREDICATE_COLLECT_IMPL_RECORDS
uint encoded_concrete_type_arg_for_type_node(uint arg_node)
{
    uint encoded_language = encoded_language_type_arg_for_token(type_path_leaf_token(arg_node));
    if (encoded_language != INVALID)
        return encoded_language;

    uint decl_i = type_decl_for_type_path(arg_node);
    return encoded_type_code(nominal_type_code_for_decl(decl_i));
}

uint encoded_concrete_type_arg_for_type_token(uint owner_type_node, uint token)
{
    uint encoded_language = encoded_language_type_arg_for_token(token);
    if (encoded_language != INVALID)
        return encoded_language;

    uint decl_i = type_decl_for_type_arg_token(token);
    return encoded_type_code(nominal_type_code_for_decl(decl_i));
}

bool trait_impl_type_arg_shape_supported(uint arg_node)
{
    if (!type_path_scan_supported(arg_node))
        return false;

    uint segment_count = type_path_segment_count(arg_node);
    if (segment_count == 0u)
        return true;

    uint leaf_token = type_path_leaf_token(arg_node);
    uint leaf_name_id = valid_token(leaf_token) ? name_id_by_token[leaf_token] : INVALID;
    if (segment_count == 1u && language_type_exists_by_name(leaf_name_id))
        return true;

    uint decl_i = type_decl_for_type_path(arg_node);
    return decl_i == INVALID || supported_predicate_type_arg_decl(decl_i);
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
    uint expected_arg_count = valid_compact_hir(decl_node)
        ? generic_type_param_count_for_compact_decl(decl_node)
        : 0u;
    return expected_arg_count > 0u && direct_type_arg_count(arg_node) == 0u;
}

uint direct_type_arg_scalar_token(uint owner_type_node, uint ordinal)
{
    if (!valid_node(owner_type_node))
        return INVALID;

    uint leaf = hir_type_path_leaf_node[owner_type_node];
    uint leaf_token = valid_node(leaf) ? hir_token_pos[leaf] : INVALID;
    if (!valid_token(leaf_token))
        return INVALID;
    uint max_token_before_arg_offset = 0xffffffffu - 2u;
    if (leaf_token > max_token_before_arg_offset ||
        ordinal > (max_token_before_arg_offset - leaf_token) / 2u)
        return INVALID;

    uint token = leaf_token + 2u + ordinal * 2u;
    return valid_token(token) &&
           name_id_by_token[token] != INVALID
        ? token
        : INVALID;
}

uint type_decl_for_type_arg_token(uint token)
{
    if (!valid_token(token))
        return INVALID;

    uint path_i = path_id_by_owner_token[token];
    if (path_i == INVALID || path_i >= path_record_count() || resolved_type_status[path_i] != 0u)
        return INVALID;

    uint decl_i = resolved_type_decl[path_i];
    return decl_i < decl_record_count() ? decl_i : INVALID;
}

bool trait_impl_type_arg_token_requires_instance_args(uint owner_type_node, uint token)
{
    if (!valid_token(token))
        return false;

    uint name_id = name_id_by_token[token];
    if (language_type_exists_by_name(name_id))
        return false;

    uint decl_i = type_decl_for_type_arg_token(token);
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return false;

    uint decl_node = decl_hir_node[decl_i];
    uint expected_arg_count = valid_compact_hir(decl_node)
        ? generic_type_param_count_for_compact_decl(decl_node)
        : 0u;
    return expected_arg_count > 0u;
}

bool trait_impl_type_arg_token_resolves(uint owner_type_node, uint token)
{
    if (!valid_token(token))
        return false;

    uint name_id = name_id_by_token[token];
    if (language_type_exists_by_name(name_id))
        return true;

    return type_decl_for_type_arg_token(token) != INVALID;
}

bool trait_impl_type_arg_token_shape_supported(uint owner_type_node, uint token)
{
    if (!valid_token(token))
        return true;

    uint name_id = name_id_by_token[token];
    if (language_type_exists_by_name(name_id))
        return true;

    uint decl_i = type_decl_for_type_arg_token(token);
    return decl_i == INVALID || supported_predicate_type_arg_decl(decl_i);
}

bool trait_impl_type_arg_token_is_header_generic(uint impl_node, uint token)
{
    return valid_node(impl_node) &&
           valid_token(token) &&
           (generic_type_param_declared_on(impl_node, token) ||
            generic_param_slot_for_name(impl_node, token) != INVALID ||
            type_generic_param_slot_by_token[token] != INVALID);
}

bool trait_impl_type_arg_is_header_generic(uint impl_node, uint arg_node)
{
    if (!valid_node(arg_node) ||
        node_kind[arg_node] != PROD_TYPE_IDENT ||
        direct_type_arg_count(arg_node) != 0u ||
        type_path_segment_count(arg_node) != 1u)
        return false;

    return trait_impl_type_arg_token_is_header_generic(
        impl_node,
        type_path_leaf_token(arg_node));
}

uint validate_trait_impl_scalar_arg_token(
    uint impl_node,
    uint trait_type_node,
    uint ordinal,
    out uint token)
{
    token = direct_type_arg_scalar_token(trait_type_node, ordinal);
    if (!valid_token(token))
        return PREDICATE_STATUS_INVALID_IMPL_ARG;
    if (trait_impl_type_arg_token_is_header_generic(impl_node, token))
        return PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG;
    if (!trait_impl_type_arg_token_shape_supported(trait_type_node, token))
        return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
    if (trait_impl_type_arg_token_requires_instance_args(trait_type_node, token))
        return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
    if (!trait_impl_type_arg_token_resolves(trait_type_node, token))
        return PREDICATE_STATUS_INVALID_IMPL_ARG;

    uint encoded_concrete = encoded_concrete_type_arg_for_type_token(trait_type_node, token);
    if (encoded_concrete != INVALID)
        token = encoded_concrete;
    return PREDICATE_STATUS_OK;
}
#endif

#if PREDICATE_COLLECT_METHOD_RECORDS
bool trait_method_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_TRAIT_METHOD || kind == PROD_TRAIT_METHOD_PUB;
}

bool impl_method_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_IMPL_FN;
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
#endif

#if PREDICATE_COLLECT_IMPL_RECORDS
uint direct_type_arg_count(uint owner_type_node)
{
    if (!valid_node(owner_type_node))
        return 0u;

    return hir_type_arg_count[owner_type_node];
}

uint direct_type_arg_node(uint owner_type_node, uint ordinal)
{
    if (!valid_node(owner_type_node))
        return INVALID;

    uint count = direct_type_arg_count(owner_type_node);
    if (ordinal >= count || ordinal >= 2u)
        return INVALID;

    uint node = hir_type_arg_start[owner_type_node];
    if (!valid_node(node) || ordinal == 0u)
        return valid_node(node) ? node : INVALID;

    uint next_node = hir_type_arg_next[node];
    return valid_node(next_node) && next_node > node ? next_node : INVALID;
}

bool inherent_impl_target_arg_supported(uint impl_node, uint arg_node)
{
    if (!valid_node(arg_node))
        return false;

    uint source_token = hir_token_pos[arg_node];
    if (trait_impl_type_arg_token_is_header_generic(impl_node, source_token))
        return true;

    if (node_kind[arg_node] != PROD_TYPE_IDENT)
        return false;
    if (!type_path_scan_supported(arg_node))
        return false;
    if (direct_type_arg_count(arg_node) != 0u)
        return false;

    uint token = type_path_leaf_token(arg_node);
    if (!valid_token(token))
        token = source_token;
    if (type_path_segment_count(arg_node) == 1u &&
        valid_token(token) &&
        (generic_param_slot_for_name(impl_node, token) != INVALID ||
         type_generic_param_slot_by_token[token] != INVALID))
        return true;

    if (!trait_impl_type_arg_shape_supported(arg_node))
        return false;
    if (type_arg_requires_instance_args(arg_node))
        return false;
    return trait_impl_type_arg_resolves(arg_node);
}

bool inherent_impl_target_arg_token_supported(uint impl_node, uint owner_type_node, uint ordinal)
{
    uint token = direct_type_arg_scalar_token(owner_type_node, ordinal);
    if (!valid_token(token))
        return false;

    if (trait_impl_type_arg_token_is_header_generic(impl_node, token) ||
        type_generic_param_slot_by_token[token] != INVALID)
        return true;
    if (!trait_impl_type_arg_token_shape_supported(owner_type_node, token))
        return false;
    if (trait_impl_type_arg_token_requires_instance_args(owner_type_node, token))
        return false;
    return trait_impl_type_arg_token_resolves(owner_type_node, token);
}

bool inherent_impl_target_args_supported(uint impl_node, uint expr_node, uint arg_count)
{
    uint arg_node = valid_node(expr_node) ? hir_type_arg_start[expr_node] : INVALID;

    for (uint ordinal = 0u; ordinal < arg_count; ordinal += 1u)
    {
        bool supported = valid_node(arg_node)
            ? inherent_impl_target_arg_supported(impl_node, arg_node)
            : inherent_impl_target_arg_token_supported(impl_node, expr_node, ordinal);
        if (!supported)
            return false;

        if (valid_node(arg_node))
        {
            uint next_node = hir_type_arg_next[arg_node];
            if (ordinal + 1u < arg_count &&
                (!valid_node(next_node) || next_node <= arg_node))
                return false;
            arg_node = next_node;
        }
    }
    return true;
}

void mark_direct_type_arg_syntax_tokens(uint expr_node, uint arg_count)
{
    uint arg_node = valid_node(expr_node) ? hir_type_arg_start[expr_node] : INVALID;

    for (uint ordinal = 0u; ordinal < arg_count; ordinal += 1u)
    {
        uint token = valid_node(arg_node) ? type_path_leaf_token(arg_node) : INVALID;
        if (!valid_token(token) && valid_node(arg_node))
            token = hir_token_pos[arg_node];
        if (!valid_token(token))
            token = direct_type_arg_scalar_token(expr_node, ordinal);
        mark_predicate_syntax_token(token);

        if (valid_node(arg_node))
        {
            uint next_node = hir_type_arg_next[arg_node];
            if (ordinal + 1u < arg_count &&
                (!valid_node(next_node) || next_node <= arg_node))
                return;
            arg_node = next_node;
        }
    }
}

uint validate_inherent_impl_target_type(uint impl_node, uint expr_node)
{
    if (!type_path_scan_supported(expr_node))
        return PREDICATE_STATUS_IMPL_TARGET_PATH_MISSING;

    uint segment_count = type_path_segment_count(expr_node);
    if (segment_count == 0u)
        return PREDICATE_STATUS_IMPL_TARGET_PATH_MISSING;

    uint leaf_token = type_path_leaf_token(expr_node);
    uint leaf_name_id = valid_token(leaf_token) ? name_id_by_token[leaf_token] : INVALID;
    uint arg_count = direct_type_arg_count(expr_node);
    if (segment_count == 1u && language_type_exists_by_name(leaf_name_id))
        return arg_count == 0u
            ? PREDICATE_STATUS_OK
            : PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;

    uint decl_i = type_decl_for_type_path(expr_node);
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return PREDICATE_STATUS_IMPL_TARGET_DECL_MISSING;
    if (!supported_predicate_type_arg_decl(decl_i))
        return PREDICATE_STATUS_IMPL_TARGET_DECL_KIND;

    uint decl_node = decl_hir_node[decl_i];
    uint expected_arg_count = valid_compact_hir(decl_node)
        ? generic_type_param_count_for_compact_decl(decl_node)
        : INVALID;
    if (expected_arg_count == INVALID)
        return PREDICATE_STATUS_IMPL_TARGET_DECL_IDENTITY;
    if (expected_arg_count != arg_count)
        return PREDICATE_STATUS_IMPL_TARGET_ARITY;
    if (!inherent_impl_target_args_supported(impl_node, expr_node, arg_count))
        return PREDICATE_STATUS_IMPL_TARGET_ARG_SHAPE;

    return PREDICATE_STATUS_OK;
}

#if PREDICATE_COLLECT_METHOD_RECORDS
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
#endif

bool trait_impl_header_is_public(uint impl_node)
{
    if (!valid_node(impl_node))
        return false;
    if (hir_item_visibility[impl_node] == HIR_ITEM_VIS_PUBLIC)
        return true;

    uint parent_i = parent_node(impl_node);
    if (valid_node(parent_i) && node_kind[parent_i] == PROD_PUB_IMPL)
        return true;

    uint grandparent_i = parent_node(parent_i);
    return valid_node(grandparent_i) && node_kind[grandparent_i] == PROD_PUB_IMPL;
}

bool trait_impl_header_visibility_matches_trait(uint trait_decl_i, uint impl_node)
{
    if (trait_decl_i >= decl_record_count())
        return false;
    bool trait_is_public = decl_visibility[trait_decl_i] == HIR_ITEM_VIS_PUBLIC;
    bool impl_is_public = trait_impl_header_is_public(impl_node);
    return trait_is_public == impl_is_public;
}

#if PREDICATE_COLLECT_METHOD_RECORDS
uint method_unsupported_contract_status(uint method_node)
{
    if (!valid_node(method_node))
        return PREDICATE_STATUS_OK;

    uint record_status = predicate_method_contract_status[method_node];
    return record_status != INVALID ? record_status : PREDICATE_STATUS_OK;
}
#endif

uint impl_receiver_type_node(uint impl_node)
{
    uint type_node = valid_node(impl_node)
        ? hir_method_impl_receiver_type_node[impl_node]
        : INVALID;
    return valid_node(type_node) ? type_node : INVALID;
}

uint direct_type_expr_child(uint node, uint ordinal)
{
    if (!valid_node(node) || ordinal != 0u || node_kind[node] != PROD_IMPL_TRAIT)
        return INVALID;
    uint trait_type = predicate_trait_impl_trait_type_node[node];
    return valid_node(trait_type) && node_kind[trait_type] == PROD_TYPE_IDENT
        ? trait_type
        : INVALID;
}

uint validate_trait_impl_type_args(
    uint impl_node,
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

    for (uint ordinal = 0u; ordinal < 2u; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;

        uint arg_node = direct_type_arg_node(trait_type_node, ordinal);
        if (!valid_node(arg_node))
        {
            uint fallback_token;
            uint fallback_status = validate_trait_impl_scalar_arg_token(
                impl_node,
                trait_type_node,
                ordinal,
                fallback_token);
            if (fallback_status != PREDICATE_STATUS_OK)
            {
                if (ordinal == 0u)
                    first_arg_token = fallback_token;
                else
                    second_arg_token = fallback_token;
                return fallback_status;
            }
            if (ordinal == 0u)
                first_arg_token = fallback_token;
            else
                second_arg_token = fallback_token;
            continue;
        }

        if (node_kind[arg_node] != PROD_TYPE_IDENT)
        {
            uint token = hir_token_pos[arg_node];
            if (ordinal == 0u)
                first_arg_token = token;
            else
                second_arg_token = token;
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        }

        if (!type_path_scan_supported(arg_node))
        {
            uint fallback_token;
            uint fallback_status = validate_trait_impl_scalar_arg_token(
                impl_node,
                trait_type_node,
                ordinal,
                fallback_token);
            if (fallback_status != PREDICATE_STATUS_OK)
            {
                if (ordinal == 0u)
                    first_arg_token = fallback_token;
                else
                    second_arg_token = fallback_token;
                return fallback_status;
            }
            if (ordinal == 0u)
                first_arg_token = fallback_token;
            else
                second_arg_token = fallback_token;
            continue;
        }

        if (trait_impl_type_arg_is_header_generic(impl_node, arg_node))
        {
            uint generic_token = type_path_leaf_token(arg_node);
            if (ordinal == 0u)
                first_arg_token = generic_token;
            else
                second_arg_token = generic_token;
            return PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG;
        }

        if (direct_type_arg_count(arg_node) != 0u)
        {
            uint token = type_path_leaf_token(arg_node);
            if (!valid_token(token))
                token = hir_token_pos[arg_node];
            if (ordinal == 0u)
                first_arg_token = token;
            else
                second_arg_token = token;
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        }

        if (!trait_impl_type_arg_shape_supported(arg_node))
        {
            uint fallback_token;
            uint fallback_status = validate_trait_impl_scalar_arg_token(
                impl_node,
                trait_type_node,
                ordinal,
                fallback_token);
            if (fallback_status != PREDICATE_STATUS_OK)
            {
                if (ordinal == 0u)
                    first_arg_token = fallback_token;
                else
                    second_arg_token = fallback_token;
                return fallback_status;
            }
            if (ordinal == 0u)
                first_arg_token = fallback_token;
            else
                second_arg_token = fallback_token;
            continue;
        }

        if (type_arg_requires_instance_args(arg_node))
        {
            uint fallback_token;
            uint fallback_status = validate_trait_impl_scalar_arg_token(
                impl_node,
                trait_type_node,
                ordinal,
                fallback_token);
            if (fallback_status != PREDICATE_STATUS_OK)
            {
                if (ordinal == 0u)
                    first_arg_token = fallback_token;
                else
                    second_arg_token = fallback_token;
                return fallback_status;
            }
            if (ordinal == 0u)
                first_arg_token = fallback_token;
            else
                second_arg_token = fallback_token;
            continue;
        }

        uint token = type_path_leaf_token(arg_node);
        if (!valid_token(token))
        {
            uint fallback_token;
            uint fallback_status = validate_trait_impl_scalar_arg_token(
                impl_node,
                trait_type_node,
                ordinal,
                fallback_token);
            if (fallback_status != PREDICATE_STATUS_OK)
            {
                if (ordinal == 0u)
                    first_arg_token = fallback_token;
                else
                    second_arg_token = fallback_token;
                return fallback_status;
            }
            token = fallback_token;
        }

        if (!trait_impl_type_arg_resolves(arg_node))
        {
            uint fallback_token;
            uint fallback_status = validate_trait_impl_scalar_arg_token(
                impl_node,
                trait_type_node,
                ordinal,
                fallback_token);
            if (fallback_status != PREDICATE_STATUS_OK)
            {
                if (ordinal == 0u)
                    first_arg_token = fallback_token;
                else
                    second_arg_token = fallback_token;
                return fallback_status;
            }
            token = fallback_token;
        }

        uint encoded_concrete = encoded_concrete_type_arg_for_type_node(arg_node);
        uint record_value = encoded_concrete != INVALID ? encoded_concrete : token;
        if (ordinal == 0u)
            first_arg_token = record_value;
        else
            second_arg_token = record_value;
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
        node,
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
    uint encoded_target = encoded_concrete_type_arg_for_type_node(target_type_node);
    predicate_subject_token[node] = encoded_target != INVALID ? encoded_target : target_token;
    predicate_bound_arg_count[node] = trait_arg_count;
    predicate_bound_first_arg_token[node] = trait_arg0_token;
    predicate_bound_second_arg_token[node] = trait_arg1_token;
    mark_predicate_syntax_token(trait_token);
    mark_predicate_syntax_token(target_token);
    mark_predicate_syntax_token(trait_arg0_token);
    mark_predicate_syntax_token(trait_arg1_token);

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
        predicate_status[node] = PREDICATE_STATUS_IMPL_VISIBILITY_MISMATCH;
        return;
    }

    if (trait_arg_status != PREDICATE_STATUS_OK)
    {
        predicate_status[node] = trait_arg_status;
        return;
    }

    if (target_status == PREDICATE_STATUS_INVALID_TARGET ||
        (target_status == PREDICATE_STATUS_OK &&
         (!valid_node(target_type_node) || !valid_token(target_token))))
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;
        return;
    }

    if (target_status != PREDICATE_STATUS_OK)
    {
        predicate_status[node] = target_status;
        return;
    }

    uint trait_node = trait_decl_i < decl_record_count() ? decl_hir_node[trait_decl_i] : INVALID;
    if (!valid_compact_hir(trait_node))
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }

    if (trait_arg_count != trait_decl_generic_param_count(trait_decl_i))
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_ARITY_MISMATCH;
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

    uint target_status = valid_node(receiver_type_node)
        ? validate_inherent_impl_target_type(node, receiver_type_node)
        : PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;
    if (target_status != PREDICATE_STATUS_OK)
    {
        predicate_status[node] = target_status;
        return;
    }

    mark_predicate_syntax_token(receiver_token);
    mark_direct_type_arg_syntax_tokens(
        receiver_type_node,
        direct_type_arg_count(receiver_type_node));
}
#endif

#if PREDICATE_COLLECT_METHOD_RECORDS
void validate_trait_method_contract_node(uint node)
{
    if (!trait_method_node(node))
        return;

    uint method_status = method_unsupported_contract_status(node);
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

void validate_impl_method_contract_record_node(uint node)
{
    if (!impl_method_node(node))
        return;

    uint name_token = method_contract_name_token(node);
    uint diagnostic_token = valid_token(name_token) ? name_token : hir_token_pos[node];
    uint owner_node = predicate_method_contract_owner_node[node];
    bool inherent_impl_method =
        valid_node(owner_node) && node_kind[owner_node] == PROD_IMPL_INHERENT;

    uint method_status = method_unsupported_contract_status(node);
    if (inherent_impl_method && method_status != PREDICATE_STATUS_OK)
    {
        predicate_owner_node[node] = node;
        predicate_bound_token[node] = diagnostic_token;
        predicate_bound_first_arg_token[node] = diagnostic_token;
        predicate_status[node] = method_status;
        return;
    }

    if (method_contract_lookup_row_valid(node))
        return;

    predicate_owner_node[node] = node;
    predicate_bound_token[node] = diagnostic_token;
    predicate_bound_first_arg_token[node] = diagnostic_token;
    if (inherent_impl_method)
        return;
    predicate_status[node] = PREDICATE_STATUS_METHOD_ARITY_MISMATCH;
}
#endif

#if PREDICATE_BOUND_ARGUMENT_VALIDATION
bool valid_bound_type_arg(uint owner_decl_node, uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return false;
    if (!bound_path_shape_supported(expr_node))
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

    uint decl_i = type_decl_for_bound_path(expr_node, owner_decl_node);
    return supported_predicate_type_arg_decl(decl_i);
}

bool bound_type_arg_shape_supported(uint owner_decl_node, uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return false;
    if (!bound_path_shape_supported(expr_node))
        return false;

    uint segment_count = bound_path_segment_count(expr_node);
    if (segment_count == 0u)
        return true;

    uint token = bound_path_leaf_token(expr_node);
    if (!valid_token(token))
        return true;

    if (segment_count == 1u)
    {
        if (generic_param_slot_for_name(owner_decl_node, token) != INVALID)
            return true;
        uint name_id = name_id_by_token[token];
        if (language_type_exists_by_name(name_id))
            return true;
    }

    uint decl_i = type_decl_for_bound_path(expr_node, owner_decl_node);
    return decl_i == INVALID || supported_predicate_type_arg_decl(decl_i);
}

bool bound_arg_requires_instance_args(uint owner_decl_node, uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return false;
    if (!bound_path_shape_supported(expr_node))
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
    uint expected_arg_count = valid_compact_hir(decl_node)
        ? generic_type_param_count_for_compact_decl(decl_node)
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

    uint segment_count = kind == PROD_BOUND_TYPE_IDENT
        ? bound_path_segment_count(arg_node)
        : 0u;
    bool unqualified_generic_arg =
        segment_count == 1u &&
        generic_param_slot_for_name(owner_decl_node, token) != INVALID;
    if (kind == PROD_BOUND_TYPE_IDENT && !unqualified_generic_arg)
    {
        if (segment_count == 1u)
        {
            uint name_id = name_id_by_token[token];
            uint type_code = name_id != INVALID ? language_type_code_by_name_id[name_id] : 0u;
            if (type_code != 0u)
                return PREDICATE_ARG_TYPE_CODE_BIT | type_code;
        }

        uint encoded_concrete = encoded_concrete_type_arg_for_bound(owner_decl_node, arg_node);
        if (encoded_concrete != INVALID)
            return encoded_concrete;
    }

    return token;
}

uint predicate_bound_arg_diagnostic_token(uint arg_node)
{
    if (!valid_node(arg_node))
        return INVALID;
    uint token = node_kind[arg_node] == PROD_BOUND_TYPE_IDENT
        ? bound_path_leaf_token(arg_node)
        : hir_token_pos[arg_node];
    if (valid_token(token))
        return token;
    token = hir_token_pos[arg_node];
    return valid_token(token) ? token : INVALID;
}

uint first_direct_bound_arg_node(uint expr_node)
{
    if (!valid_node(expr_node) || node_kind[expr_node] != PROD_BOUND_TYPE_IDENT)
        return INVALID;

    uint arg = hir_type_arg_start[expr_node];
    return valid_node(arg) && hir_type_arg_count[expr_node] != 0u ? arg : INVALID;
}

uint first_direct_bound_arg_diagnostic_token(uint expr_node)
{
    uint token = predicate_bound_arg_diagnostic_token(first_direct_bound_arg_node(expr_node));
    if (valid_token(token))
        return token;
    token = bound_path_leaf_token(expr_node);
    return valid_token(token) ? token : hir_token_pos[expr_node];
}

uint bound_arg_diagnostic_token_for(uint predicate_expr_node, uint arg_node)
{
    if (arg_node == predicate_expr_node)
    {
        uint token = first_direct_bound_arg_diagnostic_token(predicate_expr_node);
        if (valid_token(token))
            return token;
    }
    return predicate_bound_arg_diagnostic_token(arg_node);
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

void set_bound_arg_diagnostic_token(
    uint ordinal,
    uint token,
    inout uint first_arg_token,
    inout uint second_arg_token)
{
    if (ordinal == 0u)
        first_arg_token = token;
    else
        second_arg_token = token;
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
    {
        uint first_arg_node = valid_node(predicate_expr_node)
            ? predicate_bound_first_arg_token[predicate_expr_node]
            : INVALID;
        uint second_arg_node = valid_node(predicate_expr_node)
            ? predicate_bound_second_arg_token[predicate_expr_node]
            : INVALID;
        first_arg_token = bound_arg_diagnostic_token_for(predicate_expr_node, first_arg_node);
        second_arg_token = bound_arg_diagnostic_token_for(predicate_expr_node, second_arg_node);
        if (!valid_token(first_arg_token))
            first_arg_token = first_direct_bound_arg_diagnostic_token(predicate_expr_node);
        return fact_status;
    }

    if (arg_count == 0u && bound_ident_has_direct_arg_list(predicate_expr_node))
    {
        first_arg_token = first_direct_bound_arg_diagnostic_token(predicate_expr_node);
        return PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
    }

    if (arg_count > 2u)
        return PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH;

    for (uint ordinal = 0u; ordinal < 2u; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;

        uint node = predicate_bound_arg_node(predicate_expr_node, ordinal);
        if (!valid_node(node) || node_kind[node] != PROD_BOUND_TYPE_IDENT)
        {
            set_bound_arg_diagnostic_token(
                ordinal,
                bound_arg_diagnostic_token_for(predicate_expr_node, node),
                first_arg_token,
                second_arg_token);
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        }
        if (!bound_path_shape_supported(node))
        {
            set_bound_arg_diagnostic_token(
                ordinal,
                bound_arg_diagnostic_token_for(predicate_expr_node, node),
                first_arg_token,
                second_arg_token);
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        }
        uint token = predicate_bound_arg_record_value(owner_decl_node, node);
        if (!bound_type_arg_shape_supported(owner_decl_node, node))
        {
            set_bound_arg_diagnostic_token(
                ordinal,
                bound_arg_diagnostic_token_for(predicate_expr_node, node),
                first_arg_token,
                second_arg_token);
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        }
        if (bound_arg_requires_instance_args(owner_decl_node, node))
        {
            set_bound_arg_diagnostic_token(
                ordinal,
                bound_arg_diagnostic_token_for(predicate_expr_node, node),
                first_arg_token,
                second_arg_token);
            return PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        }
        if (!valid_bound_type_arg(owner_decl_node, node))
        {
            set_bound_arg_diagnostic_token(
                ordinal,
                token,
                first_arg_token,
                second_arg_token);
            return PREDICATE_STATUS_INVALID_ARG;
        }

        if (ordinal == 0u)
            first_arg_token = token;
        else
            second_arg_token = token;
    }

    return PREDICATE_STATUS_OK;
}
#endif

#if PREDICATE_BOUND_DECL_RESOLUTION
void clear_predicate_record(uint node)
{
    predicate_owner_node[node] = INVALID;
    predicate_subject_token[node] = INVALID;
    predicate_bound_token[node] = INVALID;
    predicate_bound_decl_id[node] = INVALID;
}
#endif

#if PREDICATE_BOUND_DECL_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
void mark_predicate_syntax_token(uint token_i)
{
    if (valid_token(token_i))
        predicate_syntax_token[token_i] = 1u;
}
#endif

#if PREDICATE_BOUND_DECL_RESOLUTION
void mark_direct_bound_syntax_tokens(uint node)
{
    if (node_kind[node] == PROD_BOUND_TYPE_IDENT)
    {
        mark_predicate_syntax_token(bound_path_leaf_token(node));
        mark_predicate_syntax_token(predicate_bound_first_arg_token[node]);
        mark_predicate_syntax_token(predicate_bound_second_arg_token[node]);
        return;
    }

    if (node_kind[node] == PROD_BOUND_TYPE_REF)
        mark_predicate_syntax_token(hir_token_pos[node]);
}
#endif
