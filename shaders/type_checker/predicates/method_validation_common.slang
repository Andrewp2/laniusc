import type_checker.constant_atoms;
// Dense-HIR method contract lookup and compact signature comparison helpers.
// Consumers operate on method HIR ids and compact parameter rows exclusively.

import hir_records;
import type_checker.checked_type_graph;
import type_checker.scoped_type_equality;
import fixed.compact_method;
import type_checker.predicates.method_contract_lookup;
import type_checker.predicates.trait_reference;

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
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> resolved_type_status;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> predicate_method_contract_owner_hir;
StructuredBuffer<uint> predicate_method_contract_name_token;
StructuredBuffer<uint> predicate_method_contract_name_id;
StructuredBuffer<uint> predicate_method_contract_param_count;
StructuredBuffer<uint> predicate_method_contract_param_type_node;
StructuredBuffer<uint> predicate_method_contract_return_type_node;
StructuredBuffer<uint> predicate_method_contract_visibility;
StructuredBuffer<uint> predicate_method_contract_status;
StructuredBuffer<uint> predicate_method_contract_owner_count;
StructuredBuffer<uint> predicate_method_contract_lookup_head;
StructuredBuffer<uint> predicate_method_contract_lookup_next;
StructuredBuffer<uint> predicate_bound_reference;

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
    if (!valid_hir(method_hir))
        return false;
    uint method_row = compact_method_row_for_hir(
        compact_method_cores,
        active_method_count(),
        method_hir);
    return method_row < active_method_count() &&
           compact_method_cores[method_row].node == method_hir &&
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

bool method_contract_matches(uint method, uint owner, uint name_id)
{
    return method_contract_lookup_row_valid(method) &&
           predicate_method_contract_owner_hir[method] == owner &&
           method_contract_name_id(method) == name_id;
}

uint first_method_contract_for_owner_name(uint owner, uint name_id)
{
    if (!valid_hir(owner) || name_id == INVALID) return INVALID;
    uint count = active_method_count();
    if (count == 0u) return INVALID;

    uint bucket = method_contract_lookup_bucket(owner, name_id, count);
    uint link = predicate_method_contract_lookup_head[bucket];
    uint visited = 0u;
    uint best = INVALID;
    uint best_token = INVALID;
    while (link != 0u && visited < count)
    {
        uint method = link - 1u;
        if (!valid_hir(method)) return INVALID;
        if (method_contract_matches(method, owner, name_id))
        {
            uint token = method_contract_diagnostic_token(method);
            if (best == INVALID || token < best_token ||
                (token == best_token && method < best))
            {
                best = method;
                best_token = token;
            }
        }
        link = predicate_method_contract_lookup_next[method];
        visited += 1u;
    }
    return link == 0u ? best : INVALID;
}

bool duplicate_method_contract_for_owner_name(uint owner, uint name_id)
{
    if (!valid_hir(owner) || name_id == INVALID) return false;
    uint count = active_method_count();
    if (count == 0u) return false;

    uint bucket = method_contract_lookup_bucket(owner, name_id, count);
    uint link = predicate_method_contract_lookup_head[bucket];
    uint visited = 0u;
    uint matches = 0u;
    while (link != 0u && visited < count)
    {
        uint method = link - 1u;
        if (!valid_hir(method)) return false;
        if (method_contract_matches(method, owner, name_id))
        {
            matches += 1u;
            if (matches > 1u) return true;
        }
        link = predicate_method_contract_lookup_next[method];
        visited += 1u;
    }
    return false;
}

uint method_contract_count_for_owner(uint owner)
{
    return valid_hir(owner) ? predicate_method_contract_owner_count[owner] : 0u;
}

bool method_param_lookup_row_valid(uint row)
{
    if (row >= active_param_count()) return false;
    HirParam parameter = compact_params[row];
    return method_contract_lookup_row_valid(parameter.owner) && parameter.ordinal != INVALID;
}

uint method_param_for_ordinal(uint method, uint ordinal)
{
    if (!method_contract_lookup_row_valid(method) || ordinal == INVALID) return INVALID;
    HirRange range = compact_param_ranges[method];
    if (range.start == INVALID || ordinal >= range.count) return INVALID;
    uint row = range.start + ordinal;
    if (row < range.start) return INVALID;
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
    // Impl collection resolves the predicate identity before method checking.
    // Its bound is not a value type and need not own a nominal instance.
    // Imported identities are checked against their defining interface page.
    uint reference = predicate_bound_reference[impl_owner];
    uint decl_count = min(decl_count_out[0u], gParams.n_tokens);
    if (trait_reference_is_dependency(reference) || reference >= decl_count)
        return INVALID;
    uint trait_hir = decl_hir_node[reference];
    return trait_owner_hir(trait_hir) ? trait_hir : INVALID;
}

// A trait signature is interpreted under the impl's ordered trait arguments.
// Substitution happens once: an impl argument already belongs to impl scope.
struct TraitMethodContractGraph : IScopedTypeGraph
{
    static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<TraitMethodContractGraph>(reference, constant); }
    static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return source_substitute_type_parameter<TraitMethodContractGraph>(environment, reference, tag, payload); }
    static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { return source_substitute_constant_parameter<TraitMethodContractGraph>(environment, reference, kind, value); }
    static uint parameter_slot(uint token) { return ScopedCheckedTypeGraph.parameter_slot(token); }
    static uint constant_parameter_slot(uint token) { return ScopedCheckedTypeGraph.constant_parameter_slot(token); }
    static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { kind = 0u; value = INVALID; return false; }
    static uint metadata(uint instance, uint field) { return ScopedCheckedTypeGraph.metadata(instance, field); }
    static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return ScopedCheckedTypeGraph.argument(instance, slot, tag, payload); }
    static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    {
        uint root = valid_hir(environment) ? compact_hir_payload[environment].b : INVALID;
        uint type_node = type_arg_for_slot(root, slot);
        return type_node_ref(type_node, tag, payload);
    }
}

bool complete_method_types_mismatch(uint trait_type, uint impl_type, uint impl_owner)
{
    uint left_tag; uint left_payload; uint right_tag; uint right_payload;
    if (!type_node_ref(trait_type, left_tag, left_payload) ||
        !type_node_ref(impl_type, right_tag, right_payload)) return true;
    return !scoped_type_refs_equal<TraitMethodContractGraph>(
        left_tag, left_payload, impl_owner, right_tag, right_payload, INVALID,
        checked_type_capacity(), gParams.n_tokens);
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
    return complete_method_types_mismatch(trait_type, impl_type, impl_owner);
}

bool method_return_signature_definitely_mismatches(
    uint trait_method, uint impl_method, uint impl_owner)
{
    uint trait_type = method_return_type(trait_method);
    uint impl_type = method_return_type(impl_method);
    if (!valid_hir(trait_type) && !valid_hir(impl_type)) return false;
    if (!valid_hir(trait_type) || !valid_hir(impl_type)) return true;
    return complete_method_types_mismatch(trait_type, impl_type, impl_owner);
}
