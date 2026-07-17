// Emit explicit trait-impl method validation rows from sorted method-contract
// records.
//
// This is the first method-validation relation slice. It publishes one row per
// impl/trait method contract that can be classified without scanning an owner
// window. Trait-side unsupported contract shape is also reflected through the
// matching impl-method row so late trait methods are not hidden behind the old
// owner-window bridge. Required-method and parameter/return-type reductions
// remain in the existing collector until compact `(impl, trait_method)` rows
// and full row-driven type-ref comparison are available. Parameter validation
// consumes the sorted `(method, ordinal, param)` relation instead of walking
// method-local parameter chains and only emits definite direct mismatches; trait
// generic substitutions and nested shapes are still left to the old semantic
// fallback.

import fixed.key;
import generated_parse_production_ids;
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
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_method_owner_node;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_type_len_token;
StructuredBuffer<uint> hir_type_len_value;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_type_arg_count;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> predicate_bound_decl_id;
StructuredBuffer<uint> predicate_bound_first_arg_token;
StructuredBuffer<uint> predicate_bound_second_arg_token;
StructuredBuffer<uint> decl_type_key_count_out;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> compact_hir_count;
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> predicate_method_contract_owner_hir;
StructuredBuffer<uint> predicate_method_contract_name_token;
StructuredBuffer<uint> predicate_method_contract_name_id;
StructuredBuffer<uint> predicate_method_contract_param_count;
StructuredBuffer<uint> predicate_method_contract_param_type_node;
StructuredBuffer<uint> predicate_method_contract_return_type_node;
StructuredBuffer<uint> predicate_method_contract_visibility;
StructuredBuffer<uint> predicate_method_contract_status;
StructuredBuffer<uint> predicate_method_contract_key_order;
StructuredBuffer<uint> predicate_method_param_key_order;
StructuredBuffer<uint> predicate_method_contract_owner_range_first;
StructuredBuffer<uint> predicate_method_contract_owner_range_count;

RWStructuredBuffer<uint> predicate_method_validation_owner_node;
RWStructuredBuffer<uint> predicate_method_validation_peer_node;
RWStructuredBuffer<uint> predicate_method_validation_status;
RWStructuredBuffer<uint> predicate_method_validation_detail_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;
static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint HIR_TYPE_FORM_REF = 4u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_MISSING_METHOD = 6u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;
static const uint PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD = 20u;
static const uint PREDICATE_STATUS_EXTRA_IMPL_METHOD = 23u;
static const uint PREDICATE_STATUS_DUPLICATE_IMPL_METHOD = 24u;
static const uint PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH = 26u;
static const uint MAX_METHOD_SIGNATURE_PARAMS = 65535u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;
static const uint PREDICATE_ARG_TYPE_CODE_BIT = 0x80000000u;

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

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_hir(uint hir)
{
    return hir != INVALID && hir < active_compact_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint decl_record_count()
{
    return min(decl_type_key_count_out[0], gParams.n_tokens);
}

bool trait_owner_hir(uint hir)
{
    return valid_hir(hir) && compact_hir_payload[hir].a == HIR_ITEM_KIND_TRAIT;
}

bool trait_impl_owner_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_IMPL_TRAIT;
}

bool method_contract_lookup_row_valid(uint method_node)
{
    return valid_node(method_node) &&
           valid_hir(predicate_method_contract_owner_hir[method_node]) &&
           predicate_method_contract_name_id[method_node] != INVALID;
}

uint method_contract_name_token(uint method_node)
{
    if (!valid_node(method_node))
        return INVALID;
    uint token = predicate_method_contract_name_token[method_node];
    return valid_token(token) ? token : INVALID;
}

uint method_contract_diagnostic_token(uint method_node)
{
    uint name_token = method_contract_name_token(method_node);
    if (valid_token(name_token))
        return name_token;

    uint method_token = valid_node(method_node) ? hir_token_pos[method_node] : INVALID;
    return valid_token(method_token) ? method_token : INVALID;
}

