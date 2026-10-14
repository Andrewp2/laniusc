import hir_records;
import hir_expr_semantics;
import type_checker.argument_context;
import type_checker.checked_type_graph;
import type_checker.scoped_type_equality;
import type_checker.checked_pattern_use;
import status;

// GPU HIR enum unit-variant consumer.
//
// Scheduling contract:
// - Dispatch after value status projection and after declaration records include
//   enum variants with parent enum declaration ids.
// - Consume resolved_value_decl/status path rows produced by the sorted
//   module/import resolver.
// - For resolved, non-call HIR paths to unit enum variants, including local
//   one-segment variants and qualified module variants, project the variant
//   declaration and enum type onto the path head, then clear any fail-closed
//   value-path status for that head.
// - Tuple/payload variants are deliberately left to the enum-call and
//   match-payload consumers; this pass only consumes unit variants.
// - It does not inspect source bytes, hash token text, scan for "::", perform
//   unqualified lookup, or ask the CPU to resolve values.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> resolved_value_type_qualifier_token;
StructuredBuffer<HirRange> compact_path_type_arg_ranges;
StructuredBuffer<uint> resolved_dependency_value_metadata;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> module_value_path_call_head;
StructuredBuffer<uint> module_value_path_expr_head;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> struct_init_field_expected_ref_tag;
StructuredBuffer<uint> struct_init_field_expected_ref_payload;
StructuredBuffer<uint> struct_init_field_expected_context_instance;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> type_instance_lookup_head;
StructuredBuffer<uint> type_instance_lookup_next;
StructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;

static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;

static const uint TY_ENUM_BASE = 6144u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[ForceInline]
uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_variant(uint row)
{
    return row != INVALID && row < min(compact_variant_count[0u], gParams.n_hir_nodes);
}

bool valid_unit_enum_variant_decl(uint decl_i, out uint variant_token, out uint enum_token)
{
    variant_token = INVALID;
    enum_token = INVALID;
    uint token_i = decl_name_token[decl_i];
    if (token_i == INVALID || token_i >= active_token_count())
        return false;

    uint variant = decl_hir_node[decl_i];
    if (!valid_variant(variant) || compact_variant_payload_count[variant] != 0u)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    uint enum_start = decl_name_token[enum_decl_i];
    if (enum_start == INVALID || enum_start >= active_token_count())
        return false;

    variant_token = token_i;
    enum_token = enum_start;
    return true;
}

static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
[ForceInline]
uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
[ForceInline]
bool valid_hir(uint node) { return node < active_hir_count(); }
[ForceInline]
bool valid_token(uint token) { return token < gParams.n_tokens; }
#include "../result_expression_context.slang"

bool unit_family_matches(uint2 reference, uint declaration, uint token, bool imported)
{
    if (reference.x != 3u || reference.y >= checked_type_capacity() ||
        type_instance_kind[reference.y] != 1u) return false;
    if (!imported) return type_instance_decl_token[reference.y] == declaration;
    return external_type_library_id[token] != INVALID &&
        external_type_library_id[reference.y] == external_type_library_id[token] &&
        external_type_unit_id[reference.y] == external_type_unit_id[token] &&
        external_type_local_index[reference.y] == external_type_local_index[token];
}

