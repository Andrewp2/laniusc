import type_checker.constant_atoms;
import type_checker.constant_parameter_slots;
import type_checker.concrete_type_equality;
// HIR predicate record collection shared by generic bounds, where clauses, and
// trait/inherent impl headers.
//
// This pass consumes parser-owned predicate parse nodes, generic-parameter
// declaration records, interned name ids, language type records, and module
// declaration records. It publishes node-keyed predicate records for each
// top-level bound expression, trait impl header, and unsupported trait-method
// contract shape so later validation can reject bad predicates without treating
// bounds or impls as comments.

import hir_records;
import type_checker.type.instances.generic_param_lookup;
import type_checker.modules.import_visible_lookup;
import type_checker.modules.decl_lookup;
import type_checker.modules.module_lookup;
import type_checker.predicates.trait_reference;

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

#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
import type_checker.checked_type_graph;
StructuredBuffer<uint> type_decl_hir_node_by_token;
#endif

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;

#if PREDICATE_BOUND_PATH_RESOLUTION || PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
#endif
#if PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> predicate_trait_impl_trait_type_node;
StructuredBuffer<uint> predicate_method_contract_owner_count;
StructuredBuffer<HirRange> compact_generic_param_ranges;
#endif
StructuredBuffer<uint> name_id_by_token;
#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_decl_const_param_count_by_owner_token;
#endif
#if PREDICATE_BOUND_DECL_RESOLUTION
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<HirPredicate> compact_predicates;
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
StructuredBuffer<uint> generic_param_lookup_state;
#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> language_type_code_by_name_id;
#endif
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> decl_hir_node;
#endif
StructuredBuffer<uint> decl_visibility;
#if PREDICATE_BOUND_PATH_RESOLUTION
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_by_canonical_id;
StructuredBuffer<uint> decl_lookup_state;
StructuredBuffer<uint> module_id_by_file_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_prefix_id;
#endif
#if PREDICATE_BOUND_PATH_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_id_by_owner_hir;
#endif
#if PREDICATE_BOUND_PATH_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
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
StructuredBuffer<uint> import_visible_type_lookup_state;
#endif

RWStructuredBuffer<uint> predicate_owner_node;
#if PREDICATE_BOUND_DECL_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
RWStructuredBuffer<uint> predicate_subject_token;
RWStructuredBuffer<uint> predicate_bound_token;
#endif
RWStructuredBuffer<uint> predicate_bound_reference;
RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;
#if PREDICATE_BOUND_DECL_RESOLUTION || PREDICATE_COLLECT_IMPL_RECORDS
RWStructuredBuffer<uint> predicate_syntax_token;
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
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_INVALID_SUBJECT = 1u;
static const uint PREDICATE_STATUS_BOUND_NOT_TRAIT = 2u;
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
static const uint PREDICATE_STATUS_UNKNOWN_BOUND_TYPE = 35u;
static const uint PREDICATE_STATUS_INACCESSIBLE_BOUND_TYPE_ARG = 36u;
static const uint PREDICATE_STATUS_UNSUPPORTED_CONST_TRAIT = 37u;
static const uint PREDICATE_STATUS_UNCONSTRAINED_IMPL_PARAMETER = 38u;
static const uint PREDICATE_STATUS_IMPL_HEAD_WORK_LIMIT = 39u;
static const uint IMPORT_VISIBLE_STATUS_OK = 0u;

#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
#include "type_roots.slang"
#endif

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u
        ? 0u
        : min(gParams.n_hir_nodes, compact_hir_count[0u]);
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
    return valid_node(node) ? compact_hir_core[node].parent : INVALID;
}

#if PREDICATE_BOUND_PATH_RESOLUTION
uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = compact_hir_links[node].first_child;
    return valid_node(child) && parent_node(child) == node && child > node
        ? child
        : INVALID;
}

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = compact_hir_links[node].next_sibling;
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

uint compact_item_kind_for_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    return node < count ? compact_hir_payload[node].a : INVALID;
}

bool predicate_generic_owner_supported(uint node)
{
    if (!valid_node(node)) return false;
    // Methods are canonical functions but do not enter the ordinary item
    // namespace, so their payload.a has no item-kind discriminator.
    if (compact_hir_core[node].kind == 3u) return true;
    if (compact_hir_core[node].kind == 35u)
        return compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_IMPL_INHERENT ||
            compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_IMPL_TRAIT;
    return callable_generic_decl_item_kind(compact_item_kind_for_node(node));
}