uint method_contract_name_id(uint method_node)
{
    return valid_node(method_node)
        ? predicate_method_contract_name_id[method_node]
        : INVALID;
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
                predicate_method_contract_owner_hir[method_node],
                INVALID);
        return fixed_key_encode_nullable_u32(
            predicate_method_contract_name_id[method_node],
            INVALID);
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

bool method_contract_node_matches_owner_name(uint method_node, uint owner_node, uint name_id)
{
    return method_contract_lookup_row_valid(method_node) &&
           predicate_method_contract_owner_hir[method_node] == owner_node &&
           predicate_method_contract_name_id[method_node] == name_id;
}

bool method_contract_order_row_matches_owner_name(uint row, uint owner_node, uint name_id)
{
    if (row >= active_hir_node_count())
        return false;

    uint method_node = predicate_method_contract_key_order[row];
    return method_contract_node_matches_owner_name(method_node, owner_node, name_id);
}

QueryRange method_contract_range_for_owner(uint owner_node)
{
    QueryRange range;
    range.begin = 0u;
    range.end = 0u;
    if (!valid_hir(owner_node))
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

bool method_contract_order_row_matches_owner(uint row, uint owner_node)
{
    if (row >= active_hir_node_count())
        return false;

    uint method_node = predicate_method_contract_key_order[row];
    return method_contract_lookup_row_valid(method_node) &&
           predicate_method_contract_owner_hir[method_node] == owner_node;
}

bool method_contract_range_matches_owner(uint owner_node, QueryRange range)
{
    if (!valid_hir(owner_node))
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
    if (!valid_hir(owner_node) || name_id == INVALID)
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
    QueryRange range = method_contract_range_for_owner_name(owner_node, name_id);
    return range.end > range.begin + 1u &&
           method_contract_range_matches_owner_name(owner_node, name_id, range);
}

public struct MethodParamLookupKey
{
    uint method_node;
    uint ordinal;
}

bool method_param_lookup_row_valid(uint param_node)
{
    if (!valid_node(param_node))
        return false;

    uint4 record = hir_param_record[param_node];
    return record.w == param_node &&
           method_contract_lookup_row_valid(record.x) &&
           record.y != INVALID;
}

public struct MethodParamFixedKey : IFixedU32RowKey<MethodParamLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint param_node = row < active_hir_node_count()
            ? predicate_method_param_key_order[row]
            : INVALID;
        if (!method_param_lookup_row_valid(param_node))
            return 0u;

        uint4 record = hir_param_record[param_node];
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(record.x, INVALID);
        return fixed_key_encode_nullable_u32(record.y, INVALID);
    }

    public static uint key_lane(MethodParamLookupKey key, uint lane)
    {
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(key.method_node, INVALID);
        return fixed_key_encode_nullable_u32(key.ordinal, INVALID);
    }
}

public struct MethodParamKeyCompare : IRowQueryCompare<MethodParamLookupKey>
{
    public static int compare(uint row, MethodParamLookupKey key)
    {
        return fixed_u32_row_key_compare<MethodParamLookupKey, MethodParamFixedKey>(
            row,
            key,
            2u);
    }
}

bool method_param_order_row_matches(uint row, uint method_node, uint ordinal)
{
    if (row >= active_hir_node_count())
        return false;

    uint param_node = predicate_method_param_key_order[row];
    if (!method_param_lookup_row_valid(param_node))
        return false;

    uint4 record = hir_param_record[param_node];
    return record.x == method_node && record.y == ordinal;
}

uint method_param_for_ordinal(uint method_node, uint ordinal)
{
    if (!method_contract_lookup_row_valid(method_node) || ordinal == INVALID)
        return INVALID;

    MethodParamLookupKey key;
    key.method_node = method_node;
    key.ordinal = ordinal;
    QueryRange range = equal_range_query<MethodParamLookupKey, MethodParamKeyCompare>(
        active_hir_node_count(),
        key);
    if (range.begin >= range.end ||
        !method_param_order_row_matches(range.begin, method_node, ordinal))
        return INVALID;

    uint param_node = predicate_method_param_key_order[range.begin];
    return method_param_lookup_row_valid(param_node) ? param_node : INVALID;
}

