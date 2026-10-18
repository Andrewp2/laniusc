import primitive_types;
// Join immutable complete arm types. The first arm's lane owns each match;
// pending arms defer publication, and complete mismatches are diagnosed.
import hir_records;
import hir_expr_semantics;
import status;
import type_checker.checked_index_reference;
import type_checker.checked_canonical;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_api;
import type_checker.checked_type_graph;
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> type_decl_generic_param_count;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;
static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TY_ENUM_BASE = 6144u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
[ForceInline]
uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_arm_count() { return min(compact_match_arm_count[0u], gParams.n_hir_nodes); }
[ForceInline]
bool valid_hir(uint node) { return node < active_hir_count(); }
[ForceInline]
bool valid_token(uint token) { return token < gParams.n_tokens; }
// The row whose closure the last inference_value_reference left to the
// caller, or INVALID.
static uint inference_deferred_closure = 0xffffffffu;
#define INFERENCE_DEFERRED_CLOSURE 1
#include "../inference_expression_reference.slang"
uint enum_variant_type_for_node(uint node)
{
    if (!valid_hir(node))
        return TY_UNKNOWN;
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    uint path = path_id_by_owner_hir[node];
    if (path >= path_count || resolved_value_status[path] != PATH_RESOLVE_STATUS_OK)
        return TY_UNKNOWN;
    uint variant_decl = resolved_value_decl[path];
    if (variant_decl >= gParams.n_hir_nodes ||
        decl_kind[variant_decl] != HIR_ITEM_KIND_ENUM_VARIANT)
        return TY_UNKNOWN;
    uint enum_decl = decl_parent_type_decl[variant_decl];
    if (enum_decl >= gParams.n_hir_nodes || decl_kind[enum_decl] != HIR_ITEM_KIND_ENUM)
        return TY_UNKNOWN;
    uint enum_token = decl_name_token[enum_decl];
    return valid_token(enum_token) ? TY_ENUM_BASE + enum_token : TY_UNKNOWN;
}


// The checked result of an inferred arm, and its ID (CT_UNKNOWN unless a
// row); the deferred closure and the ID are read at this kernel's one ID
// site.
bool inferred_arm_reference(uint node, out uint tag, out uint payload, out uint id)
{
    inference_deferred_closure = INVALID;
    bool known = inference_value_reference(node, tag, payload, false);
    uint closure = CT_UNKNOWN; id = CT_UNKNOWN;
    [loop]
    for (uint step = 0u; step < 2u; step++)
    {
        uint row = step == 0u ? inference_deferred_closure : tag == 3u ? payload : INVALID;
        uint row_id = known && row < checked_type_capacity() ? OnDemandIds.id(3u, row) : CT_UNKNOWN;
        if (step == 0u) closure = row_id;
        else id = row_id;
    }
    return known && (inference_deferred_closure == INVALID || ct_closed(closure));
}

bool complete_arm_reference(uint node, out uint tag, out uint payload, out uint id)
{
    if (inferred_arm_reference(node, tag, payload, id)) return true;
    id = CT_UNKNOWN;
    if (!valid_hir(node)) return false;
    HirCore core = compact_hir_core[node];
    HirPayload value = compact_hir_payload[node];
    uint legacy = 0u;
    // Unit variants and ordinary monomorphic leaves use existing nominal or
    // primitive identities. Symbolic generic codes are never concrete leaves.
    if (core.kind == 22u || core.kind == 33u)
    {
        legacy = enum_variant_type_for_node(node);
        if (legacy == 0u && call_inference_state[0u] == 0u)
        {
            uint token = value.d < gParams.n_tokens ? value.d : core.token_start;
            if (valid_token(token)) legacy = visible_type[token];
        }
    }
    else if (core.kind == 28u && valid_token(core.token_start))
        legacy = visible_type[core.token_start];
    else if (core.kind == 19u && valid_hir(value.a))
    {
        HirCore callee = compact_hir_core[value.a];
        HirPayload callee_value = compact_hir_payload[value.a];
        uint token = callee.kind == 21u ? callee_value.c : callee_value.d;
        if (!valid_token(token)) token = callee.token_start;
        if (!valid_token(token)) return false;
        uint declaration = call_fn_index[token];
        if (valid_token(declaration) && type_decl_generic_param_count[declaration] != 0u)
            return false;
        legacy = call_return_type[token];
        if (!scalar_is_known(legacy)) return false;
    }
    if (legacy == 0u || legacy >= 8192u || (legacy >= 128u && legacy < 4096u)) return false;
    tag = 1u; payload = legacy; return true;
}
uint legacy_type_code(uint tag, uint payload)
{
    if (tag == 1u) return payload;
    if (tag == 2u && valid_token(payload))
    {
        uint slot = type_generic_param_slot_by_token[payload];
        return slot < 32u ? 8192u + slot : 0u;
    }
    if (tag != 3u || payload >= checked_type_capacity()) return 0u;
    if ((type_instance_kind[payload] == 2u || type_instance_kind[payload] == 3u) &&
        type_instance_elem_ref_tag[payload] == 1u && type_instance_elem_ref_payload[payload] < 128u)
        return 128u + type_instance_elem_ref_payload[payload];
    uint declaration = type_instance_decl_token[payload];
    return valid_token(declaration) ? visible_type[declaration] : 0u;
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint first = dtid.x + dtid.y * 16776960u;
    if (first >= active_arm_count()) return;
    HirMatchArm initial = compact_match_arms[first];
    if (!valid_hir(initial.owner) || compact_hir_core[initial.owner].kind != 34u) return;
    HirPayload match_value = compact_hir_payload[initial.owner];
    if (match_value.b != first) return;
    uint match_token = compact_hir_core[initial.owner].token_start;
    if (!valid_token(match_token) || match_value.c == 0u ||
        match_value.c > active_arm_count() - first)
    { record_min_token_error(status, valid_token(match_token) ? match_token : 0u, 6u, 34u); return; }
    // The match has the type of its arms that complete; an arm of type never
    // (a call of a `-> !` function) does not, and joins any type. A match
    // whose every arm is never is itself never.
    uint tag = 1u; uint payload = SCALAR_NEVER; uint id = CT_UNKNOWN;
    bool joined = false;
    for (uint ordinal = 0u; ordinal < match_value.c; ordinal++)
    {
        HirMatchArm arm = compact_match_arms[first + ordinal];
        uint next_tag; uint next_payload; uint next_id;
        if (arm.owner != initial.owner || !valid_hir(arm.result))
        { record_min_token_error(status, match_token, 6u, 34u); return; }
        uint result_token = compact_hir_core[arm.result].token_start;
        if (!complete_arm_reference(arm.result, next_tag, next_payload, next_id))
        {
            if (call_inference_state[0u] == 0u)
                record_min_token_error(status, valid_token(result_token) ? result_token : match_token, 6u, 0x474e0003u);
            return;
        }
        if (next_tag == 1u && next_payload == SCALAR_NEVER) continue;
        if (!joined) { tag = next_tag; payload = next_payload; id = next_id; joined = true; }
        else if (!checked_refs_equal_ids(tag, payload, id, next_tag, next_payload, next_id, gParams.n_tokens))
        {
            if (call_inference_state[0u] == 0u) record_min_token_error(status, result_token, 3u, 0u);
            return;
        }
    }
    decl_type_ref_tag[match_token] = tag;
    decl_type_ref_payload[match_token] = payload;
    call_return_type[match_token] = legacy_type_code(tag, payload);
}