void publish_unit_reference(uint path, uint token, uint declaration, bool imported, bool generic)
{
    if (checked_token_in_match_pattern(token, active_hir_count(), compact_hir_core,
        compact_match_arm_count, compact_match_arms)) return;
    uint node = path_owner_hir[path];
    uint2 reference = uint2(3u, declaration);
    uint qualifier = resolved_value_type_qualifier_token[path];
    uint2 parent_reference = qualifier < gParams.n_tokens
        ? uint2(type_expr_ref_tag[qualifier], type_expr_ref_payload[qualifier]) : uint2(0u, INVALID);
    bool explicit_parent = qualifier < gParams.n_tokens &&
        (compact_path_type_arg_ranges[qualifier].count != 0u ||
         (parent_reference.x == 3u && (imported || parent_reference.y != declaration)));
    if (generic || explicit_parent)
    {
        // A pattern names a variant without constructing a value. Value uses
        // need a complete receiving application, including symbolic caller
        // parameters. They must never expose the enum's unbound header.
        if (module_value_path_expr_head[token] == 0u) return;
        uint parent = valid_hir(node) ? compact_hir_core[node].parent : INVALID;
        if (valid_hir(parent) && compact_hir_core[parent].kind == 22u) node = parent;
        uint2 receiving;
        bool has_receiving = result_expression_context<ScopedCheckedTypeGraph>(
            node, checked_type_capacity(), receiving);
        if (explicit_parent)
        {
            // The qualifier owns an ordinary checked nominal application.
            // It supplies missing context and constrains any receiving type.
            if (parent_reference.x != 3u || parent_reference.y >= checked_type_capacity() ||
                type_instance_state[parent_reference.y] != 1u)
            {
                if (call_inference_state[0u] == 0u)
                    record_min_token_error(status, token, 10u, 0xffffff09u);
                return;
            }
            reference = parent_reference;
            if (has_receiving && !scoped_type_refs_equal<ScopedCheckedTypeGraph>(
                reference.x, reference.y, INVALID, receiving.x, receiving.y, INVALID,
                checked_type_capacity(), gParams.n_tokens))
            {
                if (call_inference_state[0u] == 0u) record_min_token_error(status, token, 3u, 0u);
                return;
            }
        }
        else if (has_receiving) reference = receiving;
        else
        {
            if (call_inference_state[0u] == 0u) record_min_token_error(status, token, 6u, 0x474e0003u);
            return;
        }
    }
    else if (imported)
    {
        // The shared application producer copies a nongeneric dependency's
        // complete nominal type while its interface page is resident.
        if (!valid_hir(node)) return;
        reference = uint2(call_inference_result_tag[node], call_inference_result_payload[node]);
        if (reference.x == 0u) return;
    }
    if (!unit_family_matches(reference, declaration, token, imported))
    {
        if (call_inference_state[0u] == 0u) record_min_token_error(status, token, 3u, 0u);
        return;
    }
    bool changed = !scoped_type_refs_equal<ScopedCheckedTypeGraph>(
        type_expr_ref_tag[token], type_expr_ref_payload[token], INVALID,
        reference.x, reference.y, INVALID, checked_type_capacity(), gParams.n_tokens);
    type_expr_ref_tag[token] = reference.x;
    type_expr_ref_payload[token] = reference.y;
    if (changed) { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;
    uint owner_token = path_owner_token[path_i];
    if (owner_token >= gParams.n_tokens)
        return;
    if (module_value_path_call_head[owner_token] != 0u)
        return;
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;

    uint imported_kind = resolved_dependency_value_metadata[path_i * 4u];
    bool imported = imported_kind == 9u || imported_kind == 11u || imported_kind == 10u;
    uint variant_token = owner_token;
    uint enum_token = INVALID;
    bool generic = imported_kind == 11u;
    if (imported)
    {
        if (checked_token_in_match_pattern(owner_token, active_hir_count(), compact_hir_core,
            compact_match_arm_count, compact_match_arms)) return;
        if (imported_kind == 10u)
        {
            module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
            return;
        }
    }
    else
    {
        uint decl_i = resolved_value_decl[path_i];
        if (decl_i >= gParams.n_hir_nodes)
            return;
        if (decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_VALUE ||
            decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
            return;
        if (!valid_unit_enum_variant_decl(decl_i, variant_token, enum_token))
        {
            // A payload constructor cannot be used as a unit value.
            uint variant = decl_hir_node[decl_i];
            if (module_value_path_expr_head[owner_token] != 0u &&
                valid_variant(variant) && compact_variant_payload_count[variant] != 0u)
                module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
            return;
        }
        generic = type_instance_arg_count[enum_token] != 0u;
        visible_type[owner_token] = TY_ENUM_BASE + enum_token;
    }

    visible_decl[owner_token] = variant_token;
    publish_unit_reference(path_i, owner_token, enum_token, imported, generic);
    module_value_path_status[owner_token] = INVALID;
}
