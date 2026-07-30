// Dense-HIR method contract lookup and compact signature comparison helpers.
// Consumers operate on method HIR ids and compact parameter rows exclusively.

import hir_records;
import fixed.compact_method;
import fixed.key;
import range_query;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_active_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_type_root_owner;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> resolved_type_status;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_decl_token;
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

static const uint INVALID = 0xffffffffu;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint HIR_ITEM = 2u;
static const uint HIR_IMPL = 35u;
static const uint HIR_IMPL_INHERENT = 1u;
static const uint HIR_IMPL_TRAIT = 2u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;
static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint HIR_TYPE_FORM_REF = 4u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;
static const uint PREDICATE_STATUS_OK = 0u;
static const uint MAX_METHOD_SIGNATURE_PARAMS = 65535u;

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_method_count() { return min(compact_method_count[0u], gParams.n_hir_nodes); }
uint active_param_count() { return min(compact_param_count[0u], gParams.n_hir_nodes); }
uint active_type_arg_count() { return min(compact_type_arg_count[0u], gParams.n_hir_nodes); }
uint active_sorted_row_count() { return min(hir_active_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint hir) { return hir != INVALID && hir < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

bool trait_owner_hir(uint hir)
{
    return valid_hir(hir) && compact_hir_core[hir].kind == HIR_ITEM &&
           compact_hir_payload[hir].a == HIR_ITEM_KIND_TRAIT;
}

bool inherent_impl_owner_hir(uint hir)
{
    return valid_hir(hir) && compact_hir_core[hir].kind == HIR_IMPL &&
           compact_hir_payload[hir].a == HIR_IMPL_INHERENT;
}

bool trait_impl_owner_hir(uint hir)
{
    return valid_hir(hir) && compact_hir_core[hir].kind == HIR_IMPL &&
           compact_hir_payload[hir].a == HIR_IMPL_TRAIT;
}

bool method_contract_lookup_row_valid(uint method_hir)
{
    return valid_hir(method_hir) &&
           valid_hir(predicate_method_contract_owner_hir[method_hir]) &&
           predicate_method_contract_name_id[method_hir] != INVALID;
}

uint method_contract_name_token(uint method_hir)
{
    uint token = valid_hir(method_hir)
        ? predicate_method_contract_name_token[method_hir]
        : INVALID;
    return valid_token(token) ? token : INVALID;
}

uint method_contract_diagnostic_token(uint method_hir)
{
    uint token = method_contract_name_token(method_hir);
    if (valid_token(token)) return token;
    token = valid_hir(method_hir) ? compact_hir_core[method_hir].token_start : INVALID;
    return valid_token(token) ? token : INVALID;
}

uint method_contract_name_id(uint method_hir)
{
    return valid_hir(method_hir)
        ? predicate_method_contract_name_id[method_hir]
        : INVALID;
}

public struct MethodContractLookupKey { uint owner_node; uint name_id; }
public struct MethodContractFixedKey : IFixedU32RowKey<MethodContractLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint method = row < active_sorted_row_count()
            ? predicate_method_contract_key_order[row]
            : INVALID;
        if (!method_contract_lookup_row_valid(method)) return 0u;
        return lane == 0u
            ? fixed_key_encode_nullable_u32(predicate_method_contract_owner_hir[method], INVALID)
            : fixed_key_encode_nullable_u32(method_contract_name_id(method), INVALID);
    }
    public static uint key_lane(MethodContractLookupKey key, uint lane)
    {
        return lane == 0u
            ? fixed_key_encode_nullable_u32(key.owner_node, INVALID)
            : fixed_key_encode_nullable_u32(key.name_id, INVALID);
    }
}
public struct MethodContractKeyCompare : IRowQueryCompare<MethodContractLookupKey>
{
    public static int compare(uint row, MethodContractLookupKey key)
    {
        return fixed_u32_row_key_compare<MethodContractLookupKey, MethodContractFixedKey>(row, key, 2u);
    }
}

QueryRange method_contract_range_for_owner_name(uint owner, uint name_id)
{
    MethodContractLookupKey key;
    key.owner_node = owner;
    key.name_id = name_id;
    return equal_range_query<MethodContractLookupKey, MethodContractKeyCompare>(
        active_sorted_row_count(), key);
}

bool method_contract_matches(uint method, uint owner, uint name_id)
{
    return method_contract_lookup_row_valid(method) &&
           predicate_method_contract_owner_hir[method] == owner &&
           method_contract_name_id(method) == name_id;
}

bool method_contract_order_matches(uint row, uint owner, uint name_id)
{
    if (row >= active_sorted_row_count()) return false;
    return method_contract_matches(predicate_method_contract_key_order[row], owner, name_id);
}

