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
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> hir_value_decl_name_present;
RWStructuredBuffer<uint> hir_visible_decl_flag;
RWStructuredBuffer<uint> hir_visible_decl_source_by_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 68u;

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
    if (!valid_hir(compact_match_arms[payload.arm].result))
        return;

    uint binder_token = compact_hir_core[payload.pattern].token_start;
    if (!valid_token(binder_token))
        return;
    uint name_id = name_id_by_token[binder_token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
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