uint generic_decl_owner_for_node(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint owner = generic_decl_owner_by_node[node];
    // Impl prerequisites retain their exact lexical owner like callable bounds.
    if (!valid_node(owner)) return INVALID;
    bool supported = compact_hir_core[owner].kind == 3u || compact_hir_core[owner].kind == 35u
        ? predicate_generic_owner_supported(owner)
        : generic_decl_item_kind(compact_item_kind_for_node(owner));
    return supported ? owner : INVALID;
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
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (decl_node >= count)
        return INVALID;
    return hir_generic_owner_token(compact_hir_core[decl_node], compact_hir_payload[decl_node],
        gParams.n_tokens);
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

// Hashing visits every child, so validate nominal application arity at every
// node, including types nested inside arrays, references, and other records.
// A declaration name without its operands is not a complete type argument.
public struct PredicateDeclarationGraph : IScopedTypeGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    public static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<PredicateDeclarationGraph>(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return source_substitute_type_parameter<PredicateDeclarationGraph>(environment, reference, tag, payload); }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { return source_substitute_constant_parameter<PredicateDeclarationGraph>(environment, reference, kind, value); }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    { return ScopedCheckedTypeGraph.environment_argument(environment, slot, tag, payload); }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { return ScopedCheckedTypeGraph.environment_constant(environment, slot, kind, value); }
    public static uint parameter_slot(uint token)
    { return ScopedCheckedTypeGraph.parameter_slot(token); }
    public static uint constant_parameter_slot(uint token)
    { return ScopedCheckedTypeGraph.constant_parameter_slot(token); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        return ScopedCheckedTypeGraph.argument(instance, slot, tag, payload) &&
            (tag != TYPE_REF_SCALAR || payload < TY_STRUCT_BASE);
    }
    public static uint metadata(uint instance, uint field)
    {
        if (field == 0u && type_instance_kind[instance] != 1u &&
            type_instance_elem_ref_tag[instance] == TYPE_REF_SCALAR &&
            type_instance_elem_ref_payload[instance] >= TY_STRUCT_BASE) return 0u;
        if (field == 0u && type_instance_kind[instance] == 1u)
        {
            uint declaration = type_instance_decl_token[instance];
            if (valid_token(declaration) && type_instance_arg_count[instance] !=
                type_decl_generic_param_count_by_owner_token[declaration] +
                type_decl_const_param_count_by_owner_token[declaration]) return 0u;
        }
        return ScopedCheckedTypeGraph.metadata(instance, field);
    }
}

bool predicate_type_is_well_formed(uint2 ref)
{
    // Fully checked nominal types have graph nodes. A leftover encoded name
    // denotes an incomplete application and cannot be accepted as a scalar.
    if (ref.x == TYPE_REF_SCALAR && ref.y >= TY_STRUCT_BASE) return false;
    uint hash;
    return scoped_type_ref_hash<PredicateDeclarationGraph>(ref.x, ref.y, INVALID,
        checked_type_capacity(), gParams.n_tokens, hash);
}
#endif

bool generic_param_key_matches(uint row, uint owner, uint name_id, uint kind)
{
    return row < active_generic_param_count() &&
           generic_param_owner_token[row] == owner &&
           generic_param_name_id[row] == name_id &&
           generic_param_kind[row] == kind;
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
    uint row = generic_param_lookup_find(
        owner_token, name_id, count, gParams.n_tokens,
        generic_param_owner_token, generic_param_name_id,
        generic_param_lookup_state);
    return generic_param_key_matches(row, owner_token, name_id, kind) ? row : INVALID;
}

#if PREDICATE_BOUND_DECL_RESOLUTION
// Reuse canonical lexical lookup, including cross-domain name shadowing.
// The collector's bound input aliases the same nearest-owner producer.
#define generic_decl_owner_by_node_a generic_decl_owner_by_node
#include "../type/instances/lexical_parameter_lookup.slang"
#undef generic_decl_owner_by_node_a
#endif

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
    return min(module_count_out[0], gParams.n_hir_nodes);
}

