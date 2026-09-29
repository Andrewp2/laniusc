// Validate imported unit enum patterns after inferred local type references
// have been published. Dependency pages are no longer available here, so the
// projector's stable nominal identity and checked ordinal are authoritative.

import hir_records;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_count;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_dependency_value_metadata;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> decl_imported_type_token;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint IMPORTED_UNIT_VARIANT = 9u;
static const uint IMPORTED_GENERIC_UNIT_VARIANT = 11u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_arm_count() { return min(compact_match_arm_count[0u], gParams.n_hir_nodes); }
uint active_path_count() { return min(path_count_out[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }
bool valid_path(uint path) { return path != INVALID && path < active_path_count(); }

uint path_for_pattern(uint pattern)
{
    if (!valid_hir(pattern)) return INVALID;
    uint path = path_id_by_owner_hir[pattern];
    if (valid_path(path)) return path;
    uint child = compact_hir_links[pattern].first_child;
    path = valid_hir(child) ? path_id_by_owner_hir[child] : INVALID;
    return valid_path(path) ? path : INVALID;
}

bool same_external_enum(uint expected_token, uint actual_token)
{
    return valid_token(expected_token) && valid_token(actual_token) &&
        external_type_library_id[expected_token] != INVALID &&
        external_type_library_id[actual_token] != INVALID &&
        external_type_unit_id[expected_token] != INVALID &&
        external_type_unit_id[actual_token] != INVALID &&
        external_type_local_index[expected_token] != INVALID &&
        external_type_local_index[actual_token] != INVALID &&
        external_type_library_id[expected_token] ==
            external_type_library_id[actual_token] &&
        external_type_unit_id[expected_token] ==
            external_type_unit_id[actual_token] &&
        external_type_local_index[expected_token] ==
            external_type_local_index[actual_token];
}

bool matches_scrutinee(uint match_node, uint pattern_token)
{
    if (!valid_hir(match_node)) return false;
    uint scrutinee = compact_hir_payload[match_node].a;
    if (!valid_hir(scrutinee)) return false;
    uint kind = compact_hir_core[scrutinee].kind;
    if (kind == HIR_CALL_EXPR)
    {
        uint callee = compact_hir_payload[scrutinee].a;
        if (!valid_hir(callee)) return false;
        HirCore callee_core = compact_hir_core[callee];
        HirPayload callee_payload = compact_hir_payload[callee];
        uint callee_token = callee_core.kind == HIR_MEMBER_EXPR
            ? callee_payload.c : callee_payload.d;
        if (!valid_token(callee_token)) callee_token = callee_core.token_start;
        return valid_token(callee_token) &&
            same_external_enum(pattern_token, call_return_type_token[callee_token]);
    }
    // Literals and other compound expressions have no nominal identity at
    // this boundary. They must not compare unrelated ordinal values.
    if (kind != HIR_NAME_EXPR && kind != HIR_PATH_EXPR && kind != HIR_MEMBER_EXPR)
        return false;
    uint token = kind == HIR_MEMBER_EXPR
        ? compact_hir_payload[scrutinee].c
        : compact_hir_core[scrutinee].token_start;
    if (!valid_token(token)) return false;
    uint declaration = visible_decl[token];
    if (!valid_token(declaration)) return false;
    uint tag = decl_type_ref_tag[declaration];
    uint type_token = INVALID;
    if (tag == TYPE_REF_INSTANCE)
    {
        uint instance = decl_type_ref_payload[declaration];
        if (valid_token(instance))
        {
            uint local_decl = type_instance_decl_token[instance];
            // Imported named instances have no local declaration token.
            type_token = valid_token(local_decl) ? local_decl : instance;
        }
    }
    else if (tag == TYPE_REF_EXTERNAL_CANONICAL)
    {
        uint imported = decl_imported_type_token[declaration];
        type_token = valid_token(imported) ? imported : declaration;
    }
    return same_external_enum(pattern_token, type_token);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_arm_count()) return;
    HirMatchArm arm = compact_match_arms[row];
    if (!valid_hir(arm.pattern)) return;
    uint path = path_for_pattern(arm.pattern);
    if (!valid_path(path))
        return;
    uint kind = resolved_dependency_value_metadata[path * 3u];
    if (kind != IMPORTED_UNIT_VARIANT && kind != IMPORTED_GENERIC_UNIT_VARIANT)
        return;
    uint pattern_token = compact_hir_core[arm.pattern].token_start;
    if (!valid_token(pattern_token) || path_owner_token[path] != pattern_token)
        return;
    if (compact_match_payload_count[row] != 0u ||
        !matches_scrutinee(arm.owner, pattern_token))
        record_min_token_error(status, pattern_token, ERR_ASSIGN_MISMATCH, 0u);
}