uint trait_node_for_impl_owner(uint impl_node)
{
    if (!trait_impl_owner_node(impl_node))
        return INVALID;

    uint decl_i = predicate_bound_decl_id[impl_node];
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return INVALID;
    uint dense = decl_hir_node[decl_i];
    return valid_hir(dense) ? dense : INVALID;
}

bool method_contract_is_public(uint method_node)
{
    return valid_node(method_node) &&
           predicate_method_contract_visibility[method_node] == HIR_ITEM_VIS_PUBLIC;
}

bool trait_impl_method_visibility_matches(uint trait_method, uint impl_method)
{
    return method_contract_is_public(trait_method) == method_contract_is_public(impl_method);
}

uint method_param_count(uint method_node)
{
    return valid_node(method_node)
        ? predicate_method_contract_param_count[method_node]
        : INVALID;
}

bool trait_impl_method_arity_matches(uint trait_method, uint impl_method)
{
    uint trait_param_count = method_param_count(trait_method);
    uint impl_param_count = method_param_count(impl_method);
    return trait_param_count <= MAX_METHOD_SIGNATURE_PARAMS &&
           impl_param_count <= MAX_METHOD_SIGNATURE_PARAMS &&
           trait_param_count == impl_param_count;
}

uint method_return_type_node(uint method_node)
{
    return valid_node(method_node)
        ? predicate_method_contract_return_type_node[method_node]
        : INVALID;
}

uint method_param_type_node(uint param_node)
{
    return valid_node(param_node)
        ? predicate_method_contract_param_type_node[param_node]
        : INVALID;
}

uint type_node_leaf_token(uint type_node)
{
    if (!valid_node(type_node) || node_kind[type_node] != PROD_TYPE_IDENT)
        return INVALID;

    uint leaf = hir_type_path_leaf_node[type_node];
    if (!valid_node(leaf))
        return INVALID;

    uint token = hir_token_pos[leaf];
    return valid_token(token) ? token : INVALID;
}

bool type_node_ref(uint type_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint token = type_node_leaf_token(type_node);
    if (!valid_token(token))
        return false;

    tag = type_expr_ref_tag[token];
    payload = type_expr_ref_payload[token];
    return tag != TYPE_REF_INVALID && tag != TYPE_REF_ERROR;
}

bool predicate_arg_is_encoded_type(uint arg)
{
    return arg != INVALID && (arg & PREDICATE_ARG_TYPE_CODE_BIT) != 0u;
}

bool predicate_arg_ref(uint arg, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    if (predicate_arg_is_encoded_type(arg))
    {
        tag = TYPE_REF_SCALAR;
        payload = arg & ~PREDICATE_ARG_TYPE_CODE_BIT;
        return true;
    }

    if (!valid_token(arg))
        return false;

    tag = type_expr_ref_tag[arg];
    payload = type_expr_ref_payload[arg];
    return tag != TYPE_REF_INVALID && tag != TYPE_REF_ERROR;
}

uint predicate_trait_arg_for_slot(uint impl_owner, uint slot)
{
    if (!trait_impl_owner_node(impl_owner))
        return INVALID;
    if (slot == 0u)
        return predicate_bound_first_arg_token[impl_owner];
    if (slot == 1u)
        return predicate_bound_second_arg_token[impl_owner];
    return INVALID;
}

bool trait_generic_slot_for_type(uint type_node, out uint slot)
{
    slot = INVALID;

    uint tag;
    uint payload;
    if (!type_node_ref(type_node, tag, payload) || tag != TYPE_REF_GENERIC_PARAM)
        return false;

    slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
    return slot != INVALID;
}

