// Bind resolved enum patterns from compact match-arm and payload families.
//
// Every relation consumed here is in a declared domain: match and variant rows
// are compact family ids, node references are dense HIR ids, and declarations
// and visible bindings use declaration-row and token ids respectively.

import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirMatchArm { uint owner; uint pattern; uint result; uint ordinal; };
struct HirMatchPayload { uint arm; uint pattern; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_start;
StructuredBuffer<uint> compact_match_payload_count;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_WILDCARD = 19u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_ENUM_BASE = 6144u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_arm_count() { return min(compact_match_arm_count[0u], gParams.n_hir_nodes); }
uint active_payload_count() { return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes); }
uint active_variant_count() { return min(compact_variant_count[0u], gParams.n_hir_nodes); }
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
    if (!valid_hir(pattern))
        return INVALID;
    uint path = path_id_by_owner_hir[pattern];
    if (valid_path(path))
        return path;
    uint child = compact_hir_links[pattern].first_child;
    path = valid_hir(child) ? path_id_by_owner_hir[child] : INVALID;
    return valid_path(path) ? path : INVALID;
}

bool enum_variant_decl(
    uint decl_i,
    out uint variant_token,
    out uint enum_token,
    out uint variant)
{
    variant_token = INVALID;
    enum_token = INVALID;
    variant = INVALID;
    if (decl_i >= gParams.n_hir_nodes || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
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

void bind_decl(uint use_token, uint decl_token)
{
    if (!valid_token(use_token))
        return;
    visible_decl[use_token] = decl_token;
    module_value_path_status[use_token] = INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arm_i = linear_thread_id(dtid);
    if (arm_i >= active_arm_count())
        return;

    HirMatchArm arm = compact_match_arms[arm_i];
    if (!valid_hir(arm.owner) || !valid_hir(arm.pattern) || !valid_hir(arm.result))
        return;
    uint pattern_token = compact_hir_core[arm.pattern].token_start;
    if (!valid_token(pattern_token))
        return;
    if (token_is_wildcard(pattern_token))
    {
        bind_decl(pattern_token, pattern_token);
        visible_type[pattern_token] = TY_UNKNOWN;
        return;
    }

    uint path_i = path_for_pattern(arm.pattern);
    if (!valid_path(path_i) || resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;
    uint owner_token = path_owner_token[path_i];
    if (!valid_token(owner_token))
        return;

    uint variant_token;
    uint enum_token;
    uint variant;
    if (!enum_variant_decl(resolved_value_decl[path_i], variant_token, enum_token, variant))
        return;

    uint actual_count = compact_match_payload_count[arm_i];
    uint expected_count = compact_variant_payload_count[variant];
    if (actual_count != expected_count)
    {
        record_min_token_error(status, owner_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }

    bind_decl(owner_token, variant_token);
    visible_type[owner_token] = TY_ENUM_BASE + enum_token;

    if (actual_count == 0u)
        return;
    uint start = compact_match_payload_start[arm_i];
    if (start == INVALID || start >= active_payload_count())
        return;
    HirMatchPayload payload = compact_match_payloads[start];
    if (payload.arm != arm_i || payload.ordinal != 0u || !valid_hir(payload.pattern))
        return;
    uint binder_token = compact_hir_core[payload.pattern].token_start;
    if (valid_token(binder_token))
    {
        bind_decl(binder_token, binder_token);
        visible_type[binder_token] = TY_UNKNOWN;
    }
}
