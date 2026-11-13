// Publish compact match-payload binders by source-token anchor.
//
// Ordinary declarations and match binders share one token-indexed descriptor
// table. A later token-domain scan/scatter therefore materializes both kinds
// directly in source order.

import hir_records;
import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};


ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_match_pattern_payload_count;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> resolved_dependency_value_metadata;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;

RWStructuredBuffer<uint> hir_value_decl_name_present;
RWStructuredBuffer<uint> hir_visible_decl_flag;
RWStructuredBuffer<uint> hir_visible_decl_source_by_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 86u;
static const uint LANGUAGE_SYMBOL_WILDCARD = 19u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint IMPORTED_PAYLOAD_VARIANT = 10u;
static const uint IMPORTED_GENERIC_UNIT_VARIANT = 11u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[ForceInline]
uint active_token_count() { return min(token_count[0u], gParams.n_tokens); }
[ForceInline]
uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_arm_count() { return min(compact_match_arm_count[0u], gParams.n_hir_nodes); }
uint active_payload_count()
{
    return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
}
bool valid_token(uint token) { return token != INVALID && token < active_token_count(); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
uint active_path_count() { return min(path_count_out[0u], gParams.n_hir_nodes); }
bool valid_path(uint path) { return path != INVALID && path < active_path_count(); }

// A one-token payload pattern names an enum variant when its value path
// resolved to one, local or imported (the same test 10m binds patterns by).
bool pattern_names_variant(uint pattern, uint pattern_token)
{
    uint path = path_id_by_owner_hir[pattern];
    if (!valid_path(path))
    {
        uint child = compact_hir_links[pattern].first_child;
        path = valid_hir(child) ? path_id_by_owner_hir[child] : INVALID;
    }
    if (!valid_path(path) || resolved_value_status[path] != PATH_RESOLVE_STATUS_OK ||
        path_owner_token[path] != pattern_token)
        return false;
    uint imported_kind = resolved_dependency_value_metadata[path * 4u];
    if (imported_kind == HIR_ITEM_KIND_ENUM_VARIANT ||
        imported_kind == IMPORTED_GENERIC_UNIT_VARIANT ||
        imported_kind == IMPORTED_PAYLOAD_VARIANT)
        return true;
    uint decl_i = resolved_value_decl[path];
    return decl_i < gParams.n_hir_nodes && decl_kind[decl_i] == HIR_ITEM_KIND_ENUM_VARIANT;
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
    if (!valid_hir(compact_match_arms[payload.arm].result))
        return;

    uint binder_token = compact_hir_core[payload.pattern].token_start;
    if (!valid_token(binder_token))
        return;
    uint name_id = name_id_by_token[binder_token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return;
    // Only a single name binds. `_` and nested variant paths are matched,
    // not declared: as declarations, a later arm's same spelling would be
    // an out-of-scope use of them.
    // A nested variant's pattern node spans only its name token, so the span
    // alone does not tell `V(p)` or a unit `None` from a binder: a pattern
    // with payloads of its own, or one that resolves to a variant, is matched.
    if (compact_hir_core[payload.pattern].token_end != binder_token + 1u ||
        name_id == language_name_id[LANGUAGE_SYMBOL_WILDCARD] ||
        compact_match_pattern_payload_count[payload.pattern] != 0u ||
        pattern_names_variant(payload.pattern, binder_token))
        return;

    atomic_u32_or(hir_value_decl_name_present, name_id, 1u);
    uint encoded = 0x80000000u | (row + 1u);
    uint prior = atomic_u32_compare_exchange(
        hir_visible_decl_source_by_token,
        binder_token,
        0u,
        encoded);
    if (prior == 0u || prior == encoded)
        hir_visible_decl_flag[binder_token] = 1u;
}