bool predicate_arg_definitely_mismatches_type(uint arg, uint impl_type)
{
    uint arg_tag;
    uint arg_payload;
    uint impl_tag;
    uint impl_payload;
    bool arg_ref = predicate_arg_ref(arg, arg_tag, arg_payload);
    bool impl_ref = type_node_ref(impl_type, impl_tag, impl_payload);
    if (!arg_ref || !impl_ref)
        return false;

    if (arg_tag == TYPE_REF_GENERIC_PARAM || impl_tag == TYPE_REF_GENERIC_PARAM)
        return false;

    if (arg_tag == TYPE_REF_SCALAR || impl_tag == TYPE_REF_SCALAR)
        return arg_tag != impl_tag || arg_payload != impl_payload;

    if (arg_tag == TYPE_REF_INSTANCE && impl_tag == TYPE_REF_INSTANCE)
    {
        uint impl_token = type_node_leaf_token(impl_type);
        uint arg_name_id = valid_token(arg_payload) ? name_id_by_token[arg_payload] : INVALID;
        uint impl_name_id = valid_token(impl_token) ? name_id_by_token[impl_token] : INVALID;
        return arg_name_id != INVALID && impl_name_id != INVALID && arg_name_id != impl_name_id;
    }

    return false;
}

bool trait_generic_substitution_definitely_mismatches_type(
    uint trait_type,
    uint impl_type,
    uint impl_owner)
{
    uint slot;
    if (!trait_generic_slot_for_type(trait_type, slot))
        return false;

    uint arg = predicate_trait_arg_for_slot(impl_owner, slot);
    return predicate_arg_definitely_mismatches_type(arg, impl_type);
}

uint type_node_form(uint type_node)
{
    return valid_node(type_node) ? hir_type_form[type_node] : HIR_TYPE_FORM_NONE;
}

uint type_value_node(uint type_node)
{
    uint value = valid_node(type_node) ? hir_type_value_node[type_node] : INVALID;
    return valid_node(value) ? value : INVALID;
}

uint type_len_name_id(uint type_node)
{
    uint token = valid_node(type_node) ? hir_type_len_token[type_node] : INVALID;
    return valid_token(token) ? name_id_by_token[token] : INVALID;
}

bool direct_path_refs_definitely_mismatch(uint trait_type, uint impl_type)
{
    uint trait_tag;
    uint trait_payload;
    uint impl_tag;
    uint impl_payload;
    bool trait_ref = type_node_ref(trait_type, trait_tag, trait_payload);
    bool impl_ref = type_node_ref(impl_type, impl_tag, impl_payload);
    if (!trait_ref || !impl_ref)
        return false;

    if (trait_tag == TYPE_REF_GENERIC_PARAM || impl_tag == TYPE_REF_GENERIC_PARAM)
        return false;

    if (trait_tag == TYPE_REF_SCALAR || impl_tag == TYPE_REF_SCALAR)
        return trait_tag != impl_tag || trait_payload != impl_payload;

    if (trait_tag == TYPE_REF_INSTANCE && impl_tag == TYPE_REF_INSTANCE)
    {
        uint trait_token = type_node_leaf_token(trait_type);
        uint impl_token = type_node_leaf_token(impl_type);
        uint trait_name_id = valid_token(trait_token) ? name_id_by_token[trait_token] : INVALID;
        uint impl_name_id = valid_token(impl_token) ? name_id_by_token[impl_token] : INVALID;
        return trait_name_id != INVALID &&
               impl_name_id != INVALID &&
               trait_name_id != impl_name_id;
    }

    return false;
}

bool direct_leaf_or_generic_definitely_mismatch(
    uint trait_type,
    uint impl_type,
    uint impl_owner)
{
    if (trait_generic_substitution_definitely_mismatches_type(trait_type, impl_type, impl_owner))
        return true;
    return direct_path_refs_definitely_mismatch(trait_type, impl_type);
}

