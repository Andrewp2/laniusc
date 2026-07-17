// Append compact match-payload binders to the visible declaration table.
//
// The raw semantic-HIR scan deliberately excludes match payloads. Each compact
// payload row is already a dense binder HIR id associated with a compact arm;
// this pass writes it at raw_decl_count + payload_row without rediscovering the
// relation through parser-node indices.

import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirMatchArm { uint owner; uint pattern; uint result; uint ordinal; };
struct HirMatchPayload { uint arm; uint pattern; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_visible_decl_count_out;

RWStructuredBuffer<uint> hir_value_decl_name_present;
RWStructuredBuffer<uint> hir_visible_decl_owner_fn;
RWStructuredBuffer<uint> hir_visible_decl_name_id;
RWStructuredBuffer<uint> hir_visible_decl_token;
RWStructuredBuffer<uint> hir_visible_decl_scope_end;
RWStructuredBuffer<uint> hir_visible_decl_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 63u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count() { return min(token_count[0u], gParams.n_tokens); }
uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_arm_count() { return min(compact_match_arm_count[0u], gParams.n_hir_nodes); }
uint active_payload_count()
{
    return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
}
bool valid_token(uint token) { return token != INVALID && token < active_token_count(); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }

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
    HirMatchArm arm = compact_match_arms[payload.arm];
    if (!valid_hir(arm.result))
        return;

    uint binder_token = compact_hir_core[payload.pattern].token_start;
    if (!valid_token(binder_token))
        return;
    uint name_id = name_id_by_token[binder_token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return;

    uint raw_count = min(hir_visible_decl_count_out[0u], gParams.n_tokens);
    uint dst = raw_count + row;
    if (dst < raw_count || dst >= gParams.n_tokens)
        return;

    uint result_end = compact_hir_core[arm.result].token_end;
    uint scope_end = result_end == INVALID || result_end == 0u
        ? active_token_count()
        : min(result_end, active_token_count());
    atomic_u32_or(hir_value_decl_name_present, name_id, 1u);
    hir_visible_decl_owner_fn[dst] = enclosing_fn[binder_token];
    hir_visible_decl_name_id[dst] = name_id;
    hir_visible_decl_token[dst] = binder_token;
    hir_visible_decl_scope_end[dst] = scope_end;
    // There is no local-initializer exclusion relation for a match binder.
    hir_visible_decl_node[dst] = INVALID;
}