uint first_method_contract_for_owner_name(uint owner, uint name_id)
{
    if (!valid_hir(owner) || name_id == INVALID) return INVALID;
    QueryRange range = method_contract_range_for_owner_name(owner, name_id);
    if (range.begin >= range.end ||
        !method_contract_order_matches(range.begin, owner, name_id) ||
        !method_contract_order_matches(range.end - 1u, owner, name_id))
        return INVALID;
    return predicate_method_contract_key_order[range.begin];
}

bool duplicate_method_contract_for_owner_name(uint owner, uint name_id)
{
    if (!valid_hir(owner) || name_id == INVALID) return false;
    QueryRange range = method_contract_range_for_owner_name(owner, name_id);
    return range.end > range.begin + 1u &&
           method_contract_order_matches(range.begin, owner, name_id) &&
           method_contract_order_matches(range.end - 1u, owner, name_id);
}

QueryRange method_contract_range_for_owner(uint owner)
{
    QueryRange range;
    range.begin = 0u;
    range.end = 0u;
    if (!valid_hir(owner)) return range;
    uint first = predicate_method_contract_owner_range_first[owner];
    uint count = predicate_method_contract_owner_range_count[owner];
    if (first == INVALID || count == 0u) return range;
    range.begin = min(first, active_sorted_row_count());
    range.end = min(first + count, active_sorted_row_count());
    return range;
}

bool method_contract_range_matches_owner(uint owner, QueryRange range)
{
    if (!valid_hir(owner)) return false;
    if (range.begin >= range.end) return true;
    if (range.end > active_sorted_row_count()) return false;
    uint first = predicate_method_contract_key_order[range.begin];
    uint last = predicate_method_contract_key_order[range.end - 1u];
    return method_contract_lookup_row_valid(first) &&
           method_contract_lookup_row_valid(last) &&
           predicate_method_contract_owner_hir[first] == owner &&
           predicate_method_contract_owner_hir[last] == owner;
}

bool method_param_lookup_row_valid(uint row)
{
    if (row >= active_param_count()) return false;
    HirParam parameter = compact_params[row];
    return method_contract_lookup_row_valid(parameter.owner) && parameter.ordinal != INVALID;
}

public struct MethodParamLookupKey { uint method_node; uint ordinal; }
public struct MethodParamFixedKey : IFixedU32RowKey<MethodParamLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint parameter_row = row < active_sorted_row_count()
            ? predicate_method_param_key_order[row]
            : INVALID;
        if (!method_param_lookup_row_valid(parameter_row)) return 0u;
        HirParam parameter = compact_params[parameter_row];
        return lane == 0u
            ? fixed_key_encode_nullable_u32(parameter.owner, INVALID)
            : fixed_key_encode_nullable_u32(parameter.ordinal, INVALID);
    }
    public static uint key_lane(MethodParamLookupKey key, uint lane)
    {
        return lane == 0u
            ? fixed_key_encode_nullable_u32(key.method_node, INVALID)
            : fixed_key_encode_nullable_u32(key.ordinal, INVALID);
    }
}
public struct MethodParamKeyCompare : IRowQueryCompare<MethodParamLookupKey>
{
    public static int compare(uint row, MethodParamLookupKey key)
    {
        return fixed_u32_row_key_compare<MethodParamLookupKey, MethodParamFixedKey>(row, key, 2u);
    }
}

uint method_param_for_ordinal(uint method, uint ordinal)
{
    if (!method_contract_lookup_row_valid(method) || ordinal == INVALID) return INVALID;
    MethodParamLookupKey key;
    key.method_node = method;
    key.ordinal = ordinal;
    QueryRange range = equal_range_query<MethodParamLookupKey, MethodParamKeyCompare>(
        active_sorted_row_count(), key);
    if (range.begin >= range.end) return INVALID;
    uint row = predicate_method_param_key_order[range.begin];
    if (!method_param_lookup_row_valid(row)) return INVALID;
    HirParam parameter = compact_params[row];
    return parameter.owner == method && parameter.ordinal == ordinal ? row : INVALID;
}

uint method_param_count(uint method)
{
    return valid_hir(method) ? predicate_method_contract_param_count[method] : INVALID;
}

uint method_return_type(uint method)
{
    uint type_hir = valid_hir(method)
        ? predicate_method_contract_return_type_node[method]
        : INVALID;
    return valid_hir(type_hir) ? type_hir : INVALID;
}