bool array_lengths_definitely_mismatch(uint trait_type, uint impl_type)
{
    uint trait_len = valid_node(trait_type) ? hir_type_len_value[trait_type] : INVALID;
    uint impl_len = valid_node(impl_type) ? hir_type_len_value[impl_type] : INVALID;
    if (trait_len != INVALID || impl_len != INVALID)
        return trait_len != impl_len;

    uint trait_name = type_len_name_id(trait_type);
    uint impl_name = type_len_name_id(impl_type);
    return trait_name != INVALID && impl_name != INVALID && trait_name != impl_name;
}

bool top_level_type_args_definitely_mismatch(
    uint trait_type,
    uint impl_type,
    uint impl_owner)
{
    uint trait_count = valid_node(trait_type) ? hir_type_arg_count[trait_type] : 0u;
    uint impl_count = valid_node(impl_type) ? hir_type_arg_count[impl_type] : 0u;
    if (trait_count != impl_count)
        return true;
    return false;
}

bool flat_type_forms_definitely_mismatch(uint trait_type, uint impl_type, uint impl_owner)
{
    if (trait_generic_substitution_definitely_mismatches_type(trait_type, impl_type, impl_owner))
        return true;

    uint trait_form = type_node_form(trait_type);
    uint impl_form = type_node_form(impl_type);
    if (trait_form == HIR_TYPE_FORM_NONE || impl_form == HIR_TYPE_FORM_NONE)
        return false;
    if (trait_form != impl_form)
        return true;

    if (trait_form == HIR_TYPE_FORM_PATH)
    {
        if (direct_path_refs_definitely_mismatch(trait_type, impl_type))
            return true;
        return top_level_type_args_definitely_mismatch(trait_type, impl_type, impl_owner);
    }

    if (trait_form == HIR_TYPE_FORM_REF)
        return direct_leaf_or_generic_definitely_mismatch(
            type_value_node(trait_type),
            type_value_node(impl_type),
            impl_owner);

    if (trait_form == HIR_TYPE_FORM_ARRAY || trait_form == HIR_TYPE_FORM_SLICE)
    {
        if (trait_form == HIR_TYPE_FORM_ARRAY &&
            array_lengths_definitely_mismatch(trait_type, impl_type))
            return true;

        return direct_leaf_or_generic_definitely_mismatch(
            type_value_node(trait_type),
            type_value_node(impl_type),
            impl_owner);
    }

    return false;
}

bool method_param_signature_definitely_mismatches(
    uint trait_method,
    uint impl_method,
    uint impl_owner,
    uint ordinal)
{
    uint trait_param = method_param_for_ordinal(trait_method, ordinal);
    uint impl_param = method_param_for_ordinal(impl_method, ordinal);
    if (!valid_node(trait_param) || !valid_node(impl_param))
        return true;

    if (node_kind[trait_param] != node_kind[impl_param])
        return true;

    uint trait_type = method_param_type_node(trait_param);
    uint impl_type = method_param_type_node(impl_param);
    if (!valid_node(trait_type) && !valid_node(impl_type))
        return false;
    if (!valid_node(trait_type) || !valid_node(impl_type))
        return true;

    return flat_type_forms_definitely_mismatch(trait_type, impl_type, impl_owner);
}

bool trait_impl_method_return_signature_definitely_mismatches(
    uint trait_method,
    uint impl_method,
    uint impl_owner)
{
    uint trait_type = method_return_type_node(trait_method);
    uint impl_type = method_return_type_node(impl_method);
    if (!valid_node(trait_type) && !valid_node(impl_type))
        return false;
    if (!valid_node(trait_type) || !valid_node(impl_type))
        return true;

    return flat_type_forms_definitely_mismatch(trait_type, impl_type, impl_owner);
}

uint method_unsupported_contract_status(uint method_node)
{
    if (!valid_node(method_node))
        return PREDICATE_STATUS_OK;

    uint record_status = predicate_method_contract_status[method_node];
    return record_status != INVALID ? record_status : PREDICATE_STATUS_OK;
}

void publish_validation_row(uint method_node, uint owner, uint peer, uint status, uint detail)
{
    predicate_method_validation_owner_node[method_node] = owner;
    predicate_method_validation_peer_node[method_node] = peer;
    predicate_method_validation_status[method_node] = status;
    predicate_method_validation_detail_token[method_node] = detail;
}

