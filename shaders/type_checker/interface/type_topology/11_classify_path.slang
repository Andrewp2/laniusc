// Convert checked path-type resolution into stable semantic type identity.
// Generic parameter payloads remain declaration-local slots until the member
// scatter assigns final stable member indices.

import external_type_identity;
import hir_records;
import atomics;

struct Params
{
    uint hir_capacity;
    uint decl_capacity;
    uint token_capacity;
    uint library_id;
    uint unit_id;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> interface_type_local_decl_by_hir;
StructuredBuffer<uint> public_decl_index_by_local;
RWStructuredBuffer<uint4> interface_type_path_classification;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_KIND_SCALAR = 1u;
static const uint TYPE_KIND_GENERIC_PARAMETER = 2u;
static const uint TYPE_KIND_DECLARATION = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
bool valid_token(uint token) { return token < gParams.token_capacity; }
bool classify_external(uint token, out uint4 classification)
{
    classification = uint4(0u, 0u, 0u, 0u);
    if (!valid_token(token) || !external_type_identity_valid(token))
        return false;
    classification = uint4(
        TYPE_KIND_DECLARATION,
        external_type_library_id[token],
        external_type_unit_id[token],
        external_type_local_index[token]);
    return true;
}
void fail(uint detail)
{
    atomic_u32_or(interface_status, 0u, 2048u);
    atomic_u32_min(interface_status, 1u, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gParams.hir_capacity)
        return;
    interface_type_path_classification[node] = uint4(0u, 0u, 0u, 0u);
    if (node >= min(compact_hir_count[0u], gParams.hir_capacity) ||
        compact_hir_core[node].kind != HIR_TYPE ||
        compact_hir_payload[node].a != HIR_TYPE_FORM_PATH)
        return;
    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token))
    {
        fail(node);
        return;
    }
    uint tag = type_expr_ref_tag[token];
    uint payload = type_expr_ref_payload[token];
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint parameter_token = valid_token(payload) ? payload : token;
        uint slot = type_generic_param_slot_by_token[parameter_token];
        if (slot == INVALID)
        {
            fail(node);
            return;
        }
        interface_type_path_classification[node] =
            uint4(TYPE_KIND_GENERIC_PARAMETER, slot, 0u, 0u);
        return;
    }
    uint external_token = INVALID;
    if (tag == TYPE_REF_EXTERNAL_CANONICAL)
        external_token = token;
    else if (tag == TYPE_REF_INSTANCE && valid_token(payload))
        external_token = payload;
    if (external_token != INVALID)
    {
        uint4 classification;
        if (!classify_external(external_token, classification))
        {
            fail(node);
            return;
        }
        interface_type_path_classification[node] = classification;
        return;
    }
    uint local = interface_type_local_decl_by_hir[node];
    if (local < gParams.decl_capacity)
    {
        uint persisted = public_decl_index_by_local[local];
        if (persisted >= gParams.decl_capacity)
        {
            fail(node);
            return;
        }
        interface_type_path_classification[node] =
            uint4(TYPE_KIND_DECLARATION, gParams.library_id, gParams.unit_id, persisted);
        return;
    }
    if (tag == TYPE_REF_SCALAR)
    {
        interface_type_path_classification[node] =
            uint4(TYPE_KIND_SCALAR, payload, 0u, 0u);
        return;
    }
    fail(node);
}
