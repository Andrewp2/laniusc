import type_checker.checked_scoped_types;
import type_checker.checked_type_graph;
import type_checker.checked_index_reference;
import type_checker.checked_pattern_path;
import type_checker.scoped_type_equality;
import hir_expr_semantics;
import hir_records;
import status;

// Substitute enum match payload types from compact HIR family rows.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<uint> compact_variant_payload_start;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> resolved_dependency_value_metadata;
StructuredBuffer<uint> resolved_dependency_variant_payload_records;
StructuredBuffer<uint> imported_match_payload_ref_tag;
StructuredBuffer<uint> imported_match_payload_ref_payload;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> module_value_path_status;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LEGACY_ARG_STRIDE = 4u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_CALL_EXPR = 19u;
static const uint IMPORTED_PAYLOAD_VARIANT = 10u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint LANGUAGE_SYMBOL_WILDCARD = 19u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[ForceInline]
uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_arm_count() { return min(compact_match_arm_count[0u], gParams.n_hir_nodes); }
uint active_payload_count() { return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes); }
uint active_variant_count() { return min(compact_variant_count[0u], gParams.n_hir_nodes); }
uint active_variant_payload_count() { return min(compact_variant_payload_row_count[0u], gParams.n_hir_nodes); }
uint active_path_count() { return min(path_count_out[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }
bool valid_path(uint path) { return path != INVALID && path < active_path_count(); }

bool token_is_wildcard(uint token)
{
    return valid_token(token) && name_id_by_token[token] != INVALID &&
           name_id_by_token[token] == language_name_id[LANGUAGE_SYMBOL_WILDCARD];
}

uint path_for_pattern(uint pattern)
{
    return checked_pattern_path(pattern, active_hir_count(), active_path_count(),
        compact_hir_links, path_id_by_owner_hir);
}

bool resolved_enum_variant(
    uint pattern,
    out uint variant_token,
    out uint enum_token,
    out uint variant)
{
    variant_token = INVALID;
    enum_token = INVALID;
    variant = INVALID;
    uint path = path_for_pattern(pattern);
    if (!valid_path(path) || resolved_value_status[path] != PATH_RESOLVE_STATUS_OK)
        return false;
    uint pattern_token = compact_hir_core[pattern].token_start;
    if (!valid_token(pattern_token) || path_owner_token[path] != pattern_token)
        return false;
    uint decl_i = resolved_value_decl[path];
    if (decl_i >= gParams.n_hir_nodes ||
        decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;
    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;
    variant_token = decl_name_token[decl_i];
    enum_token = decl_name_token[enum_decl_i];
    variant = decl_hir_node[decl_i];
    return valid_token(variant_token) && valid_token(enum_token) &&
           variant < active_variant_count();
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM && valid_token(payload))
    {
        uint slot = type_generic_param_slot_by_token[payload];
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    if (tag == TYPE_REF_INSTANCE && payload < checked_type_capacity())
    {
        uint decl_token = type_instance_decl_token[payload];
        return valid_token(decl_token) ? visible_type[decl_token] : TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

bool instance_arg_ref(uint instance_i, uint slot, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (instance_i >= checked_type_capacity() || slot >= type_instance_arg_count[instance_i])
        return false;
    uint start = type_instance_arg_row_start[instance_i];
    uint row = start == INVALID ? INVALID : start + slot;
    if (row != INVALID && row < type_instance_arg_row_count_out[0u])
    {
        tag = type_instance_arg_row_ref_tag[row];
        payload = type_instance_arg_row_ref_payload[row];
        if (tag != TYPE_REF_INVALID)
            return true;
    }
    if (slot >= LEGACY_ARG_STRIDE)
        return false;
    uint fixed = instance_i * LEGACY_ARG_STRIDE + slot;
    tag = type_instance_arg_ref_tag[fixed];
    payload = type_instance_arg_ref_payload[fixed];
    return tag != TYPE_REF_INVALID;
}

#include "../inference_expression_reference.slang"
#include "../checked_referent.slang"

bool scrutinee_context_for_match(uint match_node, uint enum_token, out uint instance_i)
{
    instance_i = INVALID;
    if (!valid_hir(match_node))
        return false;
    uint tag; uint payload;
    if (!inference_value_reference(compact_hir_payload[match_node].a, tag, payload)) return false;
    uint reference_depth;
    if (!checked_referent_reference(tag, payload, reference_depth)) return false;
    if (tag == TYPE_REF_INSTANCE && payload < checked_type_capacity() &&
        type_instance_kind[payload] == 1u)
    {
        instance_i = payload;
        return type_instance_decl_token[payload] == enum_token;
    }
    return tag == TYPE_REF_SCALAR && payload == TY_ENUM_BASE + enum_token;
}

uint imported_scrutinee_instance(uint match_node)
{
    if (!valid_hir(match_node)) return INVALID;
    uint tag; uint payload;
    uint reference_depth;
    return inference_value_reference(compact_hir_payload[match_node].a, tag, payload) &&
        checked_referent_reference(tag, payload, reference_depth) &&
        tag == TYPE_REF_INSTANCE && payload < checked_type_capacity() &&
        type_instance_kind[payload] == 1u ? payload : INVALID;
}

bool imported_payload_ref(HirMatchPayload payload_row, HirMatchArm arm,
                          uint path, out uint tag, out uint ref_payload)
{
    tag = TYPE_REF_INVALID;
    ref_payload = INVALID;
    if (payload_row.parent_pattern != arm.pattern) return false;
    if (valid_hir(payload_row.pattern))
    {
        uint completed_tag = imported_match_payload_ref_tag[payload_row.pattern];
        uint completed = imported_match_payload_ref_payload[payload_row.pattern];
        if ((completed_tag == TYPE_REF_SCALAR && completed != INVALID) ||
            (completed_tag == TYPE_REF_GENERIC_PARAM && valid_token(completed)) ||
            (completed_tag == TYPE_REF_INSTANCE && completed < checked_type_capacity()))
        {
            tag = completed_tag; ref_payload = completed;
            return true;
        }
    }
    uint record_base = path * 9u;
    uint count = resolved_dependency_variant_payload_records[record_base];
    if (payload_row.ordinal >= count || count > 4u) return false;
    uint payload_base = record_base + 1u + payload_row.ordinal * 2u;
    uint projected_tag = resolved_dependency_variant_payload_records[payload_base];
    uint projected_payload = resolved_dependency_variant_payload_records[payload_base + 1u];
    if (projected_tag == TYPE_REF_SCALAR)
    {
        tag = projected_tag;
        ref_payload = projected_payload;
        return projected_payload != INVALID;
    }
    if (projected_tag != TYPE_REF_GENERIC_PARAM) return false;
    uint instance = imported_scrutinee_instance(arm.owner);
    if (instance >= checked_type_capacity() ||
        !instance_arg_ref(instance, projected_payload, tag, ref_payload))
        return false;
    return (tag == TYPE_REF_SCALAR && ref_payload != INVALID) ||
        (tag == TYPE_REF_INSTANCE && checked_instance_is_closed(ref_payload));
}

bool enum_variant_for_arm(
    HirMatchArm arm,
    out uint enum_token,
    out uint variant)
{
    enum_token = INVALID;
    variant = INVALID;
    if (!valid_hir(arm.pattern))
        return false;
    uint pattern_token = compact_hir_core[arm.pattern].token_start;
    if (!valid_token(pattern_token))
        return false;
    uint variant_token = visible_decl[pattern_token];
    if (!valid_token(variant_token))
        return false;
    uint decl_i = decl_id_by_name_token[variant_token];
    if (decl_i >= gParams.n_hir_nodes || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;
    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;
    enum_token = decl_name_token[enum_decl_i];
    variant = decl_hir_node[decl_i];
    return valid_token(enum_token) && variant < active_variant_count();
}

void substituted_ref(uint instance_i, uint type_head, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(type_head))
        return;
    tag = type_expr_ref_tag[type_head];
    payload = type_expr_ref_payload[type_head];
    if (!checked_scoped_reference(tag, payload, instance_i, gParams.n_tokens, tag, payload))
    {
        tag = TYPE_REF_INVALID;
        payload = INVALID;
    }
}

bool payload_ref(HirMatchPayload payload_row, out uint tag, out uint ref_payload)
{
    tag = TYPE_REF_INVALID;
    ref_payload = INVALID;
    if (payload_row.arm >= active_arm_count())
        return false;
    HirMatchArm arm = compact_match_arms[payload_row.arm];
    if (!valid_hir(payload_row.parent_pattern))
        return false;
    uint path = path_for_pattern(payload_row.parent_pattern);
    if (valid_path(path) &&
        resolved_dependency_value_metadata[path * 4u] == IMPORTED_PAYLOAD_VARIANT)
        return imported_payload_ref(payload_row, arm, path, tag, ref_payload);
    uint variant_token;
    uint enum_token;
    uint variant;
    if (!resolved_enum_variant(
            payload_row.parent_pattern,
            variant_token,
            enum_token,
            variant))
        return false;
    uint instance_i = INVALID;
    if (payload_row.parent_pattern == arm.pattern &&
        !scrutinee_context_for_match(arm.owner, enum_token, instance_i))
        return false;
    uint count = compact_variant_payload_count[variant];
    uint start = compact_variant_payload_start[variant];
    if (payload_row.ordinal >= count || start == INVALID ||
        start + payload_row.ordinal >= active_variant_payload_count())
        return false;
    HirVariantPayload variant_payload = compact_variant_payloads[start + payload_row.ordinal];
    if (variant_payload.variant != variant ||
        variant_payload.ordinal != payload_row.ordinal ||
        !valid_hir(variant_payload.type_node))
        return false;
    uint type_head = compact_hir_core[variant_payload.type_node].token_start;
    substituted_ref(instance_i, type_head, tag, ref_payload);
    return tag != TYPE_REF_INVALID && ref_payload != INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_payload_count())
        return;
    HirMatchPayload payload = compact_match_payloads[row];
    if (payload.arm >= active_arm_count() || !valid_hir(payload.pattern))
        return;
    uint binder_token = compact_hir_core[payload.pattern].token_start;
    if (!valid_token(binder_token))
        return;
    uint variant_token;
    uint enum_token;
    uint variant;
    if (resolved_enum_variant(
            payload.pattern,
            variant_token,
            enum_token,
            variant))
        return;
    bool wildcard = token_is_wildcard(binder_token);
    if (!wildcard)
    {
        visible_decl[binder_token] = binder_token;
        module_value_path_status[binder_token] = INVALID;
    }
    uint tag;
    uint ref_payload;
    if (!payload_ref(payload, tag, ref_payload))
    {
        uint path = path_for_pattern(payload.parent_pattern);
        if (call_inference_state[0u] == 0u && valid_path(path) &&
            resolved_dependency_value_metadata[path * 4u] == IMPORTED_PAYLOAD_VARIANT)
            record_min_token_error(status, binder_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }
    bool changed = !scoped_type_refs_equal<ScopedCheckedTypeGraph>(
        decl_type_ref_tag[binder_token], decl_type_ref_payload[binder_token], INVALID,
        tag, ref_payload, INVALID, checked_type_capacity(), gParams.n_tokens);
    // Every payload occurrence owns its complete type, including `_`: later
    // payload offsets and template closure depend on ignored prefix fields.
    // This occurrence-local root does not introduce a lexical wildcard name.
    decl_type_ref_tag[binder_token] = tag;
    decl_type_ref_payload[binder_token] = ref_payload;
    if (changed) { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
    uint ty = type_ref_to_type_code(tag, ref_payload);
    if (!wildcard && ty != TY_UNKNOWN)
        visible_type[binder_token] = ty;
}