void publish_type_peer(uint impl_type, uint trait_type, uint owner, uint method_node)
{
    if (!valid_node(impl_type) || !valid_node(trait_type) || !valid_node(owner))
        return;

    predicate_method_validation_owner_node[impl_type] = owner;
    predicate_method_validation_peer_node[impl_type] = trait_type;
    predicate_method_validation_status[impl_type] = PREDICATE_STATUS_OK;
    predicate_method_validation_detail_token[impl_type] =
        method_contract_diagnostic_token(method_node);
}

bool validate_impl_param_row(uint param_node)
{
    if (!method_param_lookup_row_valid(param_node))
        return false;

    uint4 record = hir_param_record[param_node];
    uint impl_method = record.x;
    uint ordinal = record.y;
    uint owner_hir = predicate_method_contract_owner_hir[impl_method];
    uint owner_raw = hir_method_owner_node[impl_method];
    if (!valid_hir(owner_hir) || !trait_impl_owner_node(owner_raw))
        return true;

    uint name_id = method_contract_name_id(impl_method);
    uint trait_hir = trait_node_for_impl_owner(owner_raw);
    uint trait_method = valid_hir(trait_hir)
        ? first_method_contract_for_owner_name(trait_hir, name_id)
        : INVALID;
    if (!valid_node(trait_method))
        return true;

    if (method_unsupported_contract_status(impl_method) != PREDICATE_STATUS_OK ||
        method_unsupported_contract_status(trait_method) != PREDICATE_STATUS_OK ||
        duplicate_method_contract_for_owner_name(owner_hir, name_id) ||
        !trait_impl_method_arity_matches(trait_method, impl_method))
        return true;

    if (ordinal >= method_param_count(trait_method) ||
        ordinal >= method_param_count(impl_method))
        return true;

    publish_type_peer(
        method_param_type_node(param_node),
        method_param_type_node(method_param_for_ordinal(trait_method, ordinal)),
        owner_raw,
        impl_method);

    if (method_param_signature_definitely_mismatches(
            trait_method, impl_method, owner_raw, ordinal))
    {
        uint detail = method_contract_diagnostic_token(impl_method);
        publish_validation_row(
            param_node,
            owner_raw,
            trait_method,
            PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH,
            valid_token(detail) ? detail : hir_token_pos[param_node]);
    }

    return true;
}

void validate_impl_owner_method_counts(uint owner)
{
    uint owner_hir = valid_node(owner) ? raw_to_compact_hir[owner] : INVALID;
    uint trait_hir = trait_node_for_impl_owner(owner);
    if (!valid_hir(owner_hir) || !valid_hir(trait_hir))
        return;

    QueryRange trait_methods = method_contract_range_for_owner(trait_hir);
    QueryRange impl_methods = method_contract_range_for_owner(owner_hir);
    if (!method_contract_range_matches_owner(trait_hir, trait_methods) ||
        !method_contract_range_matches_owner(owner_hir, impl_methods))
        return;

    uint trait_count = method_contract_range_count(trait_methods);
    uint impl_count = method_contract_range_count(impl_methods);
    if (trait_count == INVALID || impl_count == INVALID || trait_count <= impl_count)
        return;

    uint owner_token = valid_node(owner) ? hir_token_pos[owner] : INVALID;
    publish_validation_row(
        owner,
        owner,
        trait_hir,
        PREDICATE_STATUS_MISSING_METHOD,
        valid_token(owner_token) ? owner_token : INVALID);
}

void validate_trait_method_row(
    uint method_node,
    uint owner_hir,
    uint owner_raw,
    uint name_id,
    uint detail_token)
{
    if (duplicate_method_contract_for_owner_name(owner_hir, name_id))
    {
        uint first = first_method_contract_for_owner_name(owner_hir, name_id);
        if (first != method_node)
        {
            publish_validation_row(
                method_node,
                owner_raw,
                first,
                PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD,
                detail_token);
            return;
        }
    }

    uint status = method_unsupported_contract_status(method_node);
    publish_validation_row(method_node, owner_raw, INVALID, status, detail_token);
}