uint bound_path_record_id(uint expr_node)
{
    if (!valid_node(expr_node) ||
        compact_hir_semantic_facts[expr_node].semantic_kind != HIR_SEMANTIC_BOUND_PATH)
        return INVALID;
    uint path_i = valid_compact_hir(expr_node) ? path_id_by_owner_hir[expr_node] : INVALID;
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

uint find_module_for_bound_path_prefix(uint expr_node, uint prefix_count)
{
    uint path_i = bound_path_record_id(expr_node);
    if (path_i == INVALID || prefix_count == 0u ||
        prefix_count >= path_segment_count[path_i])
        return INVALID;

    uint canonical_id = path_prefix_id[path_segment_base[path_i] + prefix_count - 1u];
    uint module_id = module_lookup_find(
        canonical_id,
        gParams.n_tokens,
        module_by_canonical_id);
    return module_id < module_record_count() ? module_id : INVALID;
}

uint find_type_decl_in_module(uint module_id, uint name_id)
{
    if (module_id == INVALID || name_id == INVALID)
        return INVALID;

    uint decl_i = decl_lookup_query(
        module_id, HIR_ITEM_NAMESPACE_TYPE, name_id, DECL_LOOKUP_INVALID,
        decl_record_count(), decl_module_id, decl_namespace, decl_name_id,
        decl_parent_type_decl, decl_lookup_state).unique();
    return decl_i < decl_record_count() ? decl_i : INVALID;
}

uint owner_module_for_decl_node(uint owner_decl_node)
{
    if (!valid_node(owner_decl_node))
        return INVALID;

    // Declaration namespace ownership comes from the parser-owned source file,
    // including nameless impls. Impl payload.b is a dense bound HIR identity;
    // generic-owner tokens likewise do not establish declaration visibility.
    uint file_id = compact_hir_links[owner_decl_node].file_id;
    if (file_id >= max(gParams.n_source_files, 1u))
        return INVALID;
    uint module_id = module_id_by_file_id[file_id];
    if (module_id != INVALID)
        return module_id;
    // Match module-record attachment's implicit single-source namespace.
    return file_id == 0u && module_record_count() == 0u ? 0u : INVALID;
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

uint trait_reference_for_bound_path(uint expr_node, uint owner_decl_node)
{
    uint path_i = bound_path_record_id(expr_node);
    if (path_i == INVALID)
        return INVALID;
    if (resolved_type_status[path_i] == 0u)
    {
        uint resolved = resolved_type_decl[path_i];
        return resolved < decl_record_count() ? resolved
            : trait_reference_for_dependency_path(path_i);
    }

    // A fully-qualified public trait name is self-contained and does not need
    // an import. The shared path resolver intentionally requires imports for
    // ordinary qualified value/type use, so retain that language rule here.
    uint segment_count = bound_path_segment_count(expr_node);
    if (segment_count <= 1u)
        return INVALID;
    uint leaf_name_id = bound_path_segment_name_id(expr_node, segment_count - 1u);
    uint module_i = find_module_for_bound_path_prefix(expr_node, segment_count - 1u);
    uint decl_i = find_type_decl_in_module(module_i, leaf_name_id);
    uint owner_module = owner_module_for_decl_node(owner_decl_node);
    return decl_visible_from_module(owner_module, decl_i) ? decl_i : INVALID;
}

#endif

#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
uint trait_reference_parameter_count(uint decl_i)
{
    if (trait_reference_is_dependency(decl_i))
        return trait_reference_header(decl_i, 1u) + trait_reference_header(decl_i, 2u);
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
    if (!valid_node(expr_node) ||
        compact_hir_semantic_facts[expr_node].semantic_kind != HIR_SEMANTIC_TYPE_PATH)
        return INVALID;

    uint path_i = valid_compact_hir(expr_node) ? path_id_by_owner_hir[expr_node] : INVALID;
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

    uint token = valid_node(expr_node) &&
            compact_hir_semantic_facts[expr_node].semantic_kind == HIR_SEMANTIC_TYPE_PATH
        ? compact_hir_core[expr_node].token_start
        : INVALID;
    return valid_token(token) && name_id_by_token[token] != INVALID;
}

uint type_path_segment_count(uint expr_node)
{
    uint path_i = type_path_record_id(expr_node);
    if (path_i == INVALID)
    {
        uint token = valid_node(expr_node) &&
                compact_hir_semantic_facts[expr_node].semantic_kind == HIR_SEMANTIC_TYPE_PATH
            ? compact_hir_core[expr_node].token_start
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
        uint token = valid_node(expr_node) &&
                compact_hir_semantic_facts[expr_node].semantic_kind == HIR_SEMANTIC_TYPE_PATH
            ? compact_hir_core[expr_node].token_start
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

uint trait_reference_for_type_path(uint expr_node)
{
    uint path = type_path_record_id(expr_node);
    if (path == INVALID || resolved_type_status[path] != 0u) return INVALID;
    uint declaration = resolved_type_decl[path];
    return declaration < decl_record_count() ? declaration
        : trait_reference_for_dependency_path(path);
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

    return nominal_type_code_for_decl(decl_i) != 0u;
}

uint nominal_type_code_for_decl(uint decl_i)
{
    if (decl_i >= decl_record_count() || decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_TYPE)
        return 0u;
    uint owner = decl_hir_node[decl_i];
    uint token = valid_compact_hir(owner) ? compact_decl_name_token(owner) : INVALID;
    if (!valid_token(token)) return 0u;
    uint tag = type_expr_ref_tag[token];
    uint payload = type_expr_ref_payload[token];
    if (tag == TYPE_REF_SCALAR) return payload;

    // Classify inherent impl aliases from their normalized declaration refs.
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (tag != TYPE_REF_INSTANCE || payload >= capacity ||
        type_instance_kind[payload] != 1u || type_instance_arg_count[payload] != 0u) return 0u;
    token = type_instance_decl_token[payload];
    if (!valid_token(token)) return 0u;
    owner = type_decl_hir_node_by_token[token];
    if (!valid_compact_hir(owner)) return 0u;
    uint kind = compact_hir_core[owner].kind;
    return kind == 26u ? TY_STRUCT_BASE + token : kind == 27u ? TY_ENUM_BASE + token : 0u;
}

#endif

#if PREDICATE_BOUND_ARGUMENT_VALIDATION || PREDICATE_COLLECT_IMPL_RECORDS
uint direct_type_arg_count(uint owner_type_node)
{
    if (!valid_node(owner_type_node))
        return 0u;
    uint count = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    HirRange range = compact_type_arg_ranges[owner_type_node];
    return range.start <= count && range.count <= count - range.start ? range.count : 0u;
}

uint direct_type_arg_node(uint owner_type_node, uint ordinal)
{
    if (!valid_node(owner_type_node))
        return INVALID;

    uint count = direct_type_arg_count(owner_type_node);
    if (ordinal >= count)
        return INVALID;

    HirRange range = compact_type_arg_ranges[owner_type_node];
    uint total = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    if (range.start > total || range.count > total - range.start)
        return INVALID;
    uint row = range.start + ordinal;
    return compact_type_args[row].value;
}
#endif

#if PREDICATE_COLLECT_IMPL_RECORDS

uint direct_type_arg_scalar_token(uint owner_type_node, uint ordinal)
{
    if (!valid_node(owner_type_node))
        return INVALID;

    uint leaf = compact_hir_semantic_facts[owner_type_node].type_path_leaf;
    uint leaf_token = valid_node(leaf) ? compact_hir_core[leaf].token_start : INVALID;
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

#endif

#if PREDICATE_COLLECT_IMPL_RECORDS

// The hash context is the exact implementation HIR. Identity-preserving
// substitution validates lexical ownership without closing the pattern.
// Source graph slot validity alone cannot prove that a leaf belongs to this impl.
bool impl_parameter_owned(uint impl_node, uint reference, bool constant)
{
    if (!valid_node(impl_node) || !valid_token(reference)) return false;
    uint kind = constant ? 2u : GENERIC_PARAM_KIND_TYPE;
    uint row = generic_param_row_for_name(impl_node, reference, kind);
    uint count = active_generic_param_count();
    HirRange range = compact_generic_param_ranges[impl_node];
    if (range.start > count || range.count > count - range.start ||
        row < range.start || row - range.start >= range.count ||
        row >= count || generic_param_token[row] != reference) return false;
    return constant ? type_const_param_slot_by_token[reference] < 32u :
        type_generic_param_slot_by_token[reference] < 32u;
}

struct ImplValidationGraph : IParameterScopedTypeGraph
{
    static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    static bool parameter_is_valid(uint reference, bool constant)
    {
        return valid_token(reference) && (constant
            ? type_const_param_slot_by_token[reference] < 32u
            : type_generic_param_slot_by_token[reference] < 32u);
    }
    static bool substitute_type_parameter(uint impl_node, uint reference,
        out uint tag, out uint payload)
    {
        tag = TYPE_REF_GENERIC_PARAM; payload = reference;
        return impl_parameter_owned(impl_node, reference, false);
    }
    static bool substitute_constant_parameter(uint impl_node, uint reference,
        out uint kind, out uint value)
    {
        kind = 2u; value = reference;
        return impl_parameter_owned(impl_node, reference, true);
    }
    static uint metadata(uint instance, uint field)
    { return PredicateDeclarationGraph.metadata(instance, field); }
    static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return PredicateDeclarationGraph.argument(instance, slot, tag, payload); }
}

bool impl_type_is_well_formed(uint impl_node, uint expr_node)
{
    uint2 root = predicate_type_reference(expr_node);
    // Scalars and parameters cannot acquire operands by appending syntax.
    // Structural and nominal graphs retain their complete ordered children.
    if (root.x == TYPE_REF_SCALAR)
    {
        if (root.y == 0u || root.y >= TY_STRUCT_BASE ||
            direct_type_arg_count(expr_node) != 0u) return false;
    }
    else if (root.x == TYPE_REF_GENERIC_PARAM)
    {
        if (direct_type_arg_count(expr_node) != 0u) return false;
    }
    else if (root.x != TYPE_REF_INSTANCE) return false;
    uint hash;
    return scoped_type_ref_hash<ImplValidationGraph>(root.x, root.y,
        impl_node, checked_type_capacity(), gParams.n_tokens, hash);
}

bool record_impl_parameter(uint owner, uint reference, bool constant, inout uint2 used)
{
    if (!impl_parameter_owned(owner, reference, constant)) return false;
    uint slot = constant ? type_const_param_slot_by_token[reference]
        : type_generic_param_slot_by_token[reference];
    if (constant) used.y |= 1u << slot;
    else used.x |= 1u << slot;
    return true;
}

// Ownership and complete shape were checked by ImplValidationGraph above.
// This bounded inventory walk records exact owned parameter occurrences in the
// head only. Bounds never contribute to inferability. Slots are a compact set
// representation after exact declaration-token/range ownership validation.
uint record_impl_head_parameters(uint owner, uint expr_node,
    inout uint2 used, inout uint visits)
{
    static const uint DEPTH_LIMIT = 64u;
    static const uint VISIT_LIMIT = 65536u;
    uint2 refs[DEPTH_LIMIT];
    uint next[DEPTH_LIMIT];
    uint counts[DEPTH_LIMIT];
    uint depth = 0u;
    refs[0u] = predicate_type_reference(expr_node);
    next[0u] = INVALID;
    for (;;)
    {
        uint2 reference = refs[depth];
        if (next[depth] == INVALID)
        {
            if (++visits > VISIT_LIMIT) return PREDICATE_STATUS_IMPL_HEAD_WORK_LIMIT;
            next[depth] = 0u;
            counts[depth] = 0u;
            if (reference.x == TYPE_REF_GENERIC_PARAM)
            {
                if (!record_impl_parameter(owner, reference.y, false, used))
                    return PREDICATE_STATUS_INVALID_IMPL_ARG;
            }
            else if (application_argument_is_constant(reference.x))
            {
                uint kind = reference.x & ~APPLICATION_CONSTANT_ARGUMENT;
                if (kind == 2u && !record_impl_parameter(owner, reference.y, true, used))
                    return PREDICATE_STATUS_INVALID_IMPL_ARG;
                if (kind != 1u && kind != 2u) return PREDICATE_STATUS_INVALID_IMPL_ARG;
            }
            else if (reference.x == TYPE_REF_INSTANCE)
            {
                if (reference.y >= checked_type_capacity()) return PREDICATE_STATUS_INVALID_IMPL_ARG;
                uint kind = PredicateDeclarationGraph.metadata(reference.y, 0u);
                if (kind == 1u)
                    counts[depth] = PredicateDeclarationGraph.metadata(reference.y, 2u);
                else if (kind == 2u || kind == 3u || kind == 4u)
                {
                    counts[depth] = 1u;
                    if (kind == 2u && PredicateDeclarationGraph.metadata(reference.y, 5u) == 2u &&
                        !record_impl_parameter(owner, PredicateDeclarationGraph.metadata(reference.y, 6u), true, used))
                        return PREDICATE_STATUS_INVALID_IMPL_ARG;
                }
                else return PREDICATE_STATUS_INVALID_IMPL_ARG;
            }
            else if (reference.x != TYPE_REF_SCALAR) return PREDICATE_STATUS_INVALID_IMPL_ARG;
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return PREDICATE_STATUS_OK;
            depth--;
            continue;
        }
        uint slot = next[depth]++;
        uint2 child;
        if (PredicateDeclarationGraph.metadata(reference.y, 0u) == 1u)
        {
            if (!PredicateDeclarationGraph.argument(reference.y, slot, child.x, child.y))
                return PREDICATE_STATUS_INVALID_IMPL_ARG;
        }
        else child = uint2(PredicateDeclarationGraph.metadata(reference.y, 3u),
            PredicateDeclarationGraph.metadata(reference.y, 4u));
        if (depth + 1u == DEPTH_LIMIT) return PREDICATE_STATUS_IMPL_HEAD_WORK_LIMIT;
        depth++;
        refs[depth] = child;
        next[depth] = INVALID;
    }
}

uint validate_trait_impl_parameter_coverage(uint owner, uint subject, uint trait_root, uint argument_count)
{
    HirRange range = compact_generic_param_ranges[owner];
    if (range.count == 0u) return PREDICATE_STATUS_OK;
    uint count = active_generic_param_count();
    if (range.count > 64u || range.start > count || range.count > count - range.start)
        return PREDICATE_STATUS_INVALID_IMPL_ARG;
    uint2 declared = uint2(0u, 0u);
    for (uint ordinal = 0u; ordinal < range.count; ordinal++)
    {
        uint row = range.start + ordinal;
        uint kind = generic_param_kind[row];
        uint2 before = declared;
        if ((kind != 1u && kind != 2u) ||
            !record_impl_parameter(owner, generic_param_token[row], kind == 2u, declared) ||
            all(before == declared)) return PREDICATE_STATUS_INVALID_IMPL_ARG;
    }
    uint2 used = uint2(0u, 0u);
    uint visits = 0u;
    uint status = record_impl_head_parameters(owner, subject, used, visits);
    if (status != PREDICATE_STATUS_OK) return status;
    for (uint ordinal = 0u; ordinal < argument_count; ordinal++)
    {
        status = record_impl_head_parameters(owner,
            predicate_argument_node(trait_root, ordinal), used, visits);
        if (status != PREDICATE_STATUS_OK) return status;
    }
    return all(used == declared) ? PREDICATE_STATUS_OK : PREDICATE_STATUS_UNCONSTRAINED_IMPL_PARAMETER;
}

void mark_direct_type_arg_syntax_tokens(uint expr_node, uint arg_count)
{
    for (uint ordinal = 0u; ordinal < arg_count; ordinal += 1u)
    {
        uint arg_node = direct_type_arg_node(expr_node, ordinal);
        uint token = valid_node(arg_node) ? type_path_leaf_token(arg_node) : INVALID;
        if (!valid_token(token) && valid_node(arg_node))
            token = compact_hir_core[arg_node].token_start;
        if (!valid_token(token))
            token = direct_type_arg_scalar_token(expr_node, ordinal);
        mark_predicate_syntax_token(token);

    }
}

uint validate_inherent_impl_target_type(uint impl_node, uint expr_node)
{
    if (valid_node(expr_node) && impl_type_is_well_formed(impl_node, expr_node))
        return PREDICATE_STATUS_OK;

    // Keep path-specific diagnostics for unresolved declarations and missing
    // operands. Structural targets do not have a path leaf or nominal owner.
    if (!type_path_scan_supported(expr_node))
        return PREDICATE_STATUS_IMPL_TARGET_ARG_SHAPE;

    uint segment_count = type_path_segment_count(expr_node);
    if (segment_count == 0u)
        return PREDICATE_STATUS_IMPL_TARGET_PATH_MISSING;

    uint leaf_token = type_path_leaf_token(expr_node);
    uint leaf_name_id = valid_token(leaf_token) ? name_id_by_token[leaf_token] : INVALID;
    uint arg_count = direct_type_arg_count(expr_node);
    if (segment_count == 1u && language_type_exists_by_name(leaf_name_id))
        return PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;

    uint decl_i = type_decl_for_type_path(expr_node);
    if (decl_i == INVALID || decl_i >= decl_record_count())
        return PREDICATE_STATUS_IMPL_TARGET_DECL_MISSING;
    if (!supported_predicate_type_arg_decl(decl_i))
        return PREDICATE_STATUS_IMPL_TARGET_DECL_KIND;

    uint decl_node = decl_hir_node[decl_i];
    // A nominal application's arity includes both declared operand domains.
    // Type slots stay independent for trait bounds and method substitution.
    uint owner_token = valid_compact_hir(decl_node) ? compact_decl_name_token(decl_node) : INVALID;
    uint expected_arg_count = valid_compact_hir(decl_node)
        ? generic_type_param_count_for_compact_decl(decl_node)
        : INVALID;
    if (expected_arg_count != INVALID && valid_token(owner_token))
        expected_arg_count += type_decl_const_param_count_by_owner_token[owner_token];
    if (expected_arg_count == INVALID)
        return PREDICATE_STATUS_IMPL_TARGET_DECL_IDENTITY;
    if (expected_arg_count != arg_count)
        return PREDICATE_STATUS_IMPL_TARGET_ARITY;
    return PREDICATE_STATUS_IMPL_TARGET_ARG_SHAPE;
}

bool trait_impl_header_is_public(uint impl_node)
{
    if (!valid_node(impl_node))
        return false;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (impl_node < count && compact_hir_payload[impl_node].d == HIR_ITEM_VIS_PUBLIC)
        return true;

    uint parent_i = parent_node(impl_node);
    return valid_node(parent_i) &&
           compact_hir_semantic_facts[parent_i].semantic_kind == HIR_SEMANTIC_PUBLIC_IMPL;
}

bool trait_impl_header_visibility_matches_trait(uint trait_decl_i, uint impl_node)
{
    if (trait_reference_is_dependency(trait_decl_i))
        return trait_impl_header_is_public(impl_node);
    if (trait_decl_i >= decl_record_count())
        return false;
    bool trait_is_public = decl_visibility[trait_decl_i] == HIR_ITEM_VIS_PUBLIC;
    bool impl_is_public = trait_impl_header_is_public(impl_node);
    return trait_is_public == impl_is_public;
}

uint impl_receiver_type_node(uint impl_node)
{
    uint type_node = valid_node(impl_node)
        ? compact_hir_semantic_facts[impl_node].method_impl_receiver_type
        : INVALID;
    return valid_node(type_node) ? type_node : INVALID;
}

uint direct_type_expr_child(uint node, uint ordinal)
{
    if (!valid_node(node) || ordinal != 0u ||
        compact_hir_semantic_facts[node].semantic_kind != HIR_SEMANTIC_IMPL_TRAIT)
        return INVALID;
    uint trait_type = predicate_trait_impl_trait_type_node[node];
    return valid_node(trait_type) &&
           compact_hir_semantic_facts[trait_type].semantic_kind == HIR_SEMANTIC_TYPE_PATH
        ? trait_type
        : INVALID;
}

uint validate_trait_impl_type_args(uint impl_node, uint trait_type_node,
    uint target_type_node, out uint arg_count, out uint first_arg_token, out uint second_arg_token)
{
    arg_count = direct_type_arg_count(trait_type_node);
    first_arg_token = INVALID; second_arg_token = INVALID;
    if (arg_count > 32u) return PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH;
    for (uint ordinal = 0u; ordinal < arg_count; ordinal++)
    {
        uint node = predicate_argument_node(trait_type_node, ordinal);
        uint token = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
        if (ordinal == 0u) first_arg_token = token;
        if (ordinal == 1u) second_arg_token = token;
        if (!valid_node(node) || !impl_type_is_well_formed(impl_node, node))
        {
            second_arg_token = token;
            return predicate_type_reference(node).x != 0u
                ? PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE : PREDICATE_STATUS_INVALID_IMPL_ARG;
        }
    }
    return PREDICATE_STATUS_OK;
}

void validate_trait_impl_node(uint node)
{
    uint trait_type_node = direct_type_expr_child(node, 0u);
    uint target_type_node = impl_receiver_type_node(node);
    uint trait_token = type_path_leaf_token(trait_type_node);
    uint target_token = valid_node(target_type_node) ? compact_hir_core[target_type_node].token_start : INVALID;
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
        ? (impl_type_is_well_formed(node, target_type_node)
            ? PREDICATE_STATUS_OK : PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE)
        : PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE;

    predicate_owner_node[node] = node;
    predicate_bound_token[node] = trait_token;
    predicate_subject_token[node] = target_token;
    predicate_bound_arg_count[node] = trait_arg_count;
    predicate_bound_first_arg_token[node] = trait_arg0_token;
    predicate_bound_second_arg_token[node] = trait_arg1_token;
    mark_predicate_syntax_token(trait_token);
    mark_predicate_syntax_token(target_token);
    mark_predicate_syntax_token(trait_arg0_token);
    mark_predicate_syntax_token(trait_arg1_token);

    uint trait_decl_i = trait_reference_for_type_path(trait_type_node);
    if (!valid_node(trait_type_node) || !valid_token(trait_token) ||
        trait_decl_i == INVALID ||
        (!trait_reference_is_dependency(trait_decl_i) &&
         (decl_kind[trait_decl_i] != HIR_ITEM_KIND_TRAIT ||
          decl_namespace[trait_decl_i] != HIR_ITEM_NAMESPACE_TYPE)))
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }

    predicate_bound_reference[node] = trait_decl_i;

    // Predicate operands currently carry checked type graphs. A constant
    // header cannot be treated as another type slot just because arity agrees.
    if (trait_reference_is_dependency(trait_decl_i) && trait_reference_header(trait_decl_i, 2u) != 0u)
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_CONST_TRAIT;
        return;
    }

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

    // An implementation's header is retained separately from each method's
    // own header. Receiver/call inference must bind the complete composed
    // environment; program admission checks every inherited prerequisite.

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
    if (!trait_reference_is_dependency(trait_decl_i) && !valid_compact_hir(trait_node))
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }

    if (!trait_reference_is_dependency(trait_decl_i))
    {
        uint trait_name_token = compact_hir_payload[trait_node].b;
        if (!valid_token(trait_name_token))
        {
            predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
            return;
        }
        if (type_decl_const_param_count_by_owner_token[trait_name_token] != 0u)
        {
            predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_CONST_TRAIT;
            return;
        }
    }

    if (trait_arg_count != trait_reference_parameter_count(trait_decl_i))
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_ARITY_MISMATCH;
        return;
    }

    predicate_status[node] = validate_trait_impl_parameter_coverage(
        node, target_type_node, trait_type_node, trait_arg_count);
}

