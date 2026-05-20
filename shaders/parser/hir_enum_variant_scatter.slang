// Publish pointer-jumped enum variant owners, ordinals, and payload counts.

import atomics;
import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirEnum;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_variant_owner_a;
StructuredBuffer<uint> hir_variant_rank_a;
StructuredBuffer<uint> hir_variant_payload_owner_a;
StructuredBuffer<uint> hir_variant_payload_rank_a;

RWStructuredBuffer<uint> hir_variant_parent_enum;
RWStructuredBuffer<uint> hir_variant_ordinal;
RWStructuredBuffer<uint> hir_variant_payload_start;
RWStructuredBuffer<uint> hir_variant_payload_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirEnum.uses_ll1 != 0u ? min(gHirEnum.n, ll1_status[5u])
                                   : gHirEnum.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

void publish_variant(uint node)
{
    uint owner = hir_variant_owner_a[node];
    if (!valid_node(owner))
        return;

    hir_variant_parent_enum[node] = owner;
    hir_variant_ordinal[node] = hir_variant_rank_a[node];
}

void publish_payload_type(uint node)
{
    uint owner = hir_variant_payload_owner_a[node];
    if (!valid_node(owner))
        return;

    atomic_u32_min(hir_variant_payload_start, owner, node);
    atomic_u32_max(
        hir_variant_payload_count,
        owner,
        hir_variant_payload_rank_a[node] + 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirEnum.n || !valid_node(node))
        return;

    if (node_kind[node] == PROD_ENUM_VARIANT)
        publish_variant(node);

    publish_payload_type(node);
}
