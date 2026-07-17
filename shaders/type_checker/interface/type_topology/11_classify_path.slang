// Convert checked path-type resolution into stable semantic type identity.
// Generic parameter payloads remain declaration-local slots until the member
// scatter assigns final stable member indices.

import atomics;

struct Params
{
    uint hir_capacity;
    uint decl_capacity;
    uint token_capacity;
    uint library_id;
    uint unit_id;
    uint dependency_type_count;
};
ConstantBuffer<Params> gParams;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_external_canonical;
StructuredBuffer<uint> dependency_type_words;
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
static const uint TYPE_WORDS = 9u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
bool valid_token(uint token) { return token < gParams.token_capacity; }
bool classify_external(uint canonical, out uint4 classification)
{
    classification = uint4(0u, 0u, 0u, 0u);
    if (canonical >= gParams.dependency_type_count)
        return false;
    uint base = canonical * TYPE_WORDS;
    uint kind = dependency_type_words[base];
    if (kind == TYPE_KIND_DECLARATION)
    {
        classification = uint4(
            TYPE_KIND_DECLARATION,
            dependency_type_words[base + 1u],
            dependency_type_words[base + 8u],
            dependency_type_words[base + 2u]);
        return true;
    }
    if (kind == TYPE_KIND_SCALAR)
    {
        classification = uint4(
            TYPE_KIND_SCALAR,
            dependency_type_words[base + 1u],
            0u,
            0u);
        return true;
    }
    return false;
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
    uint external = INVALID;
    if (tag == TYPE_REF_EXTERNAL_CANONICAL)
        external = payload;
    else if (tag == TYPE_REF_INSTANCE && valid_token(payload))
        external = type_instance_external_canonical[payload];
    if (external != INVALID)
    {
        uint4 classification;
        if (!classify_external(external, classification))
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