uint method_param_type(uint parameter_row)
{
    uint type_hir = parameter_row < active_param_count()
        ? predicate_method_contract_param_type_node[parameter_row]
        : INVALID;
    return valid_hir(type_hir) ? type_hir : INVALID;
}

uint method_signature_row(uint method)
{
    return compact_method_row_for_hir(compact_method_cores, active_method_count(), method);
}

uint method_receiver_mode(uint method)
{
    uint row = method_signature_row(method);
    return row < active_method_count() ? compact_method_signatures[row].receiver_mode : INVALID;
}

uint method_unsupported_contract_status(uint method)
{
    uint value = valid_hir(method) ? predicate_method_contract_status[method] : INVALID;
    return value != INVALID ? value : PREDICATE_STATUS_OK;
}

bool method_contract_is_public(uint method)
{
    return valid_hir(method) &&
           predicate_method_contract_visibility[method] == HIR_ITEM_VIS_PUBLIC;
}

bool type_node_ref(uint type_hir, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_hir(type_hir)) return false;
    uint token = compact_hir_core[type_hir].token_start;
    if (!valid_token(token)) return false;
    tag = type_expr_ref_tag[token];
    payload = type_expr_ref_payload[token];
    return tag != TYPE_REF_INVALID && tag != TYPE_REF_ERROR;
}

uint type_node_form(uint type_hir)
{
    return valid_hir(type_hir) ? compact_hir_payload[type_hir].a : HIR_TYPE_FORM_NONE;
}

uint type_value_node(uint type_hir)
{
    uint value = valid_hir(type_hir) ? compact_hir_payload[type_hir].b : INVALID;
    return valid_hir(value) ? value : INVALID;
}

uint type_arg_count(uint type_hir)
{
    if (!valid_hir(type_hir)) return 0u;
    HirRange range = compact_type_arg_ranges[type_hir];
    return range.start <= active_type_arg_count() &&
           range.count <= active_type_arg_count() - range.start
        ? range.count : 0u;
}

uint type_arg_for_slot(uint type_hir, uint slot)
{
    if (!valid_hir(type_hir)) return INVALID;
    HirRange range = compact_type_arg_ranges[type_hir];
    uint count = active_type_arg_count();
    if (slot >= range.count || range.start > count || range.count > count - range.start)
        return INVALID;
    HirTypeArg argument = compact_type_args[range.start + slot];
    return argument.owner == type_hir && argument.ordinal == slot && valid_hir(argument.value)
        ? argument.value : INVALID;
}

uint trait_decl_for_impl(uint impl_owner)
{
    if (!trait_impl_owner_hir(impl_owner)) return INVALID;
    uint bound = compact_hir_payload[impl_owner].b;
    uint path = valid_hir(bound) ? path_id_by_owner_hir[bound] : INVALID;
    uint decl_count = min(decl_count_out[0u], gParams.n_tokens);
    if (path < gParams.n_hir_nodes && resolved_type_status[path] == 0u)
    {
        uint decl = resolved_type_decl[path];
        uint resolved_hir = decl < decl_count ? decl_hir_node[decl] : INVALID;
        if (trait_owner_hir(resolved_hir)) return resolved_hir;
    }

    // Retain the direct reference fallback for projected aliases and
    // dependency-interface types that do not own a local compact path row.
    uint tag;
    uint payload;
    if (!type_node_ref(bound, tag, payload)) return INVALID;
    uint decl_token = INVALID;
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
        decl_token = type_instance_decl_token[payload];
    if (!valid_token(decl_token))
    {
        uint token = compact_hir_core[bound].token_start;
        decl_token = valid_token(token) ? visible_decl[token] : INVALID;
    }
    uint trait_hir = valid_token(decl_token) ? type_decl_hir_node_by_token[decl_token] : INVALID;
    return trait_owner_hir(trait_hir) ? trait_hir : INVALID;
}

bool refs_definitely_mismatch(uint left, uint right)
{
    uint left_tag;
    uint left_payload;
    uint right_tag;
    uint right_payload;
    if (!type_node_ref(left, left_tag, left_payload) ||
        !type_node_ref(right, right_tag, right_payload))
        return false;
    if (left_tag == TYPE_REF_GENERIC_PARAM || right_tag == TYPE_REF_GENERIC_PARAM)
        return false;
    if (left_tag == TYPE_REF_SCALAR || right_tag == TYPE_REF_SCALAR)
        return left_tag != right_tag || left_payload != right_payload;
    if (left_tag == TYPE_REF_INSTANCE && right_tag == TYPE_REF_INSTANCE)
    {
        uint left_decl = valid_token(left_payload) ? type_instance_decl_token[left_payload] : INVALID;
        uint right_decl = valid_token(right_payload) ? type_instance_decl_token[right_payload] : INVALID;
        if (valid_token(left_decl) && valid_token(right_decl)) return left_decl != right_decl;
        uint left_token = compact_hir_core[left].token_start;
        uint right_token = compact_hir_core[right].token_start;
        uint left_name = valid_token(left_token) ? name_id_by_token[left_token] : INVALID;
        uint right_name = valid_token(right_token) ? name_id_by_token[right_token] : INVALID;
        return left_name != INVALID && right_name != INVALID && left_name != right_name;
    }
    return false;
}

