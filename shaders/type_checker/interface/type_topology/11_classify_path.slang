// Convert checked path-type resolution into stable semantic type identity.
// Generic parameter payloads remain declaration-local slots until the member
// scatter assigns final stable member indices.

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
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> semantic_type_ref_tag_by_hir;
StructuredBuffer<uint> semantic_type_ref_payload_by_hir;
StructuredBuffer<uint> semantic_type_generic_param_slot_by_hir;
StructuredBuffer<uint> semantic_type_external_library_id_by_hir;
StructuredBuffer<uint> semantic_type_external_unit_id_by_hir;
StructuredBuffer<uint> semantic_type_external_local_index_by_hir;
StructuredBuffer<uint> interface_type_local_decl_by_hir;
StructuredBuffer<uint> public_decl_index_by_local;
RWStructuredBuffer<uint4> interface_type_path_classification;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_KIND_SCALAR = 1u;
static const uint TYPE_KIND_GENERIC_PARAMETER = 2u;
static const uint TYPE_KIND_DECLARATION = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
bool valid_token(uint token) { return token < gParams.token_capacity; }
uint path_leaf_token(uint node)
{
    uint path_count = min(compact_path_count[0u], gParams.hir_capacity);
    uint path = node < gParams.hir_capacity ? path_id_by_owner_hir[node] : INVALID;
    if (path >= path_count)
    {
        uint path_owner = node < gParams.hir_capacity ? compact_hir_payload[node].b : INVALID;
        path = path_owner < gParams.hir_capacity ? path_id_by_owner_hir[path_owner] : INVALID;
    }
    if (path >= path_count)
        return INVALID;
    HirPath record = compact_paths[path];
    uint segment_count = min(compact_path_segment_count[0u], gParams.token_capacity);
    if (record.segment_count == 0u || record.segment_start >= segment_count ||
        record.segment_count > segment_count - record.segment_start)
        return INVALID;
    return compact_path_segments[record.segment_start + record.segment_count - 1u].name_token;
}
void fail(uint detail)
{
    atomic_u32_or(interface_status, 0u, 16384u);
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
    uint token = path_leaf_token(node);
    if (!valid_token(token))
        token = compact_hir_core[node].token_start;
    if (!valid_token(token))
    {
        fail(0x10000000u | node);
        return;
    }
    uint tag = semantic_type_ref_tag_by_hir[node];
    uint payload = semantic_type_ref_payload_by_hir[node];
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = semantic_type_generic_param_slot_by_hir[node];
        if (slot == INVALID)
        {
            fail(0x20000000u | node);
            return;
        }
        interface_type_path_classification[node] =
            uint4(TYPE_KIND_GENERIC_PARAMETER, slot, 0u, 0u);
        return;
    }
    if (semantic_type_external_library_id_by_hir[node] != INVALID &&
        semantic_type_external_unit_id_by_hir[node] != INVALID &&
        semantic_type_external_local_index_by_hir[node] != INVALID)
    {
        interface_type_path_classification[node] = uint4(
            TYPE_KIND_DECLARATION,
            semantic_type_external_library_id_by_hir[node],
            semantic_type_external_unit_id_by_hir[node],
            semantic_type_external_local_index_by_hir[node]);
        return;
    }
    uint local = interface_type_local_decl_by_hir[node];
    if (local < gParams.decl_capacity)
    {
        uint persisted = public_decl_index_by_local[local];
        if (persisted >= gParams.decl_capacity)
        {
            // A private declaration can occur in a unit-local type forest
            // while collecting implementation details, but it is not part of
            // the exported interface artifact. Keep the classification empty
            // rather than treating that private path as a malformed public
            // declaration.
            interface_type_path_classification[node] = uint4(0u, 0u, 0u, 0u);
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
    fail(0x40000000u | ((tag & 0x0fu) << 24u) | (node & 0x00ffffffu));
}