void validate_inherent_impl_header_node(uint node)
{
    uint receiver_type_node = impl_receiver_type_node(node);
    uint receiver_token = valid_node(receiver_type_node)
        ? compact_hir_core[receiver_type_node].token_start : INVALID;
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

    predicate_status[node] = PREDICATE_STATUS_OK;
    mark_predicate_syntax_token(receiver_token);
    mark_direct_type_arg_syntax_tokens(
        receiver_type_node,
        direct_type_arg_count(receiver_type_node));
}
#endif

#if PREDICATE_BOUND_ARGUMENT_VALIDATION

bool bound_type_arg_exists_but_is_inaccessible(uint owner_decl_node, uint expr_node)
{
    uint segment_count = bound_path_segment_count(expr_node);
    if (segment_count <= 1u)
        return false;

    uint module_i = find_module_for_bound_path_prefix(expr_node, segment_count - 1u);
    uint leaf_name_id = bound_path_segment_name_id(expr_node, segment_count - 1u);
    uint decl_i = find_type_decl_in_module(module_i, leaf_name_id);
    uint owner_module = owner_module_for_decl_node(owner_decl_node);
    return decl_i < decl_record_count() && !decl_visible_from_module(owner_module, decl_i);
}

uint validate_bound_type_args(uint owner_decl_node, uint predicate_expr_node,
    out uint arg_count, out uint first_arg_token, out uint second_arg_token)
{
    arg_count = direct_type_arg_count(predicate_expr_node);
    first_arg_token = INVALID; second_arg_token = INVALID;
    if (arg_count > 32u) return PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH;
    for (uint ordinal = 0u; ordinal < arg_count; ordinal++)
    {
        uint node = predicate_argument_node(predicate_expr_node, ordinal);
        uint token = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
        if (ordinal == 0u) first_arg_token = token;
        if (ordinal == 1u) second_arg_token = token;
        uint2 ref = predicate_type_reference(node);
        if (!predicate_type_is_well_formed(ref))
        {
            second_arg_token = token;
            return bound_type_arg_exists_but_is_inaccessible(owner_decl_node, node)
                ? PREDICATE_STATUS_INACCESSIBLE_BOUND_TYPE_ARG : PREDICATE_STATUS_INVALID_ARG;
        }
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
    predicate_bound_reference[node] = INVALID;
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
    if (compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_BOUND_PATH)
    {
        mark_predicate_syntax_token(bound_path_leaf_token(node));
        mark_predicate_syntax_token(predicate_bound_first_arg_token[node]);
        mark_predicate_syntax_token(predicate_bound_second_arg_token[node]);
        return;
    }

    if (compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_BOUND_REFERENCE)
        mark_predicate_syntax_token(compact_hir_core[node].token_start);
}
#endif