bool trait_generic_slot(uint trait_type, out uint slot)
{
    slot = INVALID;
    uint tag;
    uint payload;
    if (!type_node_ref(trait_type, tag, payload) || tag != TYPE_REF_GENERIC_PARAM)
        return false;
    slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
    return slot != INVALID;
}

bool trait_generic_substitution_mismatch(uint trait_type, uint impl_type, uint impl_owner)
{
    uint slot;
    if (!trait_generic_slot(trait_type, slot)) return false;
    uint bound = trait_impl_owner_hir(impl_owner) ? compact_hir_payload[impl_owner].b : INVALID;
    uint argument = type_arg_for_slot(bound, slot);
    return valid_hir(argument) && refs_definitely_mismatch(argument, impl_type);
}

bool array_lengths_definitely_mismatch(uint left, uint right)
{
    HirPayload left_payload = compact_hir_payload[left];
    HirPayload right_payload = compact_hir_payload[right];
    if (left_payload.d != INVALID || right_payload.d != INVALID)
        return left_payload.d != right_payload.d;
    uint left_name = valid_token(left_payload.c) ? name_id_by_token[left_payload.c] : INVALID;
    uint right_name = valid_token(right_payload.c) ? name_id_by_token[right_payload.c] : INVALID;
    return left_name != INVALID && right_name != INVALID && left_name != right_name;
}

bool flat_type_forms_definitely_mismatch(uint trait_type, uint impl_type, uint impl_owner)
{
    if (trait_generic_substitution_mismatch(trait_type, impl_type, impl_owner)) return true;
    uint trait_form = type_node_form(trait_type);
    uint impl_form = type_node_form(impl_type);
    if (trait_form == HIR_TYPE_FORM_NONE || impl_form == HIR_TYPE_FORM_NONE) return false;
    if (trait_form != impl_form) return true;
    if (trait_form == HIR_TYPE_FORM_PATH)
        return refs_definitely_mismatch(trait_type, impl_type) ||
               type_arg_count(trait_type) != type_arg_count(impl_type);
    if (trait_form == HIR_TYPE_FORM_ARRAY && array_lengths_definitely_mismatch(trait_type, impl_type))
        return true;
    if (trait_form == HIR_TYPE_FORM_REF || trait_form == HIR_TYPE_FORM_ARRAY ||
        trait_form == HIR_TYPE_FORM_SLICE)
    {
        uint trait_value = type_value_node(trait_type);
        uint impl_value = type_value_node(impl_type);
        return trait_generic_substitution_mismatch(trait_value, impl_value, impl_owner) ||
               refs_definitely_mismatch(trait_value, impl_value);
    }
    return false;
}

bool method_param_signature_definitely_mismatches(
    uint trait_method, uint impl_method, uint impl_owner, uint ordinal)
{
    uint trait_parameter = method_param_for_ordinal(trait_method, ordinal);
    uint impl_parameter = method_param_for_ordinal(impl_method, ordinal);
    if (!method_param_lookup_row_valid(trait_parameter) ||
        !method_param_lookup_row_valid(impl_parameter)) return true;
    if (ordinal == 0u && method_receiver_mode(trait_method) != method_receiver_mode(impl_method))
        return true;
    uint trait_type = method_param_type(trait_parameter);
    uint impl_type = method_param_type(impl_parameter);
    if (!valid_hir(trait_type) && !valid_hir(impl_type)) return false;
    if (!valid_hir(trait_type) || !valid_hir(impl_type)) return true;
    return flat_type_forms_definitely_mismatch(trait_type, impl_type, impl_owner);
}

bool method_return_signature_definitely_mismatches(
    uint trait_method, uint impl_method, uint impl_owner)
{
    uint trait_type = method_return_type(trait_method);
    uint impl_type = method_return_type(impl_method);
    if (!valid_hir(trait_type) && !valid_hir(impl_type)) return false;
    if (!valid_hir(trait_type) || !valid_hir(impl_type)) return true;
    return flat_type_forms_definitely_mismatch(trait_type, impl_type, impl_owner);
}
