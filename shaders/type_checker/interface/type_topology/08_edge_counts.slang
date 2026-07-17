// Publish the number of direct child edges for every compacted signature type.
// The following exclusive scan assigns a deterministic edge range per parent.

import atomics;

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_hir_order;
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirRange { uint start; uint count; };
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_type_arg_ranges;
RWStructuredBuffer<uint> interface_type_edge_count;
RWStructuredBuffer<uint> interface_status;

static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint HIR_TYPE_FORM_REF = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = linear_thread_id(dtid);
    if (index >= gParams.hir_capacity)
        return;
    interface_type_edge_count[index] = 0u;
    if (index >= min(interface_type_count[0u], gParams.hir_capacity))
        return;
    uint node = interface_type_hir_order[index];
    if (node >= gParams.hir_capacity)
    {
        atomic_u32_or(interface_status, 0u, 1024u);
        atomic_u32_min(interface_status, 1u, index);
        return;
    }
    uint form = compact_hir_payload[node].a;
    if (form == HIR_TYPE_FORM_PATH)
        interface_type_edge_count[index] = compact_type_arg_ranges[node].count;
    else if (form == HIR_TYPE_FORM_ARRAY || form == HIR_TYPE_FORM_SLICE ||
             form == HIR_TYPE_FORM_REF)
        interface_type_edge_count[index] = 1u;
    else if (form != HIR_TYPE_FORM_NONE)
    {
        atomic_u32_or(interface_status, 0u, 1024u);
        atomic_u32_min(interface_status, 1u, index);
    }
}