void validate_impl_method_row(
    uint method_node,
    uint owner_hir,
    uint owner_raw,
    uint name_id,
    uint detail_token)
{
    uint trait_hir = trait_node_for_impl_owner(owner_raw);
    uint trait_method = valid_hir(trait_hir)
        ? first_method_contract_for_owner_name(trait_hir, name_id)
        : INVALID;

    uint status = method_unsupported_contract_status(method_node);
    if (status != PREDICATE_STATUS_OK)
    {
        publish_validation_row(method_node, owner_raw, trait_method, status, detail_token);
        return;
    }

    if (!valid_node(trait_method))
    {
        publish_validation_row(
            method_node,
            owner_raw,
            INVALID,
            PREDICATE_STATUS_EXTRA_IMPL_METHOD,
            detail_token);
        return;
    }

    uint trait_status = method_unsupported_contract_status(trait_method);
    if (trait_status != PREDICATE_STATUS_OK)
    {
        uint trait_detail = method_contract_diagnostic_token(trait_method);
        publish_validation_row(
            method_node,
            owner_raw,
            trait_method,
            trait_status,
            valid_token(trait_detail) ? trait_detail : detail_token);
        return;
    }

    if (duplicate_method_contract_for_owner_name(owner_hir, name_id))
    {
        uint first = first_method_contract_for_owner_name(owner_hir, name_id);
        if (first != method_node)
        {
            publish_validation_row(
                method_node,
                owner_raw,
                first,
                PREDICATE_STATUS_DUPLICATE_IMPL_METHOD,
                detail_token);
            return;
        }
    }

    if (!trait_impl_method_visibility_matches(trait_method, method_node))
    {
        publish_validation_row(
            method_node,
            owner_raw,
            trait_method,
            PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH,
            detail_token);
        return;
    }

    if (!trait_impl_method_arity_matches(trait_method, method_node))
    {
        publish_validation_row(
            method_node,
            owner_raw,
            trait_method,
            PREDICATE_STATUS_METHOD_ARITY_MISMATCH,
            detail_token);
        return;
    }

    publish_type_peer(
        method_return_type_node(method_node),
        method_return_type_node(trait_method),
        owner_raw,
        method_node);

    if (trait_impl_method_return_signature_definitely_mismatches(
            trait_method,
            method_node,
            owner_raw))
    {
        publish_validation_row(
            method_node,
            owner_raw,
            trait_method,
            PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH,
            detail_token);
        return;
    }

    publish_validation_row(
        method_node, owner_raw, trait_method, PREDICATE_STATUS_OK, detail_token);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint method_node = linear_thread_id(dtid);
    if (validate_impl_param_row(method_node))
        return;

    if (trait_impl_owner_node(method_node))
    {
        validate_impl_owner_method_counts(method_node);
        return;
    }

    if (!method_contract_lookup_row_valid(method_node))
        return;

    uint owner_hir = predicate_method_contract_owner_hir[method_node];
    uint owner_raw = hir_method_owner_node[method_node];
    uint name_id = method_contract_name_id(method_node);
    uint name_token = method_contract_name_token(method_node);
    uint diagnostic_token = method_contract_diagnostic_token(method_node);
    if (!valid_token(name_token) || name_id == INVALID)
    {
        publish_validation_row(
            method_node,
            owner_raw,
            INVALID,
            PREDICATE_STATUS_METHOD_ARITY_MISMATCH,
            diagnostic_token);
        return;
    }

    if (trait_owner_hir(owner_hir))
        validate_trait_method_row(
            method_node, owner_hir, owner_raw, name_id, diagnostic_token);
    else if (trait_impl_owner_node(owner_raw))
        validate_impl_method_row(
            method_node, owner_hir, owner_raw, name_id, diagnostic_token);
}
