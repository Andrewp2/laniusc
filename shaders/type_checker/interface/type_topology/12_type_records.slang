// Emit fixed-width stable records from compacted topology and preclassified
// path identities. Descendants already have lower compacted indices.

import atomics;

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_hir_order;
StructuredBuffer<uint> interface_type_edge_prefix;
StructuredBuffer<uint> interface_type_edge_count;
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint4> interface_type_path_classification;
RWStructuredBuffer<uint> interface_types;
RWStructuredBuffer<uint> interface_status;

static const uint RECORD_WORDS = 9u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint HIR_TYPE_FORM_REF = 4u;
static const uint TYPE_KIND_ARRAY = 4u;
static const uint TYPE_KIND_SLICE = 5u;
static const uint TYPE_KIND_REFERENCE = 6u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
void fail(uint detail)
{
    atomic_u32_or(interface_status, 0u, 2048u);
    atomic_u32_min(interface_status, 1u, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = linear_thread_id(dtid);
    if (index >= min(interface_type_count[0u], gParams.hir_capacity))
        return;
    uint node = interface_type_hir_order[index];
    if (node >= gParams.hir_capacity)
    {
        fail(index);
        return;
    }
    uint form = compact_hir_payload[node].a;
    uint4 path = interface_type_path_classification[node];
    uint kind = form == HIR_TYPE_FORM_PATH ? path.x
              : form == HIR_TYPE_FORM_ARRAY ? TYPE_KIND_ARRAY
              : form == HIR_TYPE_FORM_SLICE ? TYPE_KIND_SLICE
              : form == HIR_TYPE_FORM_REF ? TYPE_KIND_REFERENCE : 0u;
    if (kind == 0u)
    {
        fail(node);
        return;
    }
    uint base = index * RECORD_WORDS;
    interface_types[base + 0u] = kind;
    interface_types[base + 1u] = path.y;
    interface_types[base + 2u] = path.w;
    interface_types[base + 3u] = interface_type_edge_prefix[index];
    interface_types[base + 4u] = interface_type_edge_count[index];
    interface_types[base + 5u] = 0u;
    interface_types[base + 6u] = 0u;
    interface_types[base + 7u] = 0u;
    interface_types[base + 8u] = path.z;
}
