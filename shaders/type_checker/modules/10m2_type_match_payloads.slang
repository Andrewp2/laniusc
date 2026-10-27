import type_checker.checked_canonical;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_api;
import type_checker.checked_type_graph;
import type_checker.checked_index_reference;
import type_checker.checked_pattern_path;
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
StructuredBuffer<uint> decl_kind;
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

// The row whose closure the last inference_value_reference left to the
// caller, or INVALID.
static uint inference_deferred_closure = 0xffffffffu;
#define INFERENCE_DEFERRED_CLOSURE 1
#include "../inference_expression_reference.slang"
#include "../checked_referent.slang"

// The checked reference of match `match_node`'s scrutinee, through
// references.
bool match_scrutinee(uint match_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID; payload = INVALID;
    if (!valid_hir(match_node)) return false;
    uint reference_depth;
    return inference_value_reference(compact_hir_payload[match_node].a, tag, payload) &&
        checked_referent_reference(tag, payload, reference_depth);
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

// How payload_ref completes a declared payload reference.
static const uint PAYLOAD_DIRECT = 3u;

// The declared reference of a payload binder, how it is completed
// (CHECKED_RESOLVE_* or PAYLOAD_DIRECT) and whether that reads the
// scrutinee. An imported variant's generic payload (`scrutinee_slot`) is
// the scrutinee's argument; a local variant's payload is substituted under
// the scrutinee's application when it binds the arm's own pattern.
bool payload_declared_ref(HirMatchPayload payload_row, HirMatchArm arm, out uint tag,
    out uint ref_payload, out uint mode, out uint scrutinee_slot, out uint enum_token)
{
    tag = TYPE_REF_INVALID; ref_payload = INVALID;
    mode = PAYLOAD_DIRECT; scrutinee_slot = INVALID; enum_token = INVALID;
    uint path = path_for_pattern(payload_row.parent_pattern);
    if (valid_path(path) &&
        resolved_dependency_value_metadata[path * 4u] == IMPORTED_PAYLOAD_VARIANT)
    {
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
        mode = CHECKED_RESOLVE_CLOSED;
        scrutinee_slot = projected_payload;
        return true;
    }
    uint variant_token;
    uint variant;
    if (!resolved_enum_variant(
            payload_row.parent_pattern,
            variant_token,
            enum_token,
            variant))
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
    if (!valid_token(type_head)) return false;
    tag = type_expr_ref_tag[type_head];
    ref_payload = type_expr_ref_payload[type_head];
    mode = CHECKED_RESOLVE_CHECKED;
    return true;
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
    uint mode; uint scrutinee_slot; uint enum_token;
    if (!payload_declared_ref(payload_row, arm, tag, ref_payload, mode, scrutinee_slot, enum_token))
        return false;
    if (mode == PAYLOAD_DIRECT) return true;
    uint context = INVALID;
    inference_deferred_closure = INVALID;
    if (mode == CHECKED_RESOLVE_CLOSED || payload_row.parent_pattern == arm.pattern)
    {
        // A scrutinee whose closure fails is unknown, and then every use
        // below fails; the closure is read with the other IDs.
        // A nested imported variant reads its slot from the enclosing
        // payload's type, which that payload's own binder row publishes.
        uint scrutinee_tag = TYPE_REF_INVALID; uint scrutinee = INVALID;
        bool known;
        if (payload_row.parent_pattern != arm.pattern)
        {
            uint parent_token = compact_hir_core[payload_row.parent_pattern].token_start;
            if (valid_token(parent_token))
            {
                scrutinee_tag = decl_type_ref_tag[parent_token];
                scrutinee = decl_type_ref_payload[parent_token];
            }
            known = scrutinee_tag != TYPE_REF_INVALID && scrutinee != INVALID;
        }
        else known = match_scrutinee(arm.owner, scrutinee_tag, scrutinee);
        bool application = known && scrutinee_tag == TYPE_REF_INSTANCE &&
            scrutinee < checked_type_capacity() && type_instance_kind[scrutinee] == 1u;
        if (mode == CHECKED_RESOLVE_CLOSED)
        {
            if (!application || !instance_arg_ref(scrutinee, scrutinee_slot, tag, ref_payload))
                return false;
        }
        else
        {
            // The arm's scrutinee is this variant's enum.
            if (application) context = scrutinee;
            if (application ? type_instance_decl_token[scrutinee] != enum_token
                : !(known && scrutinee_tag == TYPE_REF_SCALAR && scrutinee == TY_ENUM_BASE + enum_token))
                return false;
        }
    }
    // This kernel's one ID site: the scrutinee's deferred closure, the
    // payload's row and its environment.
    uint closure = CT_UNKNOWN; uint term = CT_UNKNOWN; uint env = CT_UNKNOWN;
    bool scoped = checked_resolve_scoped(mode, context);
    [loop]
    for (uint step = 0u; step < 3u; step++)
    {
        uint row = step == 0u ? inference_deferred_closure
            : step == 1u ? (tag == TYPE_REF_INSTANCE ? ref_payload : INVALID)
            : scoped ? context : INVALID;
        uint id = row < checked_type_capacity() ? OnDemandIds.id(TYPE_REF_INSTANCE, row) : CT_UNKNOWN;
        if (step == 0u) closure = id;
        else if (step == 1u) term = id;
        else env = id;
    }
    if (inference_deferred_closure != INVALID && !ct_closed(closure)) return false;
    if (!canonical_checked_resolve_ids(mode, tag, ref_payload, term, context, env, gParams.n_tokens,
        tag, ref_payload))
    {
        tag = TYPE_REF_INVALID;
        ref_payload = INVALID;
        return false;
    }
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
    bool changed = !checked_refs_known_equal(
        decl_type_ref_tag[binder_token], decl_type_ref_payload[binder_token], tag, ref_payload);
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
